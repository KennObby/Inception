# User documentation

This document covers day-to-day usage: starting and stopping the stack, reaching the website and the admin panels, managing credentials, and a handful of basic checks anyone (not just a developer) can run to confirm the stack is healthy.

## Starting the stack

```sh
cd srcs
make up
```

`make up` creates the host data directories (`/home/<login>/data/{mariadb,wordpress,redis}`) and then builds and starts all seven containers in the background. First boot takes a few minutes — WordPress downloads WordPress core and plugins, and Keycloak provisions its realm.

Check everything came up:

```sh
make ps
```

All services should show as `Up` (mariadb and adminer additionally show `healthy` once MariaDB's health check passes).

## Stopping the stack

```sh
make down
```

This stops and removes the containers but **keeps the data volumes** — restart with `make up` and the site, database, and cache are exactly as you left them (see [DEV_DOC.md](DEV_DOC.md#data-persistence) for the persistence test used during evaluation).

To wipe everything, including the data:

```sh
make fclean
```

## Accessing the website

Open `https://<DOMAIN>/` in a browser, where `<DOMAIN>` is the value of `DOMAIN` in `srcs/.env` (e.g. your 42 login's domain). The certificate is self-signed, so the browser will show a warning — accept it to continue.

- Port **443** is the only way in. Port 80 is not published by NGINX at all; `http://<DOMAIN>/` will simply refuse the connection.
- If the domain doesn't resolve on your network, add a hosts entry: `echo "127.0.0.1 <DOMAIN>" | sudo tee -a /etc/hosts` (adjust the IP if Docker is running on a different host).

## Accessing the admin panels

| Panel | URL | Sign in with |
|---|---|---|
| WordPress site | `https://<DOMAIN>/` | — |
| WordPress admin dashboard | `https://<DOMAIN>/wp-admin/` | `WP_ADMIN_USER` / `WP_ADMIN_PWD` from `srcs/.env` |
| WordPress (regular user) | `https://<DOMAIN>/wp-login.php` | `WP_USER` / `WP_USER_PWD` |
| Adminer (database admin) | `http://<DOMAIN>:9090/` | System: MySQL, Server: `mariadb`, Username: `MARIADB_USER`, Password: `MARIADB_PWD`, Database: `MARIADB_NAME` |
| Keycloak admin console | `https://<DOMAIN>/auth/admin/` | `KC_ADMIN` / `KC_ADMIN_PWD` |
| WordPress login via SSO | `https://<DOMAIN>/wp-login.php` → "OpenID Connect Generic" button | `KC_TEST_USER` / `KC_TEST_USER_PWD` |

As the WordPress admin, you can edit any page from **Pages → All Pages → Edit**; the change is visible on the live site immediately (no cache purge needed unless Redis object caching is holding a stale copy — `wp cache flush` clears it, see below).

As the regular WordPress user, you can add a comment on any post from the front end.

## Managing credentials

All credentials live in `srcs/.env` (copied from `srcs/.env.example` — see [DEV_DOC.md](DEV_DOC.md)) and are **not** committed to the repository. To change a credential:

1. Edit the relevant variable in `srcs/.env`.
2. Re-run `make up` (or `docker compose -f srcs/docker-compose.yml up -d --build`) so the affected container picks up the new value. WordPress and Keycloak entrypoints are idempotent and update existing config in place.
3. **Exception — MariaDB users/passwords:** the database entrypoint only creates users the first time (`CREATE USER IF NOT EXISTS`). Changing `MARIADB_PWD` or `KC_DB_PWD` after the volume already exists requires either `make clean-data` (destroys all data) or manually running `ALTER USER … IDENTIFIED BY …` inside the `mariadb` container.

## Basic checks

```sh
docker compose -f srcs/docker-compose.yml ps                 # all 7 containers, mariadb/adminer "healthy"
docker network ls | grep inception                            # the shared Docker network exists
docker volume ls | grep -E "mariadb_data|wordpress_data|redis_data"

curl -I http://<DOMAIN>/          # connection refused/times out — port 80 is not exposed
openssl s_client -connect <DOMAIN>:443 -tls1_2 </dev/null 2>/dev/null | grep subject=

docker exec -it wordpress wp --allow-root --path=/var/www/wordpress core is-installed
docker exec -it wordpress wp --allow-root --path=/var/www/wordpress user list --fields=user_login,roles

docker exec -it mariadb mariadb -uroot -e "SHOW DATABASES;"    # WordPress + Keycloak DBs both present

docker exec -it redis redis-cli ping                            # PONG
```

See [docs/BONUS.md](docs/BONUS.md) for FTP, Adminer and Keycloak-specific checks, and [docs/EVALUATION.md](docs/EVALUATION.md) for the full evaluation walkthrough.
