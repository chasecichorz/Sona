#!/usr/bin/env bash
# Boot the Sona Linux ISO in a QEMU virtual machine with sound, so you can
# test the live system and the installer without touching a real disk.
#
# Usage:
#   scripts/boot-sona-qemu.sh                 newest ISO in out/, UEFI
#   scripts/boot-sona-qemu.sh path/to.iso     a specific ISO
#   BIOS=1 scripts/boot-sona-qemu.sh          test legacy BIOS booting
#
# A 40 GB virtual disk (out/sona-test-disk.qcow2) is created on first run.
# Install onto that disk to test the installer. Delete the file to start over.
#
# Needs: qemu-desktop (or qemu-full), and edk2-ovmf for UEFI.

set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="$repo_dir/out"

if [[ $# -ge 1 ]]; then
    iso="$1"
else
    iso=$(ls -1t "$out_dir"/*.iso 2>/dev/null | head -n 1 || true)
fi

if [[ -z "$iso" || ! -f "$iso" ]]; then
    echo "Error: no ISO found. Build one with: sudo scripts/build-iso.sh" >&2
    echo "Or pass the path to an ISO as the first argument." >&2
    exit 1
fi

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "Error: QEMU is missing. Install it with: sudo pacman -S qemu-desktop edk2-ovmf" >&2
    exit 1
fi

mkdir -p "$out_dir"
disk="$out_dir/sona-test-disk.qcow2"
if [[ ! -f "$disk" ]]; then
    qemu-img create -f qcow2 "$disk" 40G
fi

firmware_args=()
if [[ "${BIOS:-0}" != "1" ]]; then
    ovmf_code=/usr/share/edk2/x64/OVMF_CODE.4m.fd
    ovmf_vars_template=/usr/share/edk2/x64/OVMF_VARS.4m.fd
    if [[ ! -f "$ovmf_code" ]]; then
        echo "Error: UEFI firmware is missing. Install it with: sudo pacman -S edk2-ovmf" >&2
        echo "Or test BIOS mode instead: BIOS=1 $0" >&2
        exit 1
    fi
    ovmf_vars="$out_dir/sona-test-uefi-vars.fd"
    [[ -f "$ovmf_vars" ]] || cp "$ovmf_vars_template" "$ovmf_vars"
    firmware_args=(
        -drive "if=pflash,format=raw,readonly=on,file=$ovmf_code"
        -drive "if=pflash,format=raw,file=$ovmf_vars"
    )
fi

accel_args=(-machine q35)
if [[ -w /dev/kvm ]]; then
    accel_args=(-machine q35,accel=kvm -cpu host)
fi

echo "Booting $iso"
qemu-system-x86_64 \
    "${accel_args[@]}" \
    "${firmware_args[@]}" \
    -m 4096 \
    -smp 4 \
    -drive "file=$disk,if=virtio,format=qcow2" \
    -cdrom "$iso" \
    -boot order=d,menu=on \
    -audiodev pipewire,id=snd0 \
    -device intel-hda \
    -device hda-duplex,audiodev=snd0 \
    -nic user,model=virtio-net-pci \
    -name "Sona Linux test"
