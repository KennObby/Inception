# Inception

A small virtualized infrastructure built for the 42 school **Inception** project: a WordPress site served over TLS by NGINX, backed by MariaDB, with Redis caching, FTP file access, Adminer database administration, and Keycloak single sign-on (OpenID Connect) — all defined as hand-written Dockerfiles orchestrated by Docker Compose, running inside a self-provisioned Debian VM.

- **Login / domain:** `oilyine.42.lu`
- **Mandatory part:** NGINX (TLSv1.2/1.3 only) · WordPress + php-fpm · MariaDB
- **Bonus part:** Redis cache · FTP server · Adminer · Keycloak (OIDC) — see [docs/BONUS.md](docs/BONUS.md)

If you're here to check whether this project is ready for evaluation, jump straight to **[docs/EVALUATION.md](docs/EVALUATION.md)** — it walks the official Inception grading checklist point by point against this exact codebase and lists what to verify or fix before defense.

## Table of contents

- [Architecture](#architecture)
- [Repository layout](#repository-layout)
- [Quick start](#quick-start)
- [Makefile cheat sheet](#makefile-cheat-sheet)
- [Configuration](#configuration)
- [Usage examples](#usage-examples)
- [Troubleshooting](#troubleshooting)
- [Further documentation](#further-documentation)

## Architecture

```
Host machine
  └── QEMU/Debian VM (install-vm.sh / run-vm.sh, hostfwd NAT)
        │  :2222→22 (ssh)  :8080→80  :8443→443  :9090→9090  :2121→21  :21000-21010
        └── Docker network "inception" (bridge)
              ┌────────────┐   443/TLS   ┌───────────┐  fastcgi:9000  ┌───────────┐
   browser ──▶│   nginx    │────────────▶│           │───────────────▶│           │
              │ (entrypoint│   proxy     │ wordpress │                │  mariadb  │
              │  self-signed│ /auth/ ──┐ │ (php-fpm) │───3306────────▶│           │
              │  TLS cert) │           │ └───────────┘                └───────────┘
              └────────────┘           │        │  6379                    ▲
                    │ :80→301 to :8443 │        ▼                          │
                    │                  ▼   ┌───────────┐                   │
                    │           ┌───────────┐│  redis   │                  │
                    │           │ keycloak  │└───────────┘                 │
                    │           │  (OIDC)   │                              │
                    │           └───────────┘                              │
              ┌────────────┐                                               │
              │  adminer   │───────────────────────────────────────────────┘
              │  :9090     │
              └────────────┘
              ┌────────────┐
              │    ftp     │──── shares the wordpress_data volume (upload themes/plugins/media)
              │ :21, pasv  │
              └────────────┘
```

Named Docker volumes (bind-mounted under `/home/oilyine/Inception/data/`):

| Volume | Mounted in | Purpose |
|---|---|---|
| `mariadb_data` | `mariadb` | `/var/lib/mysql` — WordPress + Keycloak databases |
| `wordpress_data` | `wordpress` (rw), `nginx` (ro), `ftp` (rw) | `/var/www/wordpress` — WP core, themes, plugins, uploads |
| `redis_data` | `redis` | `/data` — RDB snapshots |

All containers sit on a single user-defined bridge network (`inception`) and resolve each other by service name (`mariadb`, `wordpress`, `redis`, `keycloak`). Only `nginx`, `ftp` and `adminer` publish ports to the VM host; `wordpress`, `mariadb`, `redis` and `keycloak` are reachable only from inside the Docker network.

## Repository layout

```
.
├── Makefile                 # VM provisioning (install/run) + docker compose shortcuts
├── .env                      # VM/QEMU settings (ISO, disk, RAM, port forwards)
├── install-vm.sh              # Unattended Debian 13 (netinst) install for QEMU
├── run-vm.sh                   # Boots the installed VM with all port forwards
├── installers/
│   └── preseed.cfg              # Debian installer preseed (locale, partitioning, packages)
└── srcs/
    ├── Makefile                # docker compose up/down/clean-data/fclean/re/logs/ps
    ├── .env                      # Stack secrets: domain, DB, WP, FTP, Keycloak
    ├── docker-compose.yml         # The 7-service stack
    └── requirements/
        ├── mariadb/
        │   ├── Dockerfile
        │   └── scripts/{50-server.cnf, mariadb.sh}
        ├── nginx/
        │   ├── Dockerfile
        │   └── scripts/{nginx.conf, nginx.sh}
        ├── wordpress/
        │   ├── Dockerfile
        │   └── scripts/{wordpress.sh, wp-config.php}
        └── bonus/
            ├── adminer/Dockerfile
            ├── ftp/{Dockerfile, conf/vsftpd.conf, scripts/ftp.sh}
            ├── keycloak/{Dockerfile, scripts/keycloak.sh}
            └── redis/{Dockerfile, conf/redis.conf}
```

## Quick start

There are two ways to run the stack, matching the two halves of the root `Makefile`.

### Option A — Docker already available on the host (fastest for local dev)

If you're on a machine that already has Docker + Docker Compose v2 (e.g. not doing the VM step), skip straight to the stack:

```sh
cd srcs
make up          # creates data dirs, then `docker compose up -d --build`
make ps          # check all 7 containers are healthy/running
make logs        # follow logs
```

Add a hosts entry so the domain resolves locally, then browse to it:

```sh
echo "127.0.0.1 oilyine.42.lu" | sudo tee -a /etc/hosts
```

- WordPress: https://oilyine.42.lu:8443 (or `:443` if you edited `nginx.conf`'s redirect/exposed ports — see [docs/CONFIGURATION.md](docs/CONFIGURATION.md))
- Adminer: http://oilyine.42.lu:9090

Your browser will warn about the self-signed certificate generated by `nginx.sh` — accept it to continue.

### Option B — Full 42-style workflow: provision a Debian VM, then run the stack inside it

This is the workflow the root `Makefile` and `install-vm.sh`/`run-vm.sh` are built for (useful on a host without Docker/root access, e.g. a 42 cluster session):

```sh
# 1. Build the VM (downloads Debian 13 netinst ISO, unattended install via preseed)
make install                 # == UI_POLICY=auto UNATTENDED=1 ./install-vm.sh

# 2. Boot the installed VM with all service ports forwarded to the host
make run                      # == ./run-vm.sh

# 3. SSH into the VM (credentials printed during install, saved to $LOGS_DIR/vm-credentials.txt)
ssh -p 2222 oilyine@localhost

# 4. Inside the VM: clone/copy this repo to ~/Inception, then bring the stack up
cd ~/Inception/srcs
make up
```

Then, from the **host**, browse to `https://oilyine.42.lu:8443` (or `https://localhost:8443`) — the VM's port 443 is forwarded to host port `8443` by `run-vm.sh`. Add the `/etc/hosts` entry as in Option A if the domain isn't resolved by your network's DNS.

```sh
make logs                     # tail QEMU/install logs from the host
make clean                    # wipe VM disk image + logs (fresh reinstall)
```

## Makefile cheat sheet

**Root `Makefile`** (VM lifecycle + convenience docker shortcuts):

| Target | Effect |
|---|---|
| `make install` | Unattended Debian install into a fresh QEMU disk image |
| `make run` | Boot the installed VM with all port forwards |
| `make logs` | Tail `qemu-host.log`, `qemu-debug.log`, `guest-serial.log` |
| `make debug` | Re-run the installer with `sh -x` tracing |
| `make clean` | Remove logs and disk/ISO images (`$IMAGES_DIR`, `$LOGS_DIR`) |
| `make up` / `make down` | `docker compose -f srcs/docker-compose.yml up -d --build` / `down` (run this **inside** the VM, or on any Docker host) |
| `make clean-data` | Delete `/home/oilyine/Inception/data/{mariadb,wordpress}` |
| `make fclean` | `down` + `clean-data` |

**`srcs/Makefile`** (the actual Docker Compose stack):

| Target | Effect |
|---|---|
| `make up` | Create `data/{mariadb,wordpress,redis}` then `docker compose up -d --build` |
| `make down` | `docker compose down -v` |
| `make clean-data` | Interactive `rm -rf` of all three data dirs (asks for confirmation) |
| `make fclean` | `down` + `clean-data` + `docker system prune -af --volumes` |
| `make re` | `fclean` then `up` |
| `make logs` | `docker compose logs -f` |
| `make ps` | `docker compose ps` |

## Configuration

Two `.env` files drive the project — see **[docs/CONFIGURATION.md](docs/CONFIGURATION.md)** for the full variable-by-variable reference:

- **`/.env`** — QEMU/VM settings (ISO, disk size, RAM, accel/UI policy, host port forwards).
- **`/srcs/.env`** — the application stack: domain, MariaDB, WordPress, FTP and Keycloak credentials, consumed by `docker-compose.yml` and the container entrypoint scripts.

> ⚠️ Both `.env` files are currently committed to this repository with real-looking credentials. Rotate every secret before any public/shared use, and see the "Must-fix items" section of [docs/EVALUATION.md](docs/EVALUATION.md) about why this should not ship as-is to evaluation.

## Usage examples

These are drawn directly from what each container's entrypoint script does, so you can reproduce/verify the same checks the entrypoints perform.

**MariaDB** — connect with the WordPress app credentials and list tables (mirrors the healthcheck `mariadb.sh` waits on):

```sh
docker exec -it mariadb mariadb -u"$MARIADB_USER" -p"$MARIADB_PWD" "$MARIADB_NAME" -e "SHOW TABLES;"
docker exec -it mariadb mariadb -uroot -e "SHOW DATABASES;"   # db1 and keycloak should both exist
```

**WordPress** — `wordpress.sh` provisions the site with `wp-cli`; you can use the same binary to inspect it:

```sh
docker exec -it wordpress wp --allow-root --path=/var/www/wordpress core is-installed
docker exec -it wordpress wp --allow-root --path=/var/www/wordpress user list
docker exec -it wordpress wp --allow-root --path=/var/www/wordpress plugin list
docker exec -it wordpress wp --allow-root --path=/var/www/wordpress config get WP_REDIS_HOST
```

**NGINX** — verify the self-signed cert and enforced TLS versions (matches what `nginx.sh` generates):

```sh
openssl s_client -connect oilyine.42.lu:8443 -tls1_2 </dev/null 2>/dev/null | grep -E "subject=|Protocol"
curl -vk https://oilyine.42.lu:8443/ 2>&1 | grep -i "SSL connection using"
curl -I http://oilyine.42.lu:8080/          # should return a 301 to https://…:8443
```

**Redis** — confirm the WordPress object cache is talking to it:

```sh
docker exec -it redis redis-cli ping                 # PONG
docker exec -it redis redis-cli --scan | head          # WordPress cache keys after a page load
docker exec -it wordpress wp --allow-root --path=/var/www/wordpress redis status
```

**FTP** — `ftp.sh` creates the `$FTP_USER` account chrooted to `/var/www/wordpress` with explicit FTPS enforced (`force_local_data_ssl=YES`):

```sh
curl --ftp-ssl -k -u "$FTP_USER:$FTP_PWD" ftp://oilyine.42.lu:2121/
# or interactively:
lftp -u "$FTP_USER,$FTP_PWD" -e "set ftp:ssl-force true; set ssl:verify-certificate no; ls; bye" oilyine.42.lu -p 2121
```

**Adminer** — open http://oilyine.42.lu:9090, log in with:
- System: MySQL, Server: `mariadb`, Username: `$MARIADB_USER`, Password: `$MARIADB_PWD`, Database: `$MARIADB_NAME`

**Keycloak** — `keycloak.sh` provisions the realm/client/test user idempotently on every boot; check the result:

```sh
docker exec -it keycloak curl -s http://localhost:8080/auth/realms/Inception/.well-known/openid-configuration | head
# From the browser: https://oilyine.42.lu:8443/auth/  (proxied by nginx) → Inception realm
# WordPress login screen shows an "OpenID Connect Generic" button → sign in as $KC_TEST_USER / $KC_TEST_USER_PWD
```

See [docs/BONUS.md](docs/BONUS.md) for a deeper walkthrough of each bonus service, including what to check when something doesn't come up.

## Troubleshooting

| Symptom | Likely cause | Where to look |
|---|---|---|
| `wordpress` restarts in a loop | MariaDB not ready yet or wrong `WP_DB_*` vars | `docker logs wordpress`, `srcs/requirements/wordpress/scripts/wordpress.sh` (`until mysql … SELECT 1`) |
| Browser can't verify certificate | Expected — it's self-signed | Accept the exception once, or trust `srcs/requirements/nginx/scripts` output cert |
| FTP connects but data transfer hangs | Passive port/IP mismatch (`pasv_address=127.0.0.1` in `vsftpd.conf`) | See [docs/EVALUATION.md](docs/EVALUATION.md#ftp-passive-mode-address) |
| Keycloak login button does nothing / redirect fails | `KC_CLIENT_SECRET`/`DOMAIN` mismatch between `wordpress.sh` and `keycloak.sh` env, or realm not yet provisioned | `docker logs keycloak`, confirm `redirectUris` includes your `:8443` domain |
| `make up` at repo root fails with "no such file" | You're not inside the VM / wrong working directory | Run `cd srcs && make up`, or use the root `Makefile`'s `up` target which already points at `srcs/docker-compose.yml` |
| Data dirs empty / permission denied on bind mount | `/home/oilyine/Inception/data` doesn't exist yet or you're a different user | `srcs/Makefile`'s `setup-data` target creates them; verify the path matches your actual login/home |

## Further documentation

- **[docs/CONFIGURATION.md](docs/CONFIGURATION.md)** — every environment variable, what reads it, and its default.
- **[docs/BONUS.md](docs/BONUS.md)** — Redis, FTP, Adminer, Keycloak: what they do and how to exercise each one.
- **[docs/EVALUATION.md](docs/EVALUATION.md)** — the 42 Inception grading checklist mapped against this codebase, with pass/verify/fix notes.
