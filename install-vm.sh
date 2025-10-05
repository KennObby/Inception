#!/bin/sh
set -euo pipefail

# === Loading environment variables ===
set -a
. ./.env
set +a

# === Derived variables ===

ISO_PATH="$IMAGES_DIR/$ISO_NAME"
DISK_PATH="$IMAGES_DIR/$DISK_NAME"

# === Ensuring workdir exists ===
mkdir -p "$IMAGES_DIR" "$LOGS_DIR"

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1"; exit 1; };}

need_cmd "$QEMU_SYSTEM_BIN"
need_cmd "$QEMU_IMG_BIN"
need_cmd wget

# === Checking ISO... ===
if [ ! -f "$ISO_PATH" ] ; then
    echo "🔽 Downloading ISO from $ISO_URL..."
    wget -O "$ISO_PATH" "$ISO_URL"
fi

# === Checking for virtual disk ===
if [ ! -f "$DISK_PATH" ]; then 
    echo "💿 Creating new virtual disk at $DISK_PATH ($DISK_SIZE)..."
    "$QEMU_IMG_BIN" create -f qcow2 "$DISK_PATH" "$DISK_SIZE"
fi

# === Accel flags ===
accel="tcg,thread=multi"; cpu="max"
if [ "${ACCEL_POLICY}" = "kvm" ] || { [ "${ACCEL_POLICY}" = "auto" ] && [ -w /dev/kvm ] && [ -e /dev/kvm ]; }; then
    accel="kvm"; cpu="host"
fi

# === Display usage ===
ui_args="-nographic"
if [ "${UI_POLICY}" = "gtk" ] || { [ "${UI_POLICY}" = "auto" ] && [ -n "${DISPLAY}" ]; }; then
    ui_args="-display gtk"
elif [ "${UI_POLICY}" = "sdl" ]; then
    ui_args="-display sdl"
fi

# === Running QEMU ===
echo "🚀 Starting Debian installer..."
exec "$QEMU_SYSTEM_BIN" \
  -accel "$accel" \
  -cpu "$cpu" \
  -m "$RAM_SIZE" \
  -boot order=d \
  -cdrom "$ISO_PATH" \
  -drive if=none,file="$DISK_PATH",format=qcow2,id=drv0 \
  -device virtio-blk-pci,drive=drv0 \
  -nic user,model=virtio \
  -serial file:"$LOGS_DIR/guest-serial.log" \
  -d guest_errors,unimp,pcall -D "$LOGS_DIR/qemu-debug.log" \
  $ui_args \
  2> "$LOGS_DIR/qemu-host.log"

