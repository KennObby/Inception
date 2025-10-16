#!/bin/sh
set -euo pipefail

# === Load .env ===
set -a
. ./.env
set +a

DISK_PATH="$IMAGES_DIR/$DISK_NAME"

# Disk check
[ -f "$DISK_PATH" ] || { echo "❌ Disk not found at $DISK_PATH"; echo "➡️  Run ./install-vm.sh first."; exit 1; }

mkdir -p "$LOGS_DIR"

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1"; exit 1; }; }
need_cmd "$QEMU_SYSTEM_BIN"

# accel
accel="tcg,thread=multi"; cpu="max"
if [ "${ACCEL_POLICY}" = "kvm" ] || { [ "${ACCEL_POLICY}" = "auto" ] && [ -e /dev/kvm ] && [ -w /dev/kvm ]; }; then
  accel="kvm"; cpu="host"
fi

# display (safe graphics)
ui_args=""
case "${UI_POLICY}" in
  gtk)
    if [ -n "${DISPLAY-}" ]; then ui_args="-display gtk -device virtio-vga"; else ui_args="-nographic"; fi
    ;;
  sdl)
    if [ -n "${DISPLAY-}" ]; then ui_args="-display sdl -device virtio-vga"; else ui_args="-nographic"; fi
    ;;
  spice)
    ui_args="-spice port=5930,disable-ticketing -device qxl-vga -device virtio-serial-pci -chardev spicevmc,id=spicechannel0,name=vdagent -device virtserialport,chardev=spicechannel0,name=com.redhat.spice.0"
    ;;
  *)
    if [ -n "${DISPLAY-}" ]; then ui_args="-display gtk -device virtio-vga"; else ui_args="-nographic"; fi
    ;;
esac

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
