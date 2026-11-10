#!/usr/bin/env bash
# Automated install test.
#
# 1. Boots the ISO in a QEMU virtual machine with a blank 40 GB disk.
# 2. The live system downloads scripts/ci/startup.sh, which runs
#    sona-install --unattended with scripts/ci/answers.conf.
# 3. Boots the installed disk and checks that it reaches a login prompt
#    and starts the desktop (LightDM).
#
# Usage: scripts/ci-install-test.sh path/to/sona.iso [uefi|bios]
#
# Logs are written to $LOG_DIR (default: out/ci-logs).
# Needs: qemu-system-x86_64, qemu-img, bsdtar, python3, and OVMF for UEFI.

set -euo pipefail

iso="${1:?usage: $0 path/to/sona.iso [uefi|bios]}"
firmware="${2:-uefi}"
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
log_dir="${LOG_DIR:-$repo_dir/out/ci-logs}"
install_timeout_min="${INSTALL_TIMEOUT_MIN:-110}"
boot_timeout_sec="${BOOT_TIMEOUT_SEC:-600}"

work="$(mktemp -d)"
server_pid=""
qemu_pid=""
cleanup() {
    [[ -n "$qemu_pid" ]] && kill "$qemu_pid" 2>/dev/null || true
    [[ -n "$server_pid" ]] && kill "$server_pid" 2>/dev/null || true
    rm -rf "$work"
}
trap cleanup EXIT

mkdir -p "$log_dir"
install_log="$log_dir/install-$firmware.log"
boot_log="$log_dir/boot-$firmware.log"
: > "$install_log"
: > "$boot_log"

echo "== Sona install test ($firmware)"
echo "ISO: $iso"

# --- Kernel and initramfs from the ISO (QEMU starts them directly, so we
# --- can add our own boot options without using the boot menu).
bsdtar -xf "$iso" -C "$work" arch/boot/x86_64/vmlinuz-linux arch/boot/x86_64/initramfs-linux.img
kernel="$work/arch/boot/x86_64/vmlinuz-linux"
initrd="$work/arch/boot/x86_64/initramfs-linux.img"

# --- Small web server the virtual machine reaches at 10.0.2.2:8000.
mkdir -p "$work/www"
cp "$repo_dir/scripts/ci/startup.sh" "$repo_dir/scripts/ci/answers.conf" "$work/www/"
python3 -m http.server 8000 --bind 127.0.0.1 --directory "$work/www" >"$log_dir/http-$firmware.log" 2>&1 &
server_pid=$!

disk="$work/disk.qcow2"
qemu-img create -q -f qcow2 "$disk" 40G

# --- Firmware.
firmware_args=()
if [[ "$firmware" == "uefi" ]]; then
    ovmf_code="" ovmf_vars=""
    for pair in \
        "/usr/share/OVMF/OVMF_CODE_4M.fd:/usr/share/OVMF/OVMF_VARS_4M.fd" \
        "/usr/share/edk2/x64/OVMF_CODE.4m.fd:/usr/share/edk2/x64/OVMF_VARS.4m.fd" \
        "/usr/share/OVMF/OVMF_CODE.fd:/usr/share/OVMF/OVMF_VARS.fd"; do
        if [[ -f "${pair%%:*}" && -f "${pair##*:}" ]]; then
            ovmf_code="${pair%%:*}"
            ovmf_vars="${pair##*:}"
            break
        fi
    done
    [[ -n "$ovmf_code" ]] || { echo "Error: OVMF UEFI firmware not found." >&2; exit 1; }
    cp "$ovmf_vars" "$work/vars.fd"
    firmware_args=(
        -drive "if=pflash,format=raw,readonly=on,file=$ovmf_code"
        -drive "if=pflash,format=raw,file=$work/vars.fd"
    )
elif [[ "$firmware" != "bios" ]]; then
    echo "Error: firmware must be uefi or bios." >&2
    exit 1
fi

if [[ -w /dev/kvm ]]; then
    accel=(-machine q35,accel=kvm -cpu host)
else
    echo "Warning: /dev/kvm is not available. The test will be very slow."
    accel=(-machine q35)
fi

common=(
    "${accel[@]}"
    "${firmware_args[@]}"
    -m 4096 -smp 4
    -drive "file=$disk,if=virtio,format=qcow2"
    -nic user,model=virtio-net-pci
    -display none
    -no-reboot
)

# --- Phase 1: unattended install.
echo "== Phase 1: installing (up to $install_timeout_min minutes)"
cmdline="archisobasedir=arch archisodevice=/dev/sr0 sona.console accessibility=on console=tty0 console=ttyS0,115200 script=http://10.0.2.2:8000/startup.sh"
set +e
timeout "${install_timeout_min}m" qemu-system-x86_64 "${common[@]}" \
    -cdrom "$iso" \
    -kernel "$kernel" -initrd "$initrd" -append "$cmdline" \
    -serial "file:$install_log"
qemu_rc=$?
set -e

if ! grep -q "SONA-CI: INSTALL OK" "$install_log"; then
    echo "FAIL: the install did not finish (QEMU exit code $qemu_rc). Last 80 lines of the install log:"
    tail -n 80 "$install_log"
    exit 1
fi
echo "Install finished."

# --- Phase 2: boot the installed system.
echo "== Phase 2: booting the installed system (up to $boot_timeout_sec seconds)"
qemu-system-x86_64 "${common[@]}" -serial "file:$boot_log" &
qemu_pid=$!

got_login=no
got_lightdm=no
for _ in $(seq 1 $((boot_timeout_sec / 5))); do
    grep -q "login:" "$boot_log" && got_login=yes
    grep -q "Started .*Light Display Manager" "$boot_log" && got_lightdm=yes
    [[ "$got_login" == yes && "$got_lightdm" == yes ]] && break
    kill -0 "$qemu_pid" 2>/dev/null || break
    sleep 5
done
kill "$qemu_pid" 2>/dev/null || true
wait "$qemu_pid" 2>/dev/null || true
qemu_pid=""

echo "Reached a login prompt: $got_login"
echo "Started the desktop (LightDM): $got_lightdm"
if grep -q "Failed to start" "$boot_log"; then
    echo "Services that failed to start:"
    grep "Failed to start" "$boot_log" | sort -u
fi

if [[ "$got_login" != yes || "$got_lightdm" != yes ]]; then
    echo "FAIL: the installed system did not boot fully. Last 80 lines of the boot log:"
    tail -n 80 "$boot_log"
    exit 1
fi

echo "PASS: Sona installed and booted ($firmware)."
