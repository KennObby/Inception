#!/bin/sh
# Portable, unattended Debian install for QEMU (Arch + 42 friendly)
# - Uses committed installers/preseed.cfg (public)
# - Generates images/preseed.secrets.cfg (private) and images/preseed.bootstrap.cfg
# - Boots netboot kernel with preseed URL over QEMU user-mode NAT (10.0.2.2)

set -eu
# Enable pipefail when available (bash/zsh/ksh); harmless elsewhere
( set -o pipefail ) 2>/dev/null && set -o pipefail || true

# === Load environment ===
set -a
. ./.env
set +a

# On-run Debugs
progress(){ printf '%s %s\n' "[install-vm]" "$*"; }
progress "UNATTENDED=${UNATTENDED:-auto}"
progress "WORKDIR=$WORKDIR"
progress "IMAGES_DIR=$IMAGES_DIR LOGS_DIR=$LOGS_DIR"

# UNATTENDED defaults to "auto": if public preseed exists, we do unattended
UNATTENDED="${UNATTENDED:-auto}"
if [ "$UNATTENDED" = "auto" ] && [ -f "$WORKDIR/installers/preseed.cfg" ]; then
  UNATTENDED=1
fi

ISO_PATH="$IMAGES_DIR/$ISO_NAME"
DISK_PATH="$IMAGES_DIR/$DISK_NAME"
mkdir -p "$IMAGES_DIR" "$LOGS_DIR"

# === Helpers ===
need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1"; exit 1; }; }
need_cmd "$QEMU_SYSTEM_BIN"
need_cmd "$QEMU_IMG_BIN"
need_cmd wget
need_cmd python3
need_cmd ssh-keygen

write_file() { tmp="$1.tmp.$$"; cat >"$tmp"; mv "$tmp" "$1"; }
escape_sed() { printf '%s' "$1" | sed 's/[\/&\\]/\\&/g'; }
gen_random_pw() { LC_ALL=C tr -dc 'A-Za-z0-9._%+-' </dev/urandom | head -c 20; }

hash_pw_sha512() {
  pw="$1"

  set +e
  out="$(python3 - "$pw" 2>/dev/null <<'PY'
import sys
try:
    import crypt
    print(crypt.crypt(sys.argv[1], crypt.mksalt(getattr(crypt, "METHOD_SHA512", None) or crypt.METHOD_SHA512)))
except Exception:
    sys.exit(1)
PY
)"
  st=$?
  set -e
  if [ $st -eq 0 ] && [ -n "$out" ]; then
    printf '%s\n' "$out"; return
  fi

  if command -v openssl >/dev/null 2>&1; then
    out="$(openssl passwd -6 "$pw" 2>/dev/null)" || true
    if [ -n "$out" ]; then printf '%s\n' "$out"; return; fi
  fi

  if command -v mkpasswd >/dev/null 2>&1; then
    out="$(mkpasswd -m sha-512 "$pw" 2>/dev/null)" || true
    if [ -n "$out" ]; then printf '%s\n' "$out"; return; fi
  fi

  echo "⚠️  No hasher available; proceeding with SSH-only login (password disabled)." >&2
  printf '!\n'
}

ensure_pubkey() {
  # If PUBKEY_PATH set and exists, ensure~/.ssh/inception_vm_ed25519{,.pub}
  if [ -n "${PUBKEY_PATH:-}" ] && [ -f "$PUBKEY_PATH" ]; then
    printf '%s\n' "$PUBKEY_PATH"; return
  fi
  base="$HOME/.ssh/inception_vm_ed25519"
  pub="$base.pub"
  if [ ! -f "$pub" ]; then
    >&2 echo "🔐 Generating VM SSH keypair at $base ..."
    mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
    ssh-keygen -t ed25519 -f "$base" -N "" -C "inception-vm" >/dev/null
  fi
  printf '%s\n' "$pub"
}

# === User/secret knobs (can be overridden via env) ===
VM_USER="${VM_USER:-oilyine}"
VM_PASS_HASH="${VM_PASS_HASH:-}"
VM_PASS="${VM_PASS:-}"          
PUBKEY_PATH="${PUBKEY_PATH:-}"

