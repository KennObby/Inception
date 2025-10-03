#!/bin/sh

# === Loading .env ===
set -a
. ./.env
set +a

# === Derived variables ===
DISK_PATH="$WORKDIR/$DISK_NAME"

# === Cheking if disk exists ===
if [ ! -f "$DISK_PATH" ]; then
    echo "❌ Virtual disk not found at $DISK_PATH"
    echo "➡️  Run ./install-vm.sh first to install Debian."
    exit 1
fi

# === Run the VM ===
echo "🚀 Booting VM from disk..."
qemu-system-x86_64 \
    -enable-kvm \
    -m "$RAM_SIZE" \
    -boot order=c \
    -drive if=none,file="$DISK_PATH",format=qcow2,id=drv0 \
    -device virtio-blk-pci,drive=drv0 \
    -nic user,model=virtio,hostfwd=tcp::2222-:22,hostfwd=tcp::8080-:80,hostfwd=tcp::8443-:443 \
    -serial file:"$LOGS/guest-serial.log" \
    -d guest_errors,unimp,pcall -D "$LOGS/qemu-debug.log" \
    -display gtk \
    2> "$LOGS/qemu-host.log"
