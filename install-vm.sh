#!/bin/sh
# Portable, unattended Debian install for QEMU (Arch + 42 friendly)

# ---- Strict, but POSIX-safe ----
set -e  # (avoid -u; it can kill on harmless env lookups)
# Try pipefail only if shell supports it
( set -o pipefail ) >/dev/null 2>&1 && set -o pipefail || true

progress(){ printf '%s %s\n' "[install-vm]" "$*"; }

# === Load environment ===
set -a
. ./.env
set +a

progress "UNATTENDED=${UNATTENDED:-auto}"
progress "WORKDIR=$WORKDIR"
progress "IMAGES_DIR=$IMAGES_DIR LOGS_DIR=$LOGS_DIR"

# UNATTENDED: auto → 1 if public preseed exists
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
need_cmd curl

write_file() { tmp="$1.tmp.$$"; cat >"$tmp"; mv "$tmp" "$1"; }
escape_sed() { printf '%s' "$1" | sed 's/[\/&\\]/\\&/g'; }

gen_random_pw() {
  # No pipelines here (so no SIGPIPE surprises)
  LC_ALL=C tr -dc 'A-Za-z0-9._%+-' </dev/urandom | head -c 20
}

hash_pw_sha512() {
  pw="$1"
  # Prefer Python crypt; fall back to openssl or mkpasswd
  if out="$(python3 - "$pw" 2>/dev/null <<'PY'
import sys
try:
    import crypt
    print(crypt.crypt(sys.argv[1], crypt.mksalt(getattr(crypt, "METHOD_SHA512", None) or crypt.METHOD_SHA512)))
except Exception:
    sys.exit(1)
PY
)"; then
    [ -n "$out" ] && { printf '%s\n' "$out"; return 0; }
  fi
  if command -v openssl >/dev/null 2>&1; then
    out="$(openssl passwd -6 "$pw" 2>/dev/null || true)"
    [ -n "$out" ] && { printf '%s\n' "$out"; return 0; }
  fi
  if command -v mkpasswd >/dev/null 2>&1; then
    out="$(mkpasswd -m sha-512 "$pw" 2>/dev/null || true)"
    [ -n "$out" ] && { printf '%s\n' "$out"; return 0; }
  fi
  echo "⚠️  No hasher available; using SSH-key only (password disabled)." >&2
  printf '!\n'
}