if [ ! -f "$ISO_PATH" ]; then
  echo "🔽 Downloading ISO from $ISO_URL..."
  wget -O "$ISO_PATH" "$ISO_URL"
fi

if [ ! -f "$DISK_PATH" ]; then
  echo "💿 Creating new virtual disk at $DISK_PATH ($DISK_SIZE)..."
  "$QEMU_IMG_BIN" create -f qcow2 "$DISK_PATH" "$DISK_SIZE"
fi

# === Unattended path (netboot + preseed over HTTP) ===
if [ "${UNATTENDED:-0}" = "1" ]; then
  progress "Starting unattended installation..."
  
  NB_DIR="$IMAGES_DIR/netboot"
  mkdir -p "$NB_DIR"
  KURL_BASE="https://deb.debian.org/debian/dists/stable/main/installer-amd64/current/images/netboot/debian-installer/amd64"
  [ -f "$NB_DIR/linux" ]     || wget -O "$NB_DIR/linux"     "$KURL_BASE/linux"
  [ -f "$NB_DIR/initrd.gz" ] || wget -O "$NB_DIR/initrd.gz" "$KURL_BASE/initrd.gz"

  # Secrets assembly
  PUBFILE="$(ensure_pubkey)"
  PUBKEY_CONTENT="$(cat "$PUBFILE")"

  # Password handling
  if [ -z "${VM_PASS_HASH:-}" ]; then
    if [ -n "${VM_PASS:-}" ]; then
      VM_PASS_HASH="$(hash_pw_sha512 "$VM_PASS" 2>/dev/null || echo '!')"
    else
      VM_PASS_HASH='!'
    fi
  fi

  # Generate config files
  REPO_PRESEED="$WORKDIR/installers/preseed.cfg"
  [ -f "$REPO_PRESEED" ] || { echo "❌ Missing $REPO_PRESEED"; exit 1; }
  SECRETS="$IMAGES_DIR/preseed.secrets.cfg"
  BOOTSTRAP="$IMAGES_DIR/preseed.bootstrap.cfg"
  PUBLIC="$IMAGES_DIR/preseed.public.cfg"
  
  cp -f "$REPO_PRESEED" "$PUBLIC"

  write_file "$SECRETS" <<EOF
# --- generated at install time: DO NOT COMMIT ---
d-i passwd/user-fullname string $VM_USER
d-i passwd/username string $VM_USER
d-i passwd/user-password-crypted password $VM_PASS_HASH

d-i pkgsel/run_tasksel boolean false
d-i pkgsel/upgrade select none

d-i preseed/late_command string \
  mkdir -p /target/root/di-logs; \
  cp -a /var/log /target/root/di-logs/varlog || true; \
  cp -a /var/log/installer /target/root/di-logs/installer || true; \
  in-target sh -c "tar -C /root -czf /root/di-logs.tgz di-logs || true"; \
  in-target apt-get update; \
  in-target apt-get -y install --no-install-recommends sudo openssh-server qemu-guest-agent; \
  in-target usermod -aG sudo $VM_USER; \
  in-target mkdir -p /home/$VM_USER/.ssh; \
  in-target sh -c "chmod 700 /home/$VM_USER/.ssh"; \
  in-target sh -c "echo '$(echo "$PUBKEY_CONTENT" | sed 's/[\/&]/\\&/g')' >> /home/$VM_USER/.ssh/authorized_keys"; \
  in-target chown -R $VM_USER:$VM_USER /home/$VM_USER/.ssh; \
  in-target chmod 600 /home/$VM_USER/.ssh/authorized_keys; \
  in-target sh -c 'sed -i "s/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/" /etc/default/grub && update-grub'
EOF

  PRESEED_PORT="${PRESEED_PORT:-8088}"
  write_file "$BOOTSTRAP" <<EOF
