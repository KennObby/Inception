#!/bin/sh
set -euo pipefail

# === Loading .env ===
set -a
. ./.env
set +a

# === Derived variables ===
DISK_PATH="$IMAGES_DIR/$DISK_NAME"

# === Cheking if disk exists ===
[ -f "$DISK_PATH" ] || { echo "❌ Disk not found at $DISK_PATH"; echo "➡️  Run ./install-vm.sh first."; exit 1; }

mkdir -p "$LOGS_DIR"

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1"; exit 1; }; }
need_cmd "$QEMU_SYSTEM_BIN"

# accel
accel="tcg,thread=multi"; cpu="max"
if [ "${ACCEL_POLICY}" = "kvm" ] || { [ "${ACCEL_POLICY}" = "auto" ] && [ -w /dev/kvm ] && [ -e /dev/kvm ]; }; then
  accel="kvm"; cpu="host"
fi

# display
ui_args="-nographic"
if [ "${UI_POLICY}" = "gtk" ] || { [ "${UI_POLICY}" = "auto" ] && [ -n "${DISPLAY-}" ]; }; then
  ui_args="-display gtk"
elif [ "${UI_POLICY}" = "sdl" ]; then
  ui_args="-display sdl"
fi

echo "🚀 Booting VM from disk..."
exec "$QEMU_SYSTEM_BIN" \
  -accel "$accel" -cpu "$cpu" \
  -m "$RAM_SIZE" \
  -boot order=c \
  -drive if=none,file="$DISK_PATH",format=qcow2,id=drv0 \
  -device virtio-blk-pci,drive=drv0 \
  -nic "user,model=virtio,hostfwd=tcp::${SSH_HOST_PORT}-:22,hostfwd=tcp::${HTTP_HOST_PORT}-:80,hostfwd=tcp::${HTTPS_HOST_PORT}-:443" \
  -serial "file:$LOGS_DIR/guest-serial.log" \
  -d guest_errors,unimp,pcall -D "$LOGS_DIR/qemu-debug.log" \
  $ui_args \
  2> "$LOGS_DIR/qemu-host.log"
