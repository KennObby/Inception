*This project has been created as part of the 42 curriculum by oilyine.*

# Inception

## Description

Inception sets up a small, self-hosted web infrastructure entirely from hand-written Dockerfiles orchestrated by Docker Compose: an NGINX reverse proxy terminating TLS, a WordPress site running on php-fpm, and a MariaDB database, each in its own container on a private Docker network, each with its data on a persistent volume. Beyond the mandatory three, the project adds four bonus services: Redis (WordPress object cache), an FTP server pointed at the WordPress volume, Adminer (database administration UI), and Keycloak (OpenID Connect single sign-on for WordPress).

Everything runs from `srcs/`: one Dockerfile per service, built from Debian, with no pre-built application images and no background/keep-alive hacks in any entrypoint. The repository root also carries a self-contained QEMU/Debian VM setup (`install-vm.sh`, `run-vm.sh`) — the day-to-day way this project is run and tested, useful on a machine without direct Docker/root access. Because the browser reaches the VM through QEMU's NAT (only port `8443` on the host forwards to the VM's `443`), the site, WordPress's own URLs, and Keycloak's redirect URLs are all configured for `https://<DOMAIN>:8443`.

## Instructions

Two companion documents cover this in detail:

- **[USER_DOC.md](USER_DOC.md)** — how to start/stop the stack, reach the website and the admin panels, manage credentials, and run basic health checks.
- **[DEV_DOC.md](DEV_DOC.md)** — prerequisites, first-time setup, Makefile targets, the underlying `docker compose` commands, and how data persistence is set up.

Fastest path, once the VM is up (see [docs/QEMU.md](docs/QEMU.md)) or on any machine with Docker + Docker Compose v2, with `srcs/.env` created from `srcs/.env.example`:

```sh
cd srcs
make up
make ps
```

Then browse to `https://<DOMAIN>:8443/` (as set in `srcs/.env`'s `WP_PUBLIC_URL`), accepting the self-signed certificate warning.

Further reference:

- **[docs/CONFIGURATION.md](docs/CONFIGURATION.md)** — every environment variable, what reads it, and its purpose.
- **[docs/BONUS.md](docs/BONUS.md)** — a walkthrough of each bonus service with example commands.
- **[docs/QEMU.md](docs/QEMU.md)** — how the `install-vm.sh`/`run-vm.sh` VM workflow and its port forwarding work.

## Resources

- [Docker Compose documentation](https://docs.docker.com/compose/)
- [NGINX documentation](https://nginx.org/en/docs/)
- [WordPress `wp-cli` handbook](https://developer.wordpress.org/cli/commands/)
- [MariaDB documentation](https://mariadb.com/kb/en/documentation/)
- [Redis documentation](https://redis.io/docs/)
- [vsftpd documentation](https://security.appspot.com/vsftpd.html)
- [Keycloak documentation](https://www.keycloak.org/documentation)
