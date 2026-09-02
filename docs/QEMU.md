# QEMU VM workflow (`install-vm.sh` / `run-vm.sh`)

This covers the Debian VM provisioning scripts at the repository root — the standard way this project is run and tested: a QEMU-managed Debian VM that runs the `srcs/` Docker stack, reached from the host through QEMU's NAT port forwarding.

## What the two scripts do

| Script | Role |
|---|---|
| `install-vm.sh` | One-time (or repeatable) unattended install of Debian 13 into a fresh QEMU disk image. |
| `run-vm.sh` | Boots the already-installed disk image, with every service port forwarded from the host. |

Both are driven by the root `/.env` file (see [docs/CONFIGURATION.md](CONFIGURATION.md) for the full variable reference) and are invoked through the root `Makefile`:

```sh
make install     # == UI_POLICY=auto UNATTENDED=1 ./install-vm.sh
make run          # == ./run-vm.sh
make logs         # tail qemu-host.log / qemu-debug.log / guest-serial.log
make debug        # re-run install-vm.sh with `sh -x` tracing
make clean        # remove $IMAGES_DIR and $LOGS_DIR (disk image, ISO, logs)
```

## Prerequisites

- `qemu-system-x86_64`, `qemu-img` (override the binary paths with `QEMU_SYSTEM_BIN`/`QEMU_IMG_BIN` in `.env` if using a non-system build, e.g. from `~/goinfre`).
- `wget`, `curl`, `python3`, `ssh-keygen` on the host.
- Enough free disk under `$IMAGES_DIR` for the ISO/netboot images and the VM disk (`DISK_SIZE`, default `20G`).

## `install-vm.sh` walkthrough

1. **Loads `/.env`** (`set -a; . ./.env; set +a`) for `WORKDIR`, `IMAGES_DIR`, `LOGS_DIR`, `ISO_NAME`/`ISO_URL`, `DISK_NAME`/`DISK_SIZE`, `RAM_SIZE`, the QEMU binary paths, and the port-forward variables.
2. **Decides unattended vs. interactive.** `UNATTENDED` defaults to `auto`, which becomes `1` if `installers/preseed.cfg` exists (it does, in this repo) — so `make install` always takes the unattended path unless you override `UNATTENDED=0`.
3. **Fetches the ISO** (`$ISO_URL`, a Debian 13 netinst image) into `$IMAGES_DIR` if not already present, and creates the qcow2 disk (`qemu-img create`) if not already present.
4. **Unattended path** (`UNATTENDED=1`):
   - Downloads the matching netboot `linux` kernel + `initrd.gz` for `DEBIAN_SUITE` (default `bookworm` for the installer environment itself — unrelated to the Debian version used *inside* the containers, which is pinned separately in each Dockerfile).
   - Generates (or reuses) an SSH keypair at `~/.ssh/inception_vm_ed25519` and reads its public key, to be injected as an `authorized_keys` entry for the VM user.
   - Generates a random password (or hashes one you supply via `VM_PASS`/`VM_PASS_HASH`) with `python3`'s `crypt` module (falling back to `openssl passwd -6` or `mkpasswd`).
   - Optionally (`SAVE_CREDENTIALS=1`, the default) writes the generated username/password/SSH command to `$LOGS_DIR/vm-credentials.txt` — this file is gitignored, never commit it.
   - Builds three preseed files in `$IMAGES_DIR`: the repo's public `preseed.cfg` copied verbatim, a generated `preseed.secrets.cfg` (username/password hash, SSH key injection, and a `late_command` that installs `sudo`/`openssh-server`/`qemu-guest-agent`, adds the user to `sudo`, and enables SSH), and a `preseed.bootstrap.cfg` that chains the two via `d-i preseed/include`.
   - Serves `$IMAGES_DIR` over a local `python3 -m http.server` on `PRESEED_PORT` (default `8088`), which the installer inside QEMU reaches at `http://10.0.2.2:$PRESEED_PORT/...` (`10.0.2.2` is QEMU user-mode networking's address for the host).
   - Boots QEMU straight into the Debian installer kernel (`-kernel`/`-initrd`, not `-cdrom`), passing `preseed/url=` on the kernel command line so the installer fetches the bootstrap preseed automatically — no manual interaction required.
   - Picks acceleration (`ACCEL_POLICY`: `auto` uses KVM if `/dev/kvm` is present and writable, else falls back to software emulation via TCG) and display backend (`UI_POLICY`: `gtk`/`sdl`/`spice`, or `auto` — GTK if `$DISPLAY` is set, otherwise headless with a serial console).
   - On success, tears down the HTTP server and prints where the credentials were saved.
5. **Interactive fallback** (`UNATTENDED=0` or no preseed file): boots the same disk from the downloaded ISO via `-cdrom`, letting you click through the Debian installer manually.

## `run-vm.sh` walkthrough

1. Loads `/.env` the same way, and refuses to run if `$DISK_PATH` doesn't exist yet (i.e. `install-vm.sh` hasn't completed).
2. Picks acceleration and display backend using the same `ACCEL_POLICY`/`UI_POLICY` logic as the installer.
3. Boots the installed disk directly (`-boot order=c`, no installer kernel involved) with a single `-nic user,...` device carrying every port forward the stack needs:

   | Host port (`.env` var) | Forwarded to VM port | Purpose |
   |---|---|---|
   | `SSH_HOST_PORT` (`2222`) | `22` | `ssh -p 2222 <user>@localhost` |
   | `HTTP_HOST_PORT` (`8080`) | `80` | Redirects to HTTPS |
   | `HTTPS_HOST_PORT` (`8443`) | `443` | Browse to the WordPress site from the host — this is the port that matters, since it's the only one that actually reaches the VM's NGINX from outside |
   | `KEYCLOAK_HOST_PORT` (`8081`) | `8080` | Currently unused — see the note in [docs/CONFIGURATION.md](CONFIGURATION.md); Keycloak is reached through NGINX's `/auth/` proxy instead |
   | `ADMINER_HOST_PORT` (`9090`) | `9090` | Adminer web UI |
   | `FTP_HOST_PORT` (`2121`) | `21` | FTP control connection |
   | `FTP_PASSIVE_MIN`–`FTP_PASSIVE_MAX` (`21000`–`21010`) | same range, 1:1 | FTP passive-mode data connections |

   `srcs/docker-compose.yml`'s `nginx` service publishes both `443` and `80` (redirecting to `443`). `WP_PUBLIC_URL`, the Keycloak issuer/redirect URLs, and NGINX's own forwarded-port headers are all set to `:8443` to match this forward — see [docs/CONFIGURATION.md](CONFIGURATION.md). A client *inside* the VM (e.g. over the SSH session used to reach it) talks to the containers directly and doesn't need `:8443`; anything outside the VM does.
