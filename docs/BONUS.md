# Bonus services

The mandatory part is NGINX + WordPress + MariaDB (see the architecture diagram in [DEV_DOC.md](../DEV_DOC.md#architecture)). This repo additionally implements four bonus services, each its own Dockerfile under `srcs/requirements/bonus/`. Per the Inception subject, bonus is only graded if the mandatory part is implemented perfectly — keep that in mind when reading [EVALUATION.md](EVALUATION.md).

## Redis — object cache

**Files:** `srcs/requirements/bonus/redis/{Dockerfile, conf/redis.conf}`

A plain `redis-server` on Debian bookworm, running as the unprivileged `redis` user, bound to `0.0.0.0:6379` on the `inception` network only (never published to the host). `wordpress.sh` wires it up automatically on every boot:

```sh
wp config set WP_REDIS_HOST redis --type=constant
wp config set WP_REDIS_PORT 6379 --type=constant --raw
wp plugin install redis-cache --activate
wp redis enable
```

**Verify it's actually caching:**

```sh
docker exec -it redis redis-cli ping                     # PONG
docker exec -it wordpress wp --allow-root --path=/var/www/wordpress redis status
# Load the site once in a browser, then:
docker exec -it redis redis-cli --scan | grep wp_          # should list cached WP keys
docker exec -it redis redis-cli info stats | grep keyspace_hits
```

`redis.conf` has no `requirepass` — any container on the `inception` network can read the cache unauthenticated. That's fine for this project's scope (the network isn't exposed to the host), but worth knowing if you extend it.

## FTP — vsftpd

**Files:** `srcs/requirements/bonus/ftp/{Dockerfile, conf/vsftpd.conf, scripts/ftp.sh}`

`ftp.sh` creates the `$FTP_USER` system account on first boot, sets its home directory to `/var/www/wordpress` (the same named volume WordPress writes to — so files uploaded over FTP show up on the live site and vice versa), and generates a self-signed cert for FTPS if one doesn't exist yet.

`vsftpd.conf` enforces **explicit FTPS** (`ssl_enable=YES`, `force_local_data_ssl=YES`, `force_local_logins_ssl=YES`) on the standard control port 21, with passive-mode data ports restricted to `21000-21010` — matching the range forwarded by `run-vm.sh` and published in `docker-compose.yml`.

**Connect:**

```sh
# curl, explicit TLS, ignoring the self-signed cert
curl --ftp-ssl -k -u "$FTP_USER:$FTP_PWD" ftp://oilyine.42.lu:2121/

# lftp, interactive
lftp -u "$FTP_USER,$FTP_PWD" \
     -e "set ftp:ssl-force true; set ssl:verify-certificate no; ls; put ./example.txt; bye" \
     oilyine.42.lu -p 2121
```

> `pasv_address=127.0.0.1` in `vsftpd.conf` tells the server to advertise `127.0.0.1` as the address for passive data connections. That only works when the FTP client runs on the same machine as the container. Connecting from the actual VM host (through the `run-vm.sh` port forward) or from outside will complete the control connection and login, but passive data transfers (`ls`, `get`, `put`) are likely to hang or fail because the client is told to open the data channel to `127.0.0.1` instead of the reachable host/domain — this is worth testing end-to-end before defense (see the Bonus table in [EVALUATION.md](EVALUATION.md#bonus)), and, if broken, fixing by setting `pasv_address` to `$DOMAIN` or the VM's routable IP.

## Adminer — DB admin UI

**File:** `srcs/requirements/bonus/adminer/Dockerfile`

Minimal `php -S` server serving the single-file Adminer app downloaded at build time from `adminer.org`. Published directly on `9090:8080` in `docker-compose.yml` (not proxied through NGINX/TLS — it's reachable at plain `http://…:9090`, not under the HTTPS vhost).

**Use it:**

1. Browse to `http://oilyine.42.lu:9090` (or `http://<vm-host>:9090` from the VM host, per `ADMINER_HOST_PORT`).
2. System: `MySQL`, Server: `mariadb`, Username: `$MARIADB_USER`, Password: `$MARIADB_PWD`, Database: `$MARIADB_NAME`.
3. You can also connect as `$KC_DB_USER`/`$KC_DB_PWD` against the `keycloak` database created by `mariadb.sh`.

## Keycloak — OpenID Connect SSO for WordPress

**Files:** `srcs/requirements/bonus/keycloak/{Dockerfile, scripts/keycloak.sh}`

Builds Keycloak 26.4.2 from the official release tarball (`kc.sh build`), then `keycloak.sh`:

1. Starts Keycloak with `--http-relative-path=/auth` (so it lines up with NGINX's `location ^~ /auth/` proxy) and `--proxy-headers=xforwarded`, backed by its own MariaDB database (`KC_DB_URL_DATABASE=keycloak`).
2. Waits for `http://localhost:8080/auth/realms/master` to answer.
3. Logs in as the bootstrap admin (`KEYCLOAK_ADMIN`/`KEYCLOAK_ADMIN_PASSWORD`) via `kcadm.sh`.
4. Idempotently creates (or updates) the `$KC_REALM` realm, a confidential `$KC_CLIENT_ID` client with `redirectUris`/`webOrigins` scoped to `https://$DOMAIN`, and a test end user (`$KC_TEST_USER`).

WordPress's own `wordpress.sh` configures the `daggerhart-openid-connect-generic` plugin with matching issuer/endpoint URLs — internal ones (`http://keycloak:8080/auth/...`) for server-to-server calls (token, userinfo, JWKS) and external ones (`https://$DOMAIN/auth/...`) for the browser-facing authorization/login redirect.

**Try the SSO flow:**

```sh
# Confirm the realm is up and its OIDC discovery document is served
docker exec -it keycloak curl -s http://localhost:8080/auth/realms/Inception/.well-known/openid-configuration
```

Then, in a browser: go to `https://oilyine.42.lu/wp-login.php`, click **"OpenID Connect Generic"**, and log in with `$KC_TEST_USER` / `$KC_TEST_USER_PWD`. With `OIDC_CREATE_IF_DOES_NOT_EXIST=1` a matching WordPress user is auto-provisioned on first login.

**Inspect/administer the realm directly:**

```sh
docker exec -it keycloak /opt/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080/auth --realm master \
  --user "$KC_ADMIN" --password "$KC_ADMIN_PWD"
docker exec -it keycloak /opt/keycloak/bin/kcadm.sh get users -r Inception
```

Or via the admin console (proxied through NGINX): `https://oilyine.42.lu/auth/admin/` with `$KC_ADMIN`/`$KC_ADMIN_PWD`.
