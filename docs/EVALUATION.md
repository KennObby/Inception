# Evaluation readiness — 42 "Inception"

This checklist follows the actual 42 EvalHub scale for Inception (https://www.42evalhub.com/common/inception), section by section, worked through against this exact codebase. Each item is marked:

- **[x]** compliant, verified in the code.
- **[!]** procedural — depends on what happens live during the defense, not on the code.
- **[ ]** fixed in this pass, worth re-verifying once.

## Preliminaries

- *"The use of a local `.env` file to store info is allowed... credentials, API keys, or passwords available in the git repository and outside of secrets files created during the evaluation ends the evaluation, mark 0."*
  **[x]** `srcs/.env` (the file holding every real credential — DB, WordPress, FTP, Keycloak) is **not** tracked in git; it is listed in `.gitignore` (`/srcs/.env`). Only `srcs/.env.example`, with placeholder values, is committed. The root `.env` (VM/QEMU settings: ISO name, disk size, RAM, port numbers) contains no credentials, so it can stay tracked.
  Verify with a fresh clone:
  ```sh
  git clone <repo-url> /tmp/inception-check && grep -RIl "PWD=\|PASSWORD=\|SECRET=" /tmp/inception-check --include=*.env 2>/dev/null
  # should print nothing — srcs/.env doesn't exist in a fresh clone
  ```

## General instructions

- *"All files required to configure the application must be inside a `srcs` folder at the root of the repository."* **[x]** — `srcs/docker-compose.yml`, `srcs/requirements/**` hold the entire stack.
- *"A Makefile must be at the root of the repository."* **[x]** — root `Makefile` present; its `up`/`down` targets point at `srcs/docker-compose.yml`.
- *"There mustn't be `network: host` or `links:` in docker-compose.yml."* **[x]** — neither appears anywhere in `srcs/docker-compose.yml`.
- *"There must be `network(s)` in docker-compose.yml."* **[x]** — the `inception` bridge network is declared and used by every service.
- *"There mustn't be `--link` in the Makefile or any script using Docker."* **[x]** — not present anywhere in the repository.
- *"No `tail -f` or background command in the ENTRYPOINT; no bare `bash`/`sh` unless running a script."* **[x]** — every `ENTRYPOINT` runs a script (`mariadb.sh`, `nginx.sh`, `wordpress.sh`, `ftp.sh`, `keycloak.sh`) or the real binary directly (`adminer`'s `CMD`, `redis`'s `CMD`); none append `&` followed by an interactive shell.
- *"Entrypoint scripts must run no program in background."* **[x]** — `mariadb.sh` ends with `exec mariadbd --console`; `nginx.sh` with `exec nginx -g "daemon off;"`; `wordpress.sh` with `exec php-fpm8.2 -F`; `ftp.sh` with `exec /usr/sbin/vsftpd`. `keycloak.sh` starts `kc.sh` with `&` but then `trap` + `wait "$KC_PID"` blocks the script on it after one-time realm provisioning — the script's own lifetime is still tied 1:1 to the Keycloak process, not a fire-and-forget background job; be ready to walk the evaluator through this if asked.
- *"No infinite loop in any script (`sleep infinity`, `tail -f /dev/null`, `tail -f /dev/random`, etc.)."* **[x]**
  ```sh
  grep -rn "sleep infinity\|tail -f /dev/null\|tail -f /dev/random" srcs/   # no matches
  ```
- *"Containers must be built from the penultimate stable version of Alpine or Debian."* **[x]** — every `Dockerfile` starts with `FROM debian:bookworm`. Debian 13 ("trixie") is current stable; bookworm (12) is the penultimate ("oldstable") release, so this is correct as of this writing — **re-confirm this is still true on your evaluation date**, since Debian's stable release rotates.
  ```sh
  grep -rn '^FROM' srcs/requirements
  ```
- *"Run the Makefile."* **[!]** procedural — run `make -C srcs up` (or `cd srcs && make up`) and confirm all 7 containers come up clean. **Note:** a bare `make` at the repository root runs the VM-provisioning workflow (`install`), not the stack — see [DEV_DOC.md](../DEV_DOC.md#makefile-usage). Point the evaluator at `srcs/Makefile`'s `up` target explicitly, or use the root `Makefile`'s own `up` target (`make up` from the root also works, since it isn't the default/first target — only a bare `make` with no target picks `install`).

## Mandatory part — Activity overview **[!]**

Procedural — be ready to explain, in your own words:
- How Docker and Docker Compose work (images vs. containers, layers, the compose file as a declarative multi-container spec).
- The difference between a Docker image used with and without Compose (Compose adds declarative multi-container orchestration — networks, volumes, dependency ordering, single-command lifecycle — on top of the same image/container primitives `docker build`/`docker run` use directly).
- The benefit of Docker vs. VMs (shared host kernel → far lower overhead and faster startup than a full VM, at the cost of weaker isolation; this project's own optional VM layer, used only for personal development, is a good live example of the contrast).
- Why the required directory structure (`srcs/requirements/<service>/{Dockerfile, scripts, conf}`) makes sense: one build context and one concern per service, consistent with `docker-compose.yml`'s `build:` pointing at each subfolder.

## README check

- *"README.md at the root; first line (italicized): 'This project has been created as part of the 42 curriculum by \<login\>'; sections Description, Instructions, Resources (with AI-usage explanation)."*
  **[x]** — `README.md` opens with `*This project has been created as part of the 42 curriculum by oilyine.*` and has exactly `## Description`, `## Instructions`, `## Resources` (the last one documents how AI assistance was used, both for documentation and for the fixes described below).

## Documentation check

- *"USER_DOC.md and DEV_DOC.md at the root; USER_DOC covers start/stop, access to site/admin panel, credential management, basic checks; DEV_DOC covers prerequisites, setup, Makefile usage, docker compose commands, data persistence."*
  **[x]** — both files exist at the repository root and cover exactly those points; see [USER_DOC.md](../USER_DOC.md) and [DEV_DOC.md](../DEV_DOC.md).

## Simple setup

- *"NGINX accessible on port 443 only."* **[x]** — `srcs/docker-compose.yml`'s `nginx` service now publishes only `"443:443"`; the port-80 redirect server block has been removed from `nginx.conf` entirely, so `http://<DOMAIN>/` gets a connection refusal, not a redirect.
  ```sh
  curl -I http://<DOMAIN>/       # connection refused / times out
  ```
- *"A SSL/TLS certificate is used."* **[x]** — `nginx.sh` generates a self-signed cert with `openssl req -x509` at container start; `nginx.conf` sets `ssl_certificate`/`ssl_certificate_key` for the 443 server block.
- *"WordPress is properly installed and configured (no install wizard); reachable at `https://login.42.fr`; not reachable over `http://login.42.fr`."* **[x]** — `wordpress.sh` runs `wp core install` non-interactively before php-fpm ever serves a request; `WP_PUBLIC_URL` in `srcs/.env` is now `https://<DOMAIN>` with no port suffix, matching the bare-443 NGINX setup. Since NGINX only publishes 443, there is no `:8443`-style port in the URL the evaluator will type — it should be exactly `https://<your-login-domain>/`.

## Docker basics

- *"One Dockerfile per service, none empty."* **[x]** — 7 Dockerfiles under `srcs/requirements/{mariadb,nginx,wordpress,bonus/{redis,ftp,adminer,keycloak}}/`, none empty.
- *"Own Dockerfiles/images, no ready-made ones, no DockerHub pulls of the application itself."* **[x]** — every Dockerfile starts from a bare `debian:bookworm` base and installs/builds the service itself (`apt install mariadb-server|nginx|php-fpm|redis-server|vsftpd`, or Keycloak built from the official release tarball) — never `FROM nginx`, `FROM wordpress`, `FROM mariadb`, `FROM redis`, `FROM adminer`, or `FROM keycloak/keycloak`.
- *"Base image must start with `FROM alpine:X.X.X` or `FROM debian:XXXXX`."* **[x]** — `FROM debian:bookworm` everywhere (`bookworm` is the codename form of `XXXXX`).
- *"Docker images must have the same name as their corresponding service."* **[x]** — each service in `docker-compose.yml` now has an explicit `image:` line matching its service key and `container_name` (`mariadb`, `wordpress`, `nginx`, `redis`, `ftp`, `adminer`, `keycloak`).
- *"The Makefile sets up all services via docker compose, no crash."* **[!]** procedural — `make -C srcs up` then `docker compose -f srcs/docker-compose.yml ps` should show all 7 as `Up` (mariadb/adminer as `healthy`), no restart loops.

## Docker network

- *"docker-network used, visible via `docker network ls`; explain it."* **[x]** — the `inception` bridge network is declared once and attached to all 7 services; containers reach each other by service name (`mariadb`, `wordpress`, `redis`, `keycloak`) without any port publishing needed between them.
  ```sh
  docker network ls | grep inception
  docker network inspect srcs_inception --format '{{ range .Containers }}{{ .Name }} {{ end }}'
  ```
  Explanation to have ready: a user-defined bridge network gives containers automatic DNS resolution by service/container name and isolates the stack from other Docker networks on the host, without needing `--link` or manually managed IPs.

## NGINX with SSL/TLS

- *"Dockerfile exists."* **[x]** `srcs/requirements/nginx/Dockerfile`.
- *"Container created via `docker compose ps`."* **[!]** procedural.
- *"HTTP (port 80) must not connect."* **[x]** — see "Simple setup" above; port 80 is not published at all.
- *"`https://login.42.fr/` shows the configured WordPress site, not the install wizard."* **[x]**, pending the procedural check.
- *"TLS v1.2 or v1.3 demonstrated; self-signed is fine."* **[x]** — `ssl_protocols TLSv1.2 TLSv1.3;` in `nginx.conf`, nothing older enabled.
  ```sh
  openssl s_client -connect <DOMAIN>:443 -tls1_2 </dev/null 2>/dev/null | grep -E "subject=|Protocol"
  openssl s_client -connect <DOMAIN>:443 -tls1_1 </dev/null 2>&1 | tail -5   # handshake must fail
  ```

## WordPress with php-fpm and its volume

- *"Dockerfile exists; no NGINX inside it."* **[x]** — `srcs/requirements/wordpress/Dockerfile` installs `php-fpm`, `php-mysql`, `php-cli`, `mariadb-client`; no `nginx` package anywhere in it.
- *"Container created."* **[!]** procedural.
- *"Volume exists; `docker volume inspect` shows a path under `/home/login/data/`."* **[x]** — `wordpress_data` is now bind-mounted at `/home/oilyine/data/wordpress` (previously had an extra `/Inception/` path segment — fixed).
  ```sh
  docker volume inspect srcs_wordpress_data --format '{{ .Mountpoint }}'
  # → /home/oilyine/data/wordpress
  ```
- *"Add a comment using the regular WordPress user."* **[!]** procedural — sign in as `$WP_USER`/`$WP_USER_PWD` on the live site and post a comment.
- *"Sign in as administrator; admin username must not contain 'admin'/'Admin' in any form."* **[x]** — `WP_ADMIN_USER` is now `oilyine_owner` (previously `admin`, which would have ended the evaluation on this point alone).
  ```sh
  docker exec -it wordpress wp --allow-root --path=/var/www/wordpress user list --role=administrator --fields=user_login
  ```
- *"Edit a page from the dashboard; verify it updates on the site."* **[!]** procedural.

## MariaDB and its volume

- *"Dockerfile exists; no NGINX inside it."* **[x]** — `srcs/requirements/mariadb/Dockerfile` installs only `mariadb-server`.
- *"Container created."* **[!]** procedural.
- *"Volume exists under `/home/login/data/`."* **[x]** — `mariadb_data` now bind-mounted at `/home/oilyine/data/mariadb`.
  ```sh
  docker volume inspect srcs_mariadb_data --format '{{ .Mountpoint }}'
  ```
- *"Explain how to log in; database is not empty."* **[!]** procedural, but the command is:
  ```sh
  docker exec -it mariadb mariadb -u"$MARIADB_USER" -p"$MARIADB_PWD" "$MARIADB_NAME" -e "SHOW TABLES;"
  ```
  (`mariadb.sh` creates `$MARIADB_NAME`/`$MARIADB_USER` for WordPress and a second `keycloak` database/user on first boot — both should list real WordPress tables.)

## Persistence

**[!]** procedural — the code fully supports it (three named, host-backed volumes for `mariadb`, `wordpress`, `redis`), but it has to be demonstrated live:
```sh
docker compose -f srcs/docker-compose.yml down     # keep volumes
# reboot the host/VM here if that's part of your evaluation setup
docker compose -f srcs/docker-compose.yml up -d --build
```
WordPress should come back already configured, and any earlier changes (a comment, an edited page) should still be there.

## Configuration modification

**[!]** procedural, decided live by the evaluator — see [DEV_DOC.md](../DEV_DOC.md#configuration-modification-defense-scenario) for a worked example (changing NGINX's published port from `443` to `8843`) that generalizes to any service's `ports:` entry.

## Bonus

Only evaluated if the mandatory part is entirely correct. This repo implements four bonus services, each with its own Dockerfile and, where it needs one, its own volume — see **[docs/BONUS.md](BONUS.md)** for a full walkthrough and verification commands:

| Service | Own Dockerfile/container/volume | Notes |
|---|---|---|
| Redis cache | **[x]** `redis` container, `redis_data` volume | Wired into WordPress via the `redis-cache` plugin in `wordpress.sh` |
| FTP server, pointed at the WordPress volume | **[x]** `ftp` container, shares `wordpress_data` | Explicit FTPS enforced; **known issue** — `vsftpd.conf`'s `pasv_address=127.0.0.1` will likely break passive-mode transfers from outside the container's own network namespace; test this specific path before your defense (see [docs/BONUS.md](BONUS.md#ftp--vsftpd)) |
| Adminer | **[x]** `adminer` container | Plain HTTP on `9090`, not proxied through NGINX/TLS |
| Free-choice service — Keycloak (OIDC SSO for WordPress) | **[x]** `keycloak` container, uses `mariadb`'s `keycloak` database | Be ready to explain what it does and why: centralizes authentication and demonstrates a real single sign-on integration on top of the mandatory stack, rather than adding an unrelated service just to tick the box |

Not implemented: the static-site bonus option (not required — the subject offers a menu, and four other bonuses are already implemented).

## Summary of what changed in this pass

1. `WP_ADMIN_USER` no longer contains "admin" (`admin` → `oilyine_owner`).
2. `srcs/.env` removed from git tracking and added to `.gitignore`; `srcs/.env.example` (placeholder values) committed in its place.
3. NGINX no longer publishes port 80; the HTTP→HTTPS redirect server block was removed from `nginx.conf` (port 80 now refuses connections, per the subject's explicit requirement, rather than redirecting).
4. Every hardcoded `:8443` was removed from `nginx.conf`, `srcs/.env`, `wordpress.sh`, `keycloak.sh` and the (unused) `wp-config.php`, so the site and Keycloak are reachable at bare `https://$DOMAIN`.
5. `docker-compose.yml` volume host paths changed from `/home/oilyine/Inception/data/...` to `/home/oilyine/data/...` to match "`/home/login/data/`" literally; `srcs/Makefile` and the root `Makefile` updated to match.
6. Each service in `docker-compose.yml` now has an explicit `image:` matching its service/container name.
7. `run-vm.sh`'s now-pointless `HTTP_HOST_PORT` forward (port 80 has nothing listening on it anymore) was removed.

Remaining items are either procedural (only observable live during the defense) or, for the FTP passive-mode address, worth testing end-to-end before your defense since it wasn't practical to verify by static inspection alone.
