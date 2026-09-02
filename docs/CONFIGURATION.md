# Configuration reference

This project reads configuration from two separate `.env` files: one for the QEMU/VM layer, one for the Docker Compose application stack. Both are auto-sourced (`set -a; . ./.env; set +a`) by the shell scripts and by `docker compose`, so any variable added there is automatically exported to the containers/processes that need it.

## `/.env` — VM provisioning (`install-vm.sh`, `run-vm.sh`)

| Variable | Default | Used by | Purpose |
|---|---|---|---|
| `WORKDIR` | auto-detected repo root | both scripts | Base path for locating `installers/preseed.cfg` |
| `ISO_NAME` | `debian-13.1.0-amd64-netinst.iso` | `install-vm.sh` | Installer ISO filename |
| `ISO_URL` | `https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/${ISO_NAME}` | `install-vm.sh` | Where to download the ISO if missing |
| `DISK_NAME` | `debian.qcow2` | both | VM disk image filename |
| `DISK_SIZE` | `20G` | `install-vm.sh` | Size given to `qemu-img create` |
| `RAM_SIZE` | `2048` | both | VM RAM in MB |
| `IMAGES_DIR` | `$HOME/sgoinfre/$USER/images` (falls back to `$WORKDIR/images`) | both | Where the ISO/disk/netboot files live |
| `LOGS_DIR` | `$HOME/sgoinfre/$USER/Logs` (falls back to `$WORKDIR/Logs`) | both | QEMU/http-server logs, saved credentials |
| `QEMU_SYSTEM_BIN` | `qemu-system-x86_64` | both | Path to the QEMU binary (override for a 42 goinfre build) |
| `QEMU_IMG_BIN` | `qemu-img` | `install-vm.sh` | Path to `qemu-img` |
| `ACCEL_POLICY` | `auto` | both | `auto`\|`kvm`\|`tcg` — whether to use hardware acceleration |
| `UI_POLICY` | `auto` | both | `auto`\|`gtk`\|`sdl`\|`spice` — display backend |
| `AUDIO_POLICY` | `off` | `install-vm.sh` | `on` enables a PulseAudio device |
| `SAVE_CREDENTIALS` | `1` | `install-vm.sh` | Write generated VM user/password to `$LOGS_DIR/vm-credentials.txt` |
| `SSH_HOST_PORT` | `2222` | both | Host port forwarded to the VM's SSH (`22`) |
| `HTTP_HOST_PORT` | `8080` | `run-vm.sh` | Host port forwarded to the VM's port `80` |
| `HTTPS_HOST_PORT` | `8443` | `run-vm.sh` | Host port forwarded to the VM's port `443`, for the personal-VM dev workflow only |
| `KEYCLOAK_HOST_PORT` | `8081` | `run-vm.sh` | Host port forwarded to the VM's port `8080` (see note below) |
| `ADMINER_HOST_PORT` | `9090` | `run-vm.sh` | Host port forwarded to the VM's port `9090` |
| `FTP_HOST_PORT` | `2121` | `run-vm.sh` | Host port forwarded to the VM's port `21` |
| `FTP_PASSIVE_MIN` / `FTP_PASSIVE_MAX` | `21000` / `21010` | `run-vm.sh` | Passive-mode port range, forwarded 1:1 to the VM |

Runtime-only overrides (not in `.env`, passed on the command line): `UI_POLICY`, `UNATTENDED`, `VM_USER`, `VM_PASS`, `VM_PASS_HASH`, `PUBKEY_PATH`, `PRESEED_PORT`, `DEBIAN_SUITE`. E.g. `make install` is literally `UI_POLICY=auto UNATTENDED=1 ./install-vm.sh`.