4. Logs QEMU's own stderr/debug output to `$LOGS_DIR/qemu-host.log` and `qemu-debug.log`, and the guest's serial console to `guest-serial.log`.

## Typical workflow

```sh
make install                      # unattended Debian install, ~5-10 min
make run                           # boot the VM with all ports forwarded
ssh -p 2222 oilyine@localhost        # credentials in $LOGS_DIR/vm-credentials.txt
# inside the VM:
git clone <this repo> ~/Inception
cd ~/Inception/srcs
cp .env.example .env && $EDITOR .env
make up
# from the host machine's browser:
#   https://oilyine.42.lu:8443/   (:8443 is the VM's NAT port forward — see above)
```

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| QEMU exits immediately complaining about `/dev/kvm` | `ACCEL_POLICY=kvm` forced but `/dev/kvm` isn't readable/writable by your user — add yourself to the `kvm` group, or leave `ACCEL_POLICY=auto` to fall back to (slower) TCG emulation |
| Install hangs at "Waiting for temporary..." / preseed never fetched | The `PRESEED_PORT` HTTP server didn't start (port already in use) — `install-vm.sh` tries to free it automatically (`fuser`/`lsof`), but check `$LOGS_DIR/http.log` if it still fails |
| `make run` says "Disk not found" | Run `make install` first — `run-vm.sh` boots an already-installed disk, it doesn't install one |
| SSH connection refused after boot | Give the VM a few seconds to finish booting and start `sshd`; then `ssh -p 2222 <user>@localhost` using the credentials in `$LOGS_DIR/vm-credentials.txt` |
| Want a completely fresh VM | `make clean` (removes the disk image, ISO, and logs), then `make install` again |
| Browser can't reach the site via the VM | Confirm you're using `HTTPS_HOST_PORT` (default `8443`), not bare `443`, when going through the VM's NAT — and that `srcs`'s `make up` has actually completed inside the VM |