ensure_pubkey() {
  # Use provided PUBKEY_PATH if valid
  if [ -n "${PUBKEY_PATH:-}" ] && [ -f "$PUBKEY_PATH" ]; then
    printf '%s\n' "$PUBKEY_PATH"
    return 0
  fi
  base="$HOME/.ssh/inception_vm_ed25519"
  pub="$base.pub"
  # Ensure ~/.ssh exists
  [ -d "$HOME/.ssh" ] || { mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"; }
  # Generate if missing (but never fail the install)
  if [ ! -f "$pub" ]; then
    >&2 echo "🔐 Generating VM SSH keypair at $base ..."
    if ! ssh-keygen -t ed25519 -f "$base" -N "" -C "inception-vm" >/dev/null 2>&1; then
      >&2 echo "❌ ssh-keygen failed; skipping SSH key injection."
      return 1
    fi
  fi
  [ -f "$pub" ] || { >&2 echo "❌ Public key not found at $pub; skipping."; return 1; }
  printf '%s\n' "$pub"
  return 0
}

# === User/secret knobs (env overrides allowed) ===
VM_USER="${VM_USER:-oilyine}"
VM_PASS_HASH="${VM_PASS_HASH:-}"
VM_PASS="${VM_PASS:-}"
SAVE_CREDENTIALS="${SAVE_CREDENTIALS:-1}"

# === Ensure ISO & disk ===
if [ ! -f "$ISO_PATH" ]; then
  echo "🔽 Downloading ISO from $ISO_URL..."
  wget -O "$ISO_PATH" "$ISO_URL"
fi

if [ ! -f "$DISK_PATH" ]; then
  echo "💿 Creating new virtual disk at $DISK_PATH ($DISK_SIZE)..."
  "$QEMU_IMG_BIN" create -f qcow2 "$DISK_PATH" "$DISK_SIZE"
fi

# === Unattended path ===
if [ "${UNATTENDED:-0}" = "1" ]; then
  progress "Starting unattended installation..."

  NB_DIR="$IMAGES_DIR/netboot"
  mkdir -p "$NB_DIR"
  KURL_BASE="https://deb.debian.org/debian/dists/stable/main/installer-amd64/current/images/netboot/debian-installer/amd64"
  [ -f "$NB_DIR/linux" ]     || wget -O "$NB_DIR/linux"     "$KURL_BASE/linux"
  [ -f "$NB_DIR/initrd.gz" ] || wget -O "$NB_DIR/initrd.gz" "$KURL_BASE/initrd.gz"

  progress "Netboot assets ready"

  # Secrets assembly
  PUBFILE=""; PUBKEY_CONTENT=""
  if PUBFILE="$(ensure_pubkey)"; then
    if [ -f "$PUBFILE" ]; then
      PUBKEY_CONTENT="$(cat "$PUBFILE" || true)"
      progress "SSH pubkey loaded from $PUBFILE"
    fi
  else
    progress "Proceeding without SSH key injection"
  fi

  # Password handling (generate if not provided)
  if [ -z "$VM_PASS_HASH" ]; then
    if [ -n "$VM_PASS" ]; then
      VM_PASS_HASH="$(hash_pw_sha512 "$VM_PASS" 2>/dev/null || echo '!')"
    else
      VM_PASS="$(gen_random_pw || printf 'changeme')"
      VM_PASS_HASH="$(hash_pw_sha512 "$VM_PASS" 2>/dev/null || echo '!')"
    fi
  fi
  progress "Credentials prepared (user=$VM_USER, pass_present=$([ -n "$VM_PASS" ] && echo yes || echo no))"

  # Optionally save credentials
  if [ "$SAVE_CREDENTIALS" = "1" ]; then
    CREDENTIALS_FILE="$LOGS_DIR/vm-credentials.txt"
    write_file "$CREDENTIALS_FILE" <<EOF
=== VM Credentials ===
Username: $VM_USER
Password: $VM_PASS
SSH Key: ${PUBFILE:-<none>}
SSH Command: ssh -p ${SSH_HOST_PORT:-2222} $VM_USER@localhost
EOF
    progress "✅ Credentials saved to: $CREDENTIALS_FILE"
  fi

  # Generate preseed files
  REPO_PRESEED="$WORKDIR/installers/preseed.cfg"
  [ -f "$REPO_PRESEED" ] || { echo "❌ Missing $REPO_PRESEED"; exit 1; }

  SECRETS="$IMAGES_DIR/preseed.secrets.cfg"
  BOOTSTRAP="$IMAGES_DIR/preseed.bootstrap.cfg"
  PUBLIC="$IMAGES_DIR/preseed.public.cfg"

  cp -f "$REPO_PRESEED" "$PUBLIC"
  progress "Public preseed copied → $PUBLIC"

  # Build the secrets preseed
  AK_LINE1=""
  AK_LINE2=""
  if [ -n "$PUBKEY_CONTENT" ]; then
    esc_key="$(escape_sed "$PUBKEY_CONTENT")"
    AK_LINE1="  in-target sh -c \"echo '$esc_key' >> /home/$VM_USER/.ssh/authorized_keys\"; \\"
    AK_LINE2="  in-target chmod 600 /home/$VM_USER/.ssh/authorized_keys; \\"
  fi

  write_file "$SECRETS" <<EOF
# --- generated at install time: DO NOT COMMIT ---
d-i passwd/user-fullname string $VM_USER
d-i passwd/username string $VM_USER
d-i passwd/user-password-crypted password $VM_PASS_HASH

d-i pkgsel/run_tasksel boolean false
d-i pkgsel/upgrade select none

# Optional lightweight desktop & fonts
d-i pkgsel/include string \
  openssh-server sudo curl ca-certificates neovim git qemu-guest-agent \
  xorg x11-apps xterm xdg-user-dirs \
  xwayland weston wayland-protocols \
  firefox-esr fonts-noto-core fonts-noto-cjk fonts-noto-color-emoji

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
$AK_LINE1
$AK_LINE2
  in-target sh -c 'sed -i "s/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/" /etc/default/grub && update-grub'; \
  in-target systemctl enable ssh || true
EOF
  progress "Secrets preseed written → $SECRETS"

  PRESEED_PORT="${PRESEED_PORT:-8088}"
  write_file "$BOOTSTRAP" <<EOF
# Chain the public preseed and the generated secrets
d-i preseed/include string http://10.0.2.2:${PRESEED_PORT}/$(basename "$PUBLIC") http://10.0.2.2:${PRESEED_PORT}/$(basename "$SECRETS")
EOF
  progress "Bootstrap preseed written → $BOOTSTRAP"

  # Start & test HTTP server
  ( cd "$IMAGES_DIR" && python3 -m http.server "$PRESEED_PORT" >"$LOGS_DIR/http.log" 2>&1 & echo $! > "$LOGS_DIR/http.pid" )
  HTTP_PID="$(cat "$LOGS_DIR/http.pid")"
  trap 'kill "$HTTP_PID" 2>/dev/null || true; wait "$HTTP_PID" 2>/dev/null || true' EXIT

  progress "HTTP server starting on :$PRESEED_PORT (PID=$HTTP_PID)"
  sleep 1
  curl -fsS "http://127.0.0.1:${PRESEED_PORT}/$(basename "$BOOTSTRAP")" >/dev/null
  progress "HTTP server OK"

  # Accel choice
  accel="tcg,thread=multi"; cpu="max"
  if [ "${ACCEL_POLICY}" = "kvm" ] || { [ "${ACCEL_POLICY}" = "auto" ] && [ -e /dev/kvm ] && [ -w /dev/kvm ]; }; then
    accel="kvm"; cpu="host"
  fi

  # UI policy
  ui_args=""
  case "${UI_POLICY}" in
    gtk)
      if [ -n "${DISPLAY-}" ]; then ui_args="-display gtk -device virtio-vga"; progress "Display: GTK + virtio-vga"; else ui_args="-nographic"; progress "Display: none"; fi
      ;;
    sdl)
      if [ -n "${DISPLAY-}" ]; then ui_args="-display sdl -device virtio-vga"; progress "Display: SDL + virtio-vga"; else ui_args="-nographic"; progress "Display: none"; fi
      ;;
    spice)
      ui_args="-spice port=5930,disable-ticketing -device qxl-vga -device virtio-serial-pci -chardev spicevmc,id=spicechannel0,name=vdagent -device virtserialport,chardev=spicechannel0,name=com.redhat.spice.0"
      progress "Display: SPICE on :5930"
      ;;
    *)
      if [ -n "${DISPLAY-}" ]; then ui_args="-display gtk -device virtio-vga"; progress "Display: auto → GTK + virtio-vga"; else ui_args="-nographic"; progress "Display: auto → nographic"; fi
      ;;
  esac

  # Audio (optional)
  audio_args=""
  if [ "${AUDIO_POLICY:-off}" = "on" ] && command -v pactl >/dev/null 2>&1; then
    audio_args="-audiodev pa,id=audio0 -device AC97,audiodev=audio0"
    progress "Audio: PulseAudio backend enabled"
  fi

  # Kernel append: serial console ONLY for -nographic
  append_args="auto=true priority=critical preseed/url=http://10.0.2.2:${PRESEED_PORT}/$(basename "$BOOTSTRAP") netcfg/choose_interface=auto ip=dhcp"
  case "$ui_args" in *-nographic*) append_args="console=ttyS0,115200n8 $append_args" ;; esac

  progress "Launching QEMU (accel=$accel cpu=$cpu) ..."
  if ! "$QEMU_SYSTEM_BIN" \
      -accel "$accel" -cpu "$cpu" \
      -m "$RAM_SIZE" \
      -boot order=c \
      -kernel "$NB_DIR/linux" \
      -initrd "$NB_DIR/initrd.gz" \
      -append "$append_args" \
      -drive if=none,file="$DISK_PATH",format=qcow2,id=drv0 \
      -device virtio-blk-pci,drive=drv0 \
      -nic "user,model=virtio,hostfwd=tcp::${SSH_HOST_PORT:-2222}-:22" \
      -serial "file:$LOGS_DIR/guest-serial.log" \
      -monitor stdio \
      -no-reboot \
      $ui_args $audio_args
  then
    progress "⚠️ QEMU exited with error, see logs in $LOGS_DIR"
    exit 1
  fi

  kill "$HTTP_PID" 2>/dev/null || true
  progress "✅ Installation completed. Use './run-vm.sh' to boot."
  [ -n "${CREDENTIALS_FILE:-}" ] && { progress "📋 Credentials → $CREDENTIALS_FILE"; }
  exit 0