> This VM layer is a personal development convenience (useful on a machine without direct Docker/root access) and is not part of the mandatory Inception infrastructure — it is not what gets evaluated. `srcs/.env` and the entrypoint scripts use bare `https://$DOMAIN` with no port suffix.
>
> **Port 80:** `srcs/docker-compose.yml`'s `nginx` service currently publishes both `443` and `80` (with `80` redirecting to `443`), for everyday local convenience. The real evaluation criteria require NGINX reachable on port **443 only** — `http://` must refuse the connection, not redirect. Remove the `"80:80"` line from `nginx`'s `ports:` and the `listen 80 { ... }` server block from `nginx.conf` before your defense; see [EVALUATION.md](EVALUATION.md#simple-setup) for the exact revert.
>
> **Note on `KEYCLOAK_HOST_PORT`:** `run-vm.sh` forwards this host port to the VM's TCP `8080`, but nothing inside the VM (outside Docker) listens there — the `keycloak` container's `8080` is only published to the `inception` Docker network, not to the VM host (`docker-compose.yml` has no `ports:` entry for `keycloak`). Keycloak is reached exclusively through NGINX's `/auth/` reverse-proxy on `443`. This host forward is effectively unused; see [EVALUATION.md](EVALUATION.md) for detail.

## `srcs/.env` — application stack (`docker-compose.yml` + container entrypoints)

`srcs/.env` is not committed to the repository (credentials must never be in git — see [EVALUATION.md](EVALUATION.md)). Copy `srcs/.env.example` to `srcs/.env` and fill in real values before running `make up`.

| Variable | Example value | Consumed by | Purpose |
|---|---|---|---|
| `DOMAIN` | `oilyine.42.lu` | nginx, wordpress, ftp, keycloak | Server name for the vhost, TLS cert CN/SAN, WP site URL, Keycloak hostname/issuer |
| `HOST` | `localhost` | (unused directly by compose; template for `CERT_DIR`/`KEY`/`CRT` below) | |
| `CERT_DIR`, `KEY`, `CRT`, `CSRCONF` | `/etc/nginx/certs`, … | *(declared but not read by any compose service — the actual cert paths are hardcoded in `nginx.sh`)* | Legacy/unused — see EVALUATION.md |
| `MARIADB_NAME` | `wordpress` | mariadb, wordpress | WordPress database name |
| `MARIADB_USER` / `MARIADB_PWD` | *(yours)* | mariadb, wordpress, adminer (manually) | WordPress DB credentials, created by `mariadb.sh` |
| `WP_TITLE` | `Inception Wordpress Site` | wordpress | Site title passed to `wp core install` |
| `WP_PUBLIC_URL` | `https://oilyine.42.lu` | wordpress | `home`/`siteurl` set after install — no port suffix, since NGINX publishes only `443` |
| `WP_ADMIN_USER` / `WP_ADMIN_PWD` / `WP_ADMIN_MAIL` | *(yours — must not contain "admin"/"Admin")* | wordpress | WordPress administrator account created by `wp core install` |
| `WP_USER` / `WP_USER_PWD` / `WP_MAIL` | *(yours)* | wordpress | A second, non-admin (`author`) WordPress user |
| `WP_DB` / `WP_DB_USER` / `WP_DB_PWD` | mirrors `MARIADB_*` | docker-compose only | Re-exposed under `WP_*` names for the `wordpress` service environment |
| `FTP_USER` / `FTP_PWD` | *(yours)* | ftp | FTP account, chrooted to `/var/www/wordpress` |
| `KC_NAME` | `keycloak` | mariadb | Name of the second database created for Keycloak |
| `KC_ADMIN` / `KC_ADMIN_PWD` | *(yours)* | keycloak (`KEYCLOAK_ADMIN`/`KEYCLOAK_ADMIN_PASSWORD`) | Keycloak bootstrap admin console credentials |
| `KC_DB_USER` / `KC_DB_PWD` | *(yours)* | mariadb, keycloak | Dedicated DB user/password for Keycloak's own database |
| `KC_REALM` | `Inception` | keycloak, wordpress | Realm created by `keycloak.sh`; must match the WP OIDC plugin config |
| `KC_CLIENT_ID` / `KC_CLIENT_SECRET` | `wordpress` / *(yours)* | keycloak, wordpress | Confidential OIDC client used by the WordPress OpenID Connect plugin |
| `KC_TEST_USER` / `KC_TEST_USER_PWD` / `KC_TEST_USER_EMAIL` | *(yours)* | keycloak | A ready-to-use end-user account for testing SSO login |

### Variables read by `docker-compose.yml` with no matching key in `srcs/.env`

`docker-compose.yml`'s `wordpress` service also references `KC_REALM`, `KC_CLIENT_ID`, `KC_CLIENT_SECRET` a second time to build its own `wp-config.php` OIDC constants (`wordpress.sh`) — these are the same three Keycloak variables above, just consumed by two services.

## Editing credentials

Both `.env` files are plain shell (`. ./.env`), so any POSIX-safe assignment works — quote values containing spaces or `$`. After changing `srcs/.env`, re-run `make up` (or `docker compose up -d --build`) so containers pick up the new environment; entrypoint scripts like `wordpress.sh` and `keycloak.sh` are written to be idempotent and will update existing config in place (`wp config set …`, `kcadm update …`) rather than requiring a full teardown, **except** for MariaDB users/passwords, which are only created with `CREATE USER IF NOT EXISTS` in `mariadb.sh` — changing `MARIADB_PWD` after the volume already has that user requires `make clean-data` (or manually running `ALTER USER`) before it takes effect.
