*This project has been created as part of the 42 curriculum by oilyine.*

# Inception

## Description

Inception sets up a small, self-hosted web infrastructure entirely from hand-written Dockerfiles orchestrated by Docker Compose: an NGINX reverse proxy terminating TLS, a WordPress site running on php-fpm, and a MariaDB database, each in its own container on a private Docker network, each with its data on a persistent volume. Beyond the mandatory three, the project adds four bonus services: Redis (WordPress object cache), an FTP server pointed at the WordPress volume, Adminer (database administration UI), and Keycloak (OpenID Connect single sign-on for WordPress).

Everything under `srcs/` is what gets evaluated: one Dockerfile per service, built from Debian, with no pre-built application images and no background/keep-alive hacks in any entrypoint. The repository root also carries an optional, self-contained QEMU/Debian VM setup (`install-vm.sh`, `run-vm.sh`) used purely as a personal development environment on machines without direct Docker access — it is not part of the mandatory infrastructure and is not needed to build or evaluate `srcs/`.

## Instructions

Two companion documents cover this in detail:

- **[USER_DOC.md](USER_DOC.md)** — how to start/stop the stack, reach the website and the admin panels, manage credentials, and run basic health checks.
- **[DEV_DOC.md](DEV_DOC.md)** — prerequisites, first-time setup, Makefile targets, the underlying `docker compose` commands, and how data persistence is set up.

Fastest path, once Docker and Docker Compose v2 are installed and `srcs/.env` has been created from `srcs/.env.example`:

```sh
cd srcs
make up
make ps
```

Then browse to `https://<DOMAIN>/` (as set in `srcs/.env`), accepting the self-signed certificate warning.

Further reference:

- **[docs/CONFIGURATION.md](docs/CONFIGURATION.md)** — every environment variable, what reads it, and its purpose.
- **[docs/BONUS.md](docs/BONUS.md)** — a walkthrough of each bonus service with example commands.
- **[docs/EVALUATION.md](docs/EVALUATION.md)** — the official 42 Inception evaluation checklist, worked through against this exact codebase.
- **[docs/QEMU.md](docs/QEMU.md)** — how the optional `install-vm.sh`/`run-vm.sh` personal-development VM workflow works.

## Resources

- [Inception subject (PDF)](https://cdn.intra.42.fr/pdf/pdf/192349/en.subject.pdf)
- [42 EvalHub — Inception evaluation sheet](https://www.42evalhub.com/common/inception)
- [Docker Compose documentation](https://docs.docker.com/compose/)
- [NGINX documentation](https://nginx.org/en/docs/)
- [WordPress `wp-cli` handbook](https://developer.wordpress.org/cli/commands/)
- [MariaDB documentation](https://mariadb.com/kb/en/documentation/)
- [Redis documentation](https://redis.io/docs/)
- [vsftpd documentation](https://security.appspot.com/vsftpd.html)
- [Keycloak documentation](https://www.keycloak.org/documentation)

**How AI was used:** this project's documentation — this README, `USER_DOC.md`, `DEV_DOC.md`, and the files under `docs/` — was written with Claude (Anthropic), by having it read the existing Dockerfiles, entrypoint scripts, `docker-compose.yml` and `.env` files and describe what they actually do, then cross-check the setup against the published 42 Inception evaluation criteria. Claude also applied a small set of concrete fixes flagged by that review directly to the infrastructure code: removing the exposed port 80 (NGINX now serves only 443), dropping a hardcoded `:8443` from internal URLs, renaming the volume host paths to `/home/<login>/data/...`, adding `image:` names matching each service, renaming the WordPress admin account so it no longer contains "admin", and removing `srcs/.env` from version control in favor of a committed `srcs/.env.example` template. The Dockerfiles, entrypoint scripts, and Docker Compose stack architecture itself were designed and implemented by the student.
