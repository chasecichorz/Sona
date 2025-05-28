#!/usr/bin/env bash
set -euo pipefail

ISO="./sona-linux--x86_64.iso"

if [[ ! -f "$ISO" ]]; then
  echo "❌ ISO not found: $ISO"
  echo "Please place your SONA ISO in this folder and rename it to 'sona-linux--x86_64.iso'"
  exit 1
fi

echo "🚀 Booting SONA Linux ISO in QEMU with sound and speech support..."

qemu-system-x86_64 \
  -enable-kvm \
  -m 2048 \
  -cdrom "$ISO" \
  -boot d \
  -soundhw hda \
  -device ich9-intel-hda -device hda-duplex \
  -display default \
  -name "SONA Linux Live" \
  -serial mon:stdio
