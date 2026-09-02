# Developer documentation

Prerequisites, first-time setup, Makefile usage, the underlying `docker compose` commands, and how data persistence is implemented.

## Architecture

```
Docker network "inception" (bridge)
      443/TLS   ┌───────────┐  fastcgi:9000  ┌───────────┐
browser ───────▶│           │───────────────▶│           │
                │   nginx   │                │ wordpress │
                │ (entrypoint,   ┌────┐      │ (php-fpm) │───3306────────▶┌───────────┐
                │  self-signed   │auth│─────▶│           │                │  mariadb  │
                │  TLS cert)     └────┘      └───────────┘                │           │
                └───────────┘  proxy to           │  6379                └───────────┘
                                keycloak           ▼                            ▲
                              ┌───────────┐  ┌───────────┐                     │
                              │ keycloak  │  │   redis   │                     │
                              │  (OIDC)   │  └───────────┘                     │
                              └───────────┘                                    │
                              ┌───────────┐                                    │
                              │  adminer  │────────────────────────────────────┘
                              │  :9090    │
                              └───────────┘
                              ┌───────────┐
                              │    ftp    │──── shares the wordpress_data volume
                              │ :21, pasv │      (upload themes/plugins/media)
                              └───────────┘
```

Only `nginx` (`443`), `ftp` (`21`, `21000-21010`) and `adminer` (`9090`) publish ports to the host; `wordpress`, `mariadb`, `redis` and `keycloak` are reachable only from inside the `inception` network, by service name.

| Volume | Mounted in | Purpose |
|---|---|---|
| `mariadb_data` | `mariadb` | `/var/lib/mysql` — WordPress + Keycloak databases |
| `wordpress_data` | `wordpress` (rw), `nginx` (ro), `ftp` (rw) | `/var/www/wordpress` — WP core, themes, plugins, uploads |
| `redis_data` | `redis` | `/data` — RDB snapshots |

## Prerequisites

- Docker Engine and Docker Compose v2 (the `docker compose` subcommand, not the standalone `docker-compose` v1 binary).
- Root or a user in the `docker` group.
- `openssl` on the host is not required — the TLS certificate is generated *inside* the `nginx` container at startup.
- Port `443` (and, for the bonus services, `9090` for Adminer, `21`/`21000-21010` for FTP) free on the host.
- Optional, only for the personal VM development workflow (see [docs/QEMU.md](docs/QEMU.md)): `qemu-system-x86_64`, `qemu-img`, `python3`, `wget`, `ssh-keygen`, `curl`.

## First-time setup

```sh
git clone <this repository> Inception
cd Inception/srcs
cp .env.example .env
$EDITOR .env                     # set DOMAIN and every credential — see docs/CONFIGURATION.md
mkdir -p /home/$USER/data/{mariadb,wordpress,redis}   # make up does this too, but useful to know
make up
```

`srcs/.env` is intentionally **not** tracked by git (see `.gitignore`) — real credentials must never be committed. `srcs/.env.example` documents every variable with placeholder values; see [docs/CONFIGURATION.md](docs/CONFIGURATION.md) for what each one does and which service reads it.

## Repository layout

```
.
├── Makefile                 # VM provisioning (install/run) + docker compose shortcuts
├── .env                      # VM/QEMU settings (ISO, disk, RAM, port forwards) — no secrets
├── install-vm.sh              # Personal dev workflow only: unattended Debian install for QEMU
├── run-vm.sh                   # Personal dev workflow only: boots the VM with port forwards
├── installers/preseed.cfg       # Debian installer preseed
└── srcs/                          # <- this is what's evaluated
    ├── Makefile                    # docker compose up/down/clean-data/fclean/re/logs/ps
    ├── .env.example                  # template — copy to .env and fill in
    ├── docker-compose.yml             # the 7-service stack
    └── requirements/
        ├── mariadb/{Dockerfile, scripts/}
        ├── nginx/{Dockerfile, scripts/}
        ├── wordpress/{Dockerfile, scripts/}
        └── bonus/{adminer,ftp,keycloak,redis}/
```

## Makefile usage

**`srcs/Makefile`** — the actual stack, and the one used for evaluation:

| Target | Effect |
|---|---|
| `make up` | Create `data/{mariadb,wordpress,redis}` under `/home/<login>/`, then `docker compose up -d --build` |
| `make down` | `docker compose down` (data volumes are kept — use `make fclean` to also wipe them) |
| `make clean-data` | Interactive `rm -rf` of all three data dirs (asks for confirmation) |
| `make fclean` | `down` + `clean-data` + `docker system prune -af --volumes` |
| `make re` | `fclean` then `up` — full clean rebuild |
| `make logs` | `docker compose logs -f` |
| `make ps` | `docker compose ps` |

**Root `Makefile`** — a thin convenience wrapper, plus the optional VM workflow (full detail in [docs/QEMU.md](docs/QEMU.md)):

| Target | Effect |
|---|---|
| `make up` / `make down` | Same as `srcs/Makefile`'s, invoked with `-f srcs/docker-compose.yml` from the repo root |
| `make clean-data` | Delete `/home/<login>/data/{mariadb,wordpress}` |
| `make fclean` | `down` + `clean-data` |
| `make install` | *(optional, personal dev only)* unattended Debian install into a QEMU disk image |
| `make run` | *(optional, personal dev only)* boot that VM with all service ports forwarded |
| `make logs` | *(optional)* tail QEMU logs |
| `make clean` | *(optional)* remove the VM's disk/ISO/logs |

A bare `make` at the repository root runs the **first** target, `install` — i.e. it starts VM provisioning, not the Docker stack. This is by design (the VM targets exist for the student's own cross-platform development, not for evaluation), but it means the evaluation should always invoke the stack explicitly with `cd srcs && make up` (or `make -C srcs up` from the root), never a bare `make`.

## Docker Compose commands

Everything the Makefiles do can be run directly:

```sh
docker compose -f srcs/docker-compose.yml up -d --build
docker compose -f srcs/docker-compose.yml ps
docker compose -f srcs/docker-compose.yml logs -f [service]
docker compose -f srcs/docker-compose.yml exec <service> sh
docker compose -f srcs/docker-compose.yml down            # stop, keep volumes
docker compose -f srcs/docker-compose.yml down -v          # stop and delete volumes
```

Each service builds from its own `Dockerfile` under `srcs/requirements/`, all from `debian:bookworm` (no pre-built application images, no `:latest` tag), and each is explicitly named with `image: <service>` matching its `container_name` and Compose service key.

## Data persistence

Two named, host-backed Docker volumes satisfy the mandatory persistence requirement, plus one bonus volume:

| Volume | Container mount | Host path |
|---|---|---|
| `mariadb_data` | `mariadb:/var/lib/mysql` | `/home/<login>/data/mariadb` |
| `wordpress_data` | `wordpress:/var/www/wordpress` (also mounted read-only in `nginx`, read-write in `ftp`) | `/home/<login>/data/wordpress` |
| `redis_data` | `redis:/data` | `/home/<login>/data/redis` |

They use the `local` driver with `driver_opts: {type: none, o: bind, device: ...}` — a bind mount surfaced as a proper named volume, so it's both inspectable with `docker volume inspect` and durable on the host filesystem independent of container/image lifecycle.

**Verifying persistence** (what an evaluator will do): make a change (post a comment, edit a page, add a plugin), then:

```sh
docker compose -f srcs/docker-compose.yml down     # stop everything, keep volumes
# reboot the host/VM if testing that path too
docker compose -f srcs/docker-compose.yml up -d --build
```

WordPress should come back already installed (no setup wizard), the database should still contain your data, and the change you made should still be visible on the site.

## Configuration modification (defense scenario)

During the defense, expect to be asked to change one service's port and prove the stack still works after a rebuild. Concretely, e.g. to move NGINX off 443 to `8843`:

1. Edit `srcs/docker-compose.yml`: change the `nginx` service's `ports:` entry from `"443:443"` to `"8843:443"` (the *container's* internal port stays 443 — only the host-side mapping changes).
2. `cd srcs && make down && make up` (a `--build` is technically not required since no Dockerfile changed, but `make up` always does one, which is harmless).
3. Verify: `curl -Ik https://<DOMAIN>:8843/` should now succeed, and `https://<DOMAIN>:443/` should refuse.

The same pattern (edit the host-side half of one service's `ports:` mapping, then `make down && make up`) applies to any other service's exposed port (Adminer's `9090`, FTP's `21`, etc.).