# Chain the public preseed and the generated secrets
d-i preseed/include string http://10.0.2.2:${PRESEED_PORT}/$(basename "$PUBLIC") http://10.0.2.2:${PRESEED_PORT}/$(basename "$SECRETS")
EOF

  # Start & test HTTP server
  ( cd "$IMAGES_DIR" && python3 -m http.server "$PRESEED_PORT" >"$LOGS_DIR/http.log" 2>&1 & echo $! > "$LOGS_DIR/http.pid" )
  HTTP_PID=$(cat "$LOGS_DIR/http.pid")
  trap 'kill $HTTP_PID 2>/dev/null || true; wait $HTTP_PID 2>/dev/null || true' EXIT
  
  progress "HTTP server started on port $PRESEED_PORT (PID: $HTTP_PID)"
  sleep 2

  if ! curl -fsS "http://127.0.0.1:${PRESEED_PORT}/$(basename "$BOOTSTRAP")" >/dev/null; then
    echo "❌ HTTP server test failed"
    exit 1
  fi

  # QEMU setup
  accel="tcg,thread=multi"; cpu="max"
  if [ "${ACCEL_POLICY}" = "kvm" ] || { [ "${ACCEL_POLICY}" = "auto" ] && [ -e /dev/kvm ] && [ -w /dev/kvm ]; }; then
    accel="kvm"; cpu="host"
  fi
  ui_args="-nographic"
  [ "${UI_POLICY}" = "gtk" ] && ui_args="-display gtk"
  [ "${UI_POLICY}" = "sdl" ] && ui_args="-display sdl"

  progress "Starting QEMU with preseed..."
  "$QEMU_SYSTEM_BIN" \
    -accel "$accel" -cpu "$cpu" \
    -m "$RAM_SIZE" \
    -boot order=c \
    -kernel "$NB_DIR/linux" \
    -initrd "$NB_DIR/initrd.gz" \
    -append "console=ttyS0,115200n8 auto=true priority=critical preseed/url=http://10.0.2.2:${PRESEED_PORT}/$(basename "$BOOTSTRAP") netcfg/choose_interface=auto ip=dhcp" \
    -drive if=none,file="$DISK_PATH",format=qcow2,id=drv0 \
    -device virtio-blk-pci,drive=drv0 \
    -nic user,model=e1000 \
    -serial "file:$LOGS_DIR/guest-serial.log" \
    -monitor stdio \
    -no-reboot \
    $ui_args

  # Stop HTTP server
  kill $HTTP_PID 2>/dev/null || true
  progress "✅ Installation completed. Use './run-vm.sh' to boot the installed system."
  exit 0
fi

# === Interactive fallback (ISO-based install) ===
echo "🚀 Starting interactive installer (ISO)..."
accel="tcg,thread=multi"; cpu="max"
if [ "${ACCEL_POLICY}" = "kvm" ] || { [ "${ACCEL_POLICY}" = "auto" ] && [ -e /dev/kvm ] && [ -w /dev/kvm ]; }; then
  accel="kvm"; cpu="host"
fi
ui_args="-nographic"
if [ "${UI_POLICY}" = "gtk" ] || { [ "${UI_POLICY}" = "auto" ] && [ -n "${DISPLAY-}" ]; }; then
  ui_args="-display gtk"
elif [ "${UI_POLICY}" = "sdl" ]; then
  ui_args="-display sdl"
fi
progress "Launching QEMU (accel=$accel ui=$ui_args)"

exec "$QEMU_SYSTEM_BIN" \
  -accel "$accel" -cpu "$cpu" \
  -m "$RAM_SIZE" \
  -boot order=d \
  -cdrom "$ISO_PATH" \
  -drive if=none,file="$DISK_PATH",format=qcow2,id=drv0 \
  -device virtio-blk-pci,drive=drv0 \
  -nic user,model=virtio \
  -serial "file:$LOGS_DIR/guest-serial.log" \
  -d guest_errors,unimp,pcall -D "$LOGS_DIR/qemu-debug.log" \
  $ui_args \
  2> "$LOGS_DIR/qemu-host.log"
