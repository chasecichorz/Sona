#!/usr/bin/env bash
# Boot the Sona live desktop in a virtual machine and check it, from a root
# shell on the serial port:
#   - tty1 logged in the live user "sona" by itself and started SonicDE
#     (XLibre, no LightDM), and Orca is running;
#   - Windows+Alt+I opens the installer; the Start menu entry and desktop
#     icon are there; Orca Bridge is approved; Kokoro is set up;
#   - pacman can sync every repository (Stormux and the others are trusted);
#   - with "ram": the system was loaded into RAM and the installer can still
#     find the live image to copy.
#
# Usage: scripts/live-boot-test.sh path/to/sona.iso [usb|ram]
# Logs go to out/live-test-<mode>.log. Needs qemu, bsdtar, python3.

set -euo pipefail

iso="${1:?usage: $0 path/to/sona.iso [usb|ram]}"
mode="${2:-usb}"
[[ "$mode" == usb || "$mode" == ram ]] || { echo "Mode must be usb or ram" >&2; exit 2; }
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$repo_dir/out"
work="$(mktemp -d -p "$repo_dir/out" live-test.XXXXXX)"
log="$repo_dir/out/live-test-$mode.log"
: > "$log"
qemu_pid=""
cleanup() {
    [[ -n "$qemu_pid" ]] && kill "$qemu_pid" 2>/dev/null || true
    rm -rf "$work"
}
trap cleanup EXIT

bsdtar -xf "$iso" -C "$work" arch/boot/x86_64/vmlinuz-linux arch/boot/x86_64/initramfs-linux.img
params="archisobasedir=arch archisodevice=/dev/sr0 sona.nosoundpick sona.nowelcome console=tty0 console=ttyS0,115200"
if [[ "$mode" == ram ]]; then params+=" copytoram=y"; else params+=" copytoram=n"; fi

accel=(-machine q35)
[[ -w /dev/kvm ]] && accel=(-machine q35,accel=kvm -cpu host)
qemu-system-x86_64 "${accel[@]}" -m 8192 -smp 4 \
    -cdrom "$iso" \
    -kernel "$work/arch/boot/x86_64/vmlinuz-linux" -initrd "$work/arch/boot/x86_64/initramfs-linux.img" \
    -append "$params" \
    -audiodev none,id=snd0 -device intel-hda -device hda-duplex,audiodev=snd0 \
    -nic user,model=virtio-net-pci -display none -no-reboot \
    -serial "unix:$work/serial.sock,server=on,wait=off" &
qemu_pid=$!

# The checks, typed into the root shell. Each prints CHECK PASS or CHECK FAIL.
cat > "$work/steps" << 'STEPS'
expect 400 login:
send root
expect 30 root@
send exec bash --noprofile --norc
send stty -echo cols 250; export TERM=dumb PS1='SONA-PROMPT# '
expect 10 (?:^|\n)SONA-PROMPT# 
# Give the desktop and Orca time to start.
send sleep 75; printf '\\nDESKTOP-WAIT-DONE\\n'
expect 120 (?:^|\n)DESKTOP-WAIT-DONE\r?\n
send c() { if eval "$2" >/dev/null 2>&1; then printf '\\nCHECK PASS %s\\n' "$1"; else printf '\\nCHECK FAIL %s\\n' "$1"; fi; }
send U="sudo -u sona env DISPLAY=:0 XAUTHORITY=/home/sona/.Xauthority XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"
send c tty1-logged-in-sona "loginctl list-sessions --no-legend | grep -E 'sona.*tty1'"
send c desktop-running "pgrep -u sona -x plasmashell"
send c orca-running "pgrep -u sona -x orca"
send c xlibre-is-the-x-server "pacman -Q xlibre-xserver"
send c no-lightdm "! pacman -Q lightdm"
send c start-menu-entry "grep -q 'Name=Install Sona Linux' /usr/share/applications/sona-install.desktop"
send c desktop-icon "test -x /home/sona/Desktop/install-sona.desktop"
send c shortcut-definition-installed "test -L /usr/share/kglobalaccel/sona-install.desktop && grep -q '^X-KDE-Shortcuts=Meta+Alt+I$' /usr/share/kglobalaccel/sona-install.desktop"
send c orca-bridge-approved "$U dconf read /org/gnome/orca/default/extensions/approved-user-extensions | grep -q remote"
send c kokoro-set-up "test -x /opt/kokoro-speechd/venv/bin/python && test -f /etc/speech-dispatcher/modules/kokoro-generic.conf"
send $U xdotool key super+alt+i; sleep 10
send c windows-alt-i-opens-installer "pgrep -f /usr/local/bin/sona-install"
send for p in $(pgrep -f /usr/local/bin/sona-install); do kill $p; done
send c pacman-syncs-all-repos "pacman -Sy --noconfirm"
send c stormux-key-trusted "pacman-key --list-keys 52ADA49000F1FF0456F8AEEFB4CDE1CD56EF8E82"
STEPS
if [[ "$mode" == ram ]]; then
    cat >> "$work/steps" << 'STEPS'
send c loaded-into-ram "test -f /run/archiso/copytoram/airootfs.sfs"
send c usb-not-needed "! mountpoint -q /run/archiso/bootmnt"
send c installer-finds-ram-image "grep -q 'LIVE_IMAGE=/run/archiso/copytoram/airootfs.sfs' /usr/local/bin/sona-install"
STEPS
fi
cat >> "$work/steps" << 'STEPS'
send printf '\\nPROBE-DONE\\n'
expect 300 (?:^|\n)PROBE-DONE\r?\n
send poweroff
sleep 5
STEPS

echo "== Live desktop test ($mode): booting $(basename "$iso")"
set +e
python3 "$repo_dir/scripts/vm-serial.py" "$work/serial.sock" "$work/steps" "$log"
driver_rc=$?
set -e

results="$(tr -d '\r' < "$log" | grep -a -o '^CHECK \(PASS\|FAIL\) [a-z0-9-]\+$' | sort -u || true)"
printf '%s\n' "$results"
pass=$(grep -c 'CHECK PASS' <<< "$results" || true)
fail=$(grep -c 'CHECK FAIL' <<< "$results" || true)
echo "$pass passed, $fail failed. Serial log: $log"
expected=13
[[ "$mode" == ram ]] && expected=16
[[ $driver_rc -eq 0 && $fail -eq 0 && $pass -eq $expected ]]