fi

# === Interactive fallback (ISO) ===
echo "🚀 Starting interactive installer (ISO)..."
accel="tcg,thread=multi"; cpu="max"
if [ "${ACCEL_POLICY}" = "kvm" ] || { [ "${ACCEL_POLICY}" = "auto" ] && [ -e /dev/kvm ] && [ -w /dev/kvm ]; }; then
  accel="kvm"; cpu="host"
fi

ui_args=""
case "${UI_POLICY}" in
  gtk) if [ -n "${DISPLAY-}" ]; then ui_args="-display gtk -device virtio-vga"; else ui_args="-nographic"; fi ;;
  sdl) if [ -n "${DISPLAY-}" ]; then ui_args="-display sdl -device virtio-vga"; else ui_args="-nographic"; fi ;;
  spice) ui_args="-spice port=5930,disable-ticketing -device qxl-vga -device virtio-serial-pci -chardev spicevmc,id=spicechannel0,name=vdagent -device virtserialport,chardev=spicechannel0,name=com.redhat.spice.0" ;;
  *) if [ -n "${DISPLAY-}" ]; then ui_args="-display gtk -device virtio-vga"; else ui_args="-nographic"; fi ;;
esac

progress "Launching QEMU (accel=$accel ui=$UI_POLICY)"
exec "$QEMU_SYSTEM_BIN" \
  -accel "$accel" -cpu "$cpu" \
  -m "$RAM_SIZE" \
  -boot order=d \
  -cdrom "$ISO_PATH" \
  -drive if=none,file="$DISK_PATH",format=qcow2,id=drv0 \
  -device virtio-blk-pci,drive=drv0 \
  -nic "user,model=virtio,hostfwd=tcp::${SSH_HOST_PORT:-2222}-:22" \
  -serial "file:$LOGS_DIR/guest-serial.log" \
  -d guest_errors,unimp,pcall -D "$LOGS_DIR/qemu-debug.log" \
  $ui_args \
  2> "$LOGS_DIR/qemu-host.log"
