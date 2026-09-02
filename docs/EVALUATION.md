# Evaluation readiness — 42 "Inception"

> **Source note:** `www.42evalhub.com` is not reachable from this environment (blocked by network egress policy), so this checklist was compiled from the official 42 Common Core Inception subject requirements and cross-referenced against a public community evaluation guide ([42sp-cursus-inception/guides/Evaluation-en.md](https://github.com/caroldaniel/42sp-cursus-inception/blob/main/guides/Evaluation-en.md)), rather than scraped verbatim from evalhub. **Open the live evalhub page yourself and diff it against this list before your defense** — campus-specific evaluation sheets do vary in wording and occasionally in strictness.

Legend: ✅ compliant · ⚠️ verify / be ready to explain · ❌ fix before evaluation

## 🔴 Must-fix items

### 1. `WP_ADMIN_USER` contains the string "admin" ❌

`srcs/.env`:
```
WP_ADMIN_USER=admin
```
The Inception subject explicitly forbids an admin account whose **username or login contains "admin"** in any form/case (`admin`, `Admin`, `administrator`…) — evaluators are instructed to fail the project outright on this point alone, independent of everything else. `wordpress.sh` passes this straight to `wp core install --admin_user="$WP_ADMIN_USER"`, so the running site currently violates the rule.

**Fix:** rename it, e.g. `WP_ADMIN_USER=oilyine_owner` (anything not containing "admin"), then `make -C srcs re` (or drop the volume) so `wp core install` re-runs, or manually `docker exec wordpress wp --allow-root --path=/var/www/wordpress user update <id> --user_login=...` (note: `wp-cli` can't rename a login in place; easiest is to recreate the WP volume).

**Verify:**
```sh
docker exec -it wordpress wp --allow-root --path=/var/www/wordpress user list --role=administrator --fields=user_login
```

### 2. Secrets committed to git ❌ — both `.env` files, with real credentials

```sh
git ls-files | grep -i env
# .env
# srcs/.env
```
The subject requires secrets to live only in an `.env` file that is **not** pushed to the repository (`.gitignore` should exclude it) — Dockerfiles must stay credential-free (they already are ✅), but the `.env` itself leaking into git defeats the purpose and is a common, explicit fail point during defense ("why are your passwords on GitHub"). `.gitignore` at the repo root currently has no `.env` rule at all (it only excludes `.env.local`).

**Fix:**
```sh
git rm --cached .env srcs/.env
printf '.env\nsrcs/.env\n' >> .gitignore
```
then commit `.env.example`/`srcs/.env.example` templates (blank/placeholder values) instead, and rotate every credential currently in those files since they're in git history regardless.

## 🟡 Verify / be ready to explain

### The site is reached at `:8443`, not bare `:443`

`docker-compose.yml` correctly publishes `443:443`/`80:80` and NGINX correctly terminates TLS on `443` — that part is fully compliant. The `:8443` suffix only appears because of the **outer** NAT layer: `run-vm.sh` forwards the VM's `443` to host port `8443` (`HTTPS_HOST_PORT`). If you're evaluated from inside the VM (`https://localhost` / `https://oilyine.42.lu` directly against the VM's own network interface) it resolves on bare `443` with no port suffix — only the host-side, NAT'd access needs `:8443`. Know which context you'll be evaluated in and be ready to explain the NAT hop; if your campus expects the browser bar to show a bare `https://login.42.fr` with no port, evaluate from a shell *inside* the VM, or switch `run-vm.sh` to bridged/macvlan networking instead of user-mode NAT.

```sh
openssl s_client -connect oilyine.42.lu:8443 -tls1_2 </dev/null 2>/dev/null | grep -E "subject=|Protocol"
openssl s_client -connect oilyine.42.lu:8443 -tls1_1 </dev/null 2>&1 | tail -5   # handshake must fail — TLSv1.1 is not offered
```

### `make` (no arguments) at the repo root boots the VM installer, not the stack

The root `Makefile`'s first target is `install`, so a bare `make` triggers `UNATTENDED=1 ./install-vm.sh` — a multi-minute unattended OS install — rather than bringing up the Docker stack. This is a deliberate consequence of the two-layer design (VM host + Docker Compose stack inside it) but can surprise an evaluator who runs `make` expecting the site to come up in seconds. Walk them through `cd srcs && make up` explicitly, or add a documented `make help`/reordered default target if your campus expects `make` to fully deploy in one shot from a clean host.

### FTP passive-mode address

`srcs/requirements/bonus/ftp/conf/vsftpd.conf` sets `pasv_address=127.0.0.1`. Passive-mode clients are told to open the data connection to whatever `pasv_address` says — `127.0.0.1` only resolves correctly when the FTP client and server share the same network namespace. Connecting through the VM's `FTP_HOST_PORT` forward (or from any real remote client) will likely complete the login but hang or fail on `ls`/`get`/`put`. **Test this specific path before your defense**:
```sh
curl --ftp-ssl -k -u "$FTP_USER:$FTP_PWD" ftp://oilyine.42.lu:2121/ -v
```
If it hangs on `LIST`, set `pasv_address` to `$DOMAIN` (or the VM's routable address) and re-inject it via `sed`/envsubst in `ftp.sh` at container start, the same way `nginx.sh` templates `nginx.conf`.

### Volume host path includes an extra `Inception` segment

`docker-compose.yml` binds volumes to `/home/oilyine/Inception/data/{mariadb,wordpress,redis}` rather than the more literal `/home/oilyine/data/...` some evaluation sheets specifically look for. Functionally this is still a real, inspectable, host-persisted named volume (fully compliant with the "must be a Docker volume, not an anonymous/tmpfs mount" rule) — but if your sheet's wording is "volumes must be located at `/home/<login>/data`" literally, rename the path to match. Check with:
```sh
docker volume inspect srcs_wordpress_data --format '{{ .Mountpoint }}'
```

### `wp-config.php` under `requirements/wordpress/scripts/` is dead code

`srcs/requirements/wordpress/Dockerfile` only `COPY`s `wordpress.sh` — `wp-config.php` in the same directory is never copied into the image; the real config is generated at runtime via `wp config create`/`wp config set` in `wordpress.sh`. The unused file hardcodes a domain, DB placeholders and WordPress salts, which could confuse an evaluator skimming the repo into thinking config is static/hardcoded. Recommend deleting it, or clearly marking it unused, to keep the story simple: "config is generated at container start, from `.env`, full stop."

### Port 80 is exposed (redirect-only)

`nginx.conf`'s `:80` server block only issues a `301` to `:8443` and serves no content — this is the standard, broadly-accepted pattern for "NGINX must be the single entry point over TLS." A minority of evaluators interpret the subject as "port 80 must refuse connections outright." Have the one-line justification ready: *"port 80 is open only to redirect browsers to HTTPS; no application content is ever served over plaintext."*
```sh
curl -I http://oilyine.42.lu:8080/     # expect: HTTP/1.1 301 Moved Permanently → Location: https://…:8443/
```

## ✅ Confirmed compliant

Run each command to see it for yourself; they're grouped the way most evaluators walk the checklist.

**Structure**
- `srcs/docker-compose.yml` + one `Dockerfile` per service under `srcs/requirements/<service>/` — ✅ matches the required layout exactly.
- No pre-built application images anywhere (`FROM debian:bookworm` + `apt install nginx|mariadb-server|php-fpm|redis-server|vsftpd`, and Keycloak built from the official release tarball) — never `FROM nginx`, `FROM wordpress`, `FROM mariadb`, `FROM redis`, `FROM keycloak/keycloak` — ✅.
- No `:latest` tag on any base image (`debian:bookworm` everywhere, pinned) — ✅.
  ```sh
  grep -rn '^FROM' srcs/requirements
  ```
- No `network: host`, no `links:`, no privileged containers anywhere in `docker-compose.yml` — ✅.

**Runtime behavior**
- Every container's foreground process is the real service, not a keep-alive hack — no `tail -f /dev/null`, `sleep infinity`, or busy `while true` loops anywhere in the repo:
  ```sh
  grep -rn "sleep infinity\|tail -f /dev/null\|while true" srcs/requirements   # no matches
  ```
  `mariadb.sh` ends with `exec mariadbd --console`; `nginx.sh` with `exec nginx -g "daemon off;"`; `wordpress.sh` with `exec php-fpm8.2 -F`; `redis`'s `CMD` is `redis-server` directly; `ftp.sh` ends with `exec /usr/sbin/vsftpd`. `keycloak.sh` starts `kc.sh` in the background with an explicit `trap … TERM INT` and blocks on `wait "$KC_PID"` so it can run one-time realm provisioning first — PID 1 still correctly proxies signals and the container exits when the JVM does; this is a deliberate and commonly-accepted pattern (not a disguised keep-alive loop), but be ready to explain the two-step boot if asked.
- `restart: unless-stopped` on every mandatory/bonus service (not `restart: always`, which several campuses explicitly flag) — ✅.
- No secrets baked into any image at build time (no `ARG`/`ENV` password in any `Dockerfile`; everything arrives via `docker-compose.yml`'s `environment:` block from `srcs/.env` at container start) — confirm nothing leaks into a layer:
  ```sh
  docker history --no-trunc wordpress | grep -i pwd   # nothing
  ```

**NGINX / TLS**
- NGINX is the only container publishing the web ports (`443`, `80`); WordPress, MariaDB, Redis and Keycloak are unreachable except through the `inception` network — ✅.
- TLS restricted to `ssl_protocols TLSv1.2 TLSv1.3;` — no TLSv1/1.1, no plaintext HTTP for app content — ✅.
- Certificate generated locally with `openssl req -x509` at container start (no external CA dependency, appropriate since `oilyine.42.lu` isn't a certificate-authority-issuable domain) — ✅.

**WordPress**
- Fully unattended install via `wp-cli` — no browser install wizard — ✅.
- Two accounts: one administrator (`$WP_ADMIN_USER`, subject to the fix above) and one non-admin `author` (`$WP_USER`) — ✅ (count requirement met).
- Only `php-fpm` in the WordPress container; NGINX proxies `.php` requests via FastCGI to `wordpress:9000` — no embedded web/app server duplicating NGINX's job — ✅.
- DB credentials sourced from environment (`$WP_DB_*`), never hardcoded — ✅.

**MariaDB**
- `mariadb-install-db` bootstrap + `CREATE DATABASE`/`CREATE USER IF NOT EXISTS` from env vars, then hands off to the real `mariadbd` daemon in the foreground — ✅.
- Listens only on the `inception` network (`bind-address = 0.0.0.0` inside the container, but the port is never published to the host in `docker-compose.yml`) — ✅.
- `healthcheck:` (`mysqladmin ping`) gates `wordpress`'s and `adminer`'s `depends_on: condition: service_healthy` — ✅, avoids the classic "WordPress starts before the DB is ready" race (the additional `until mysql … SELECT 1` wait loop in `wordpress.sh` is a sound belt-and-suspenders check on top of that).

**Volumes & network**
- Exactly the two mandated named, host-persisted volumes (`mariadb_data` for `/var/lib/mysql`, `wordpress_data` for `/var/www/wordpress`), both inspectable with `docker volume ls`/`docker volume inspect`, both bind-mounted under the login's home directory (path caveat noted above) — ✅.
- Single user-defined bridge network (`inception`) shared by all seven containers, no per-service networks, no host networking — ✅.
  ```sh
  docker network ls | grep inception
  docker network inspect srcs_inception --format '{{ range .Containers }}{{ .Name }} {{ end }}'
  ```

## Bonus part

Bonus is only evaluated once the mandatory part scores full marks. This repo implements four bonus services — see **[docs/BONUS.md](BONUS.md)** for details and verification commands on each:

| Service | Implemented from scratch (no pre-built image)? | Notes |
|---|---|---|
| Redis cache | ✅ (`debian:bookworm` + `redis-server`) | Wired into WP via `redis-cache` plugin |
| FTP server | ✅ (`debian:bookworm` + `vsftpd`) | See the passive-mode caveat above |
| Adminer | ✅ (`debian:bookworm` + `php -S`, Adminer is a single downloaded PHP file, not a container image) | Reachable on plain HTTP, port `9090` |
| Keycloak (extra service, OIDC SSO) | ✅ (`debian:bookworm` + official release tarball, built with `kc.sh build`) | Realm/client/test user auto-provisioned; proxied through NGINX at `/auth/` |

## Suggested pre-defense run-through

```sh
cd srcs
make re                                              # clean rebuild from scratch
make ps                                              # all 7 containers "Up"/"healthy"
docker network ls | grep inception
docker volume ls | grep -E "mariadb_data|wordpress_data|redis_data"
curl -I http://oilyine.42.lu:8080/                   # 301 → https://…:8443
openssl s_client -connect oilyine.42.lu:8443 -tls1_2 </dev/null 2>/dev/null | grep subject=
docker exec -it wordpress wp --allow-root --path=/var/www/wordpress user list --fields=user_login,roles
docker exec -it mariadb mariadb -uroot -e "SHOW DATABASES;"
curl --ftp-ssl -k -u "$FTP_USER:$FTP_PWD" ftp://oilyine.42.lu:2121/ -v
docker exec -it redis redis-cli ping
```

Fix the two 🔴 items, confirm the FTP passive-mode path end-to-end, and rehearse the `:8443`/`make` explanations — the rest of the mandatory and bonus implementation is solid and matches the subject's expectations.
