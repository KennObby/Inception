#!/bin/sh

# === Loading environment variables ===
set -a
. ./.env
set +a

# === Derived variables ===

ISO_PATH="$WORKDIR/$ISO_NAME"
DISK_PATH="$WORKDIR/$DISK_NAME"

# === Ensuring workdir exists ===
mkdir -p "$WORKDIR"
mkdir -p "$LOGS"


# === Checking ISO... ===
[ -f "$ISO_PATH" ] || {
    echo "🔽 ISO not found. Downloading from $ISO_URL..."
    wget -O "$ISO_PATH" "$ISO_URL" || { echo "❌ Failed to download ISO"; exit 1; }
}

# === Checking for virtual disk ===
[ -f "$DISK_PATH" ] || {
    echo "💿 Creating new virtual disk (20G)..."
    qemu-img create -f qcow2 "$DISK_PATH" 20G
}

# === Running QEMU ===
echo "🚀 Starting QEMU..."
exec qemu-system-x86_64 \
  -enable-kvm \
  -cpu host \
  -m "$RAM_SIZE" \
  -boot order=d \
  -cdrom "$ISO_PATH" \
  -drive if=none,file="$DISK_PATH",format=qcow2,id=drv0 \
  -device virtio-blk-pci,drive=drv0 \
  -nic user,model=virtio \
  -serial file:"$LOGS/guest-serial.log" \
  -d guest_errors,unimp,pcall -D "$LOGS/qemu-debug.log" \
  -display gtk \
  2> "$LOGS/qemu-host.log"

