#!/usr/bin/env bash
# Install Sona in a virtual machine by answering the installer's plain-text
# questions over the serial port, the way a person types them, then check
# the installed disk. This covers what the unattended test cannot: the
# questions themselves, a wrong answer to a menu, the summary and typed YES,
# the separate /home layout, a second user, choosing who logs in
# automatically, and turning on SSH.
#
# Usage: scripts/interactive-install-test.sh path/to/sona.iso
# Needs: qemu, edk2-ovmf, bsdtar, python3, qemu-nbd (uses sudo for the
# disk checks at the end). Logs go to out/interactive-test.log.

set -euo pipefail

iso="${1:?usage: $0 path/to/sona.iso}"
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$repo_dir/out"
work="$(mktemp -d -p "$repo_dir/out" interactive-test.XXXXXX)"
log="$repo_dir/out/interactive-test.log"
: > "$log"
qemu_pid=""
nbd=""
cleanup() {
    [[ -n "$qemu_pid" ]] && kill "$qemu_pid" 2>/dev/null || true
    for m in "$work/mnt/boot/efi" "$work/mnt/home" "$work/mnt"; do
        mountpoint -q "$m" 2>/dev/null && sudo umount "$m"
    done
    [[ -n "$nbd" ]] && sudo qemu-nbd --disconnect "$nbd" >/dev/null 2>&1 || true
    rm -rf "$work"
}
trap cleanup EXIT

ovmf_code=/usr/share/edk2/x64/OVMF_CODE.4m.fd
cp /usr/share/edk2/x64/OVMF_VARS.4m.fd "$work/vars.fd"
qemu-img create -q -f qcow2 "$work/disk.qcow2" 40G
bsdtar -xf "$iso" -C "$work" arch/boot/x86_64/vmlinuz-linux arch/boot/x86_64/initramfs-linux.img

accel=(-machine q35)
[[ -w /dev/kvm ]] && accel=(-machine q35,accel=kvm -cpu host)
qemu-system-x86_64 "${accel[@]}" -m 4096 -smp 4 \
    -drive "if=pflash,format=raw,readonly=on,file=$ovmf_code" \
    -drive "if=pflash,format=raw,file=$work/vars.fd" \
    -drive "file=$work/disk.qcow2,if=virtio,format=qcow2" \
    -cdrom "$iso" \
    -kernel "$work/arch/boot/x86_64/vmlinuz-linux" -initrd "$work/arch/boot/x86_64/initramfs-linux.img" \
    -append "archisobasedir=arch archisodevice=/dev/sr0 sona.console accessibility=on systemd.unit=multi-user.target console=tty0 console=ttyS0,115200" \
    -nic user,model=virtio-net-pci -display none -no-reboot \
    -serial "unix:$work/serial.sock,server=on,wait=off" &
qemu_pid=$!

cat > "$work/steps" << 'STEPS'
expect 400 login:
send root
expect 30 root@
send stty cols 250; export TERM=dumb
send sona-install
expect 120 Press Enter to continue
send
expect 900 Enter your full name
send Test User
expect 30 Enter a lowercase username \(no spaces\)
send tester
expect 30 Enter a name for this computer
send
expect 30 Enter a password for tester
send tester-pass
expect 30 Confirm your password
send tester-pass
expect 30 Use the same password for the root
send
expect 30 Add another user account
send yes
expect 30 Enter the full name for the new user
send Sona Helper
expect 30 Enter a lowercase username for Sona Helper
send helper
expect 30 Enter a password for helper
send helper-pass
expect 30 Confirm the password for helper
send helper-pass
expect 30 Should helper be an administrator
send
expect 30 Add another user account
send no
expect 30 Which user should log into the desktop automatically
expect 10 3\. helper
send 3
expect 30 Make the desktop sound like Windows XP
send
expect 30 Install Linux Game Manager
send
expect 30 Install Audiogame Manager
send
expect 30 Install Steam
send
expect 30 Turn on SSH
send yes
expect 30 Select your time zone
# A number that is not on the list must be refused.
send 9
expect 30 Please type one of the numbers listed
send 6
expect 30 Confirm the system locale
send
expect 30 Confirm the console keyboard layout
send
expect 30 Confirm the desktop keyboard layout
send
expect 30 How should Sona use the disks
send 2
expect 30 Choose the drive to install Sona Linux onto
send 1
expect 30 How many GB should the system partition get
send
expect 30 Sona Linux will be installed like this
expect 30 User: Sona Helper \(helper\), regular user
expect 30 Automatic login: helper
expect 30 ERASE ALL OF /dev/vda
expect 30 Type YES in capital letters
send YES
expect 60 Step 2 of 5: Preparing the disk
expect 900 Step 3 of 5: Copying Sona to the disk
expect 900 Step 4 of 5: Setting up the new system
expect 3600 Sona Linux has been installed
expect 60 Press Enter to continue
send
sleep 20
STEPS

echo "== Interactive install test: booting $(basename "$iso")"
set +e
python3 "$repo_dir/scripts/vm-serial.py" "$work/serial.sock" "$work/steps" "$log"
driver_rc=$?
set -e
wait "$qemu_pid" 2>/dev/null || true
qemu_pid=""
if [[ $driver_rc -ne 0 ]]; then
    echo "FAIL: the installer did not go as expected. Last lines of $log:"
    tr -d '\r' < "$log" | sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' | tail -n 40
    exit 1
fi
echo "The installer finished. Checking the installed disk."

# --- Look inside the installed disk.
sudo modprobe nbd max_part=8
for dev in /dev/nbd*; do
    [[ "$dev" =~ ^/dev/nbd[0-9]+$ ]] || continue
    if [[ "$(cat "/sys/block/${dev#/dev/}/size" 2>/dev/null)" == 0 ]]; then
        nbd="$dev"
        break
    fi
done
[[ -n "$nbd" ]] || { echo "FAIL: no free nbd device"; exit 1; }
sudo qemu-nbd --read-only --connect="$nbd" "$work/disk.qcow2"
sleep 2
sudo partprobe "$nbd" 2>/dev/null || true
mkdir -p "$work/mnt"
sudo mount -o ro "${nbd}p3" "$work/mnt"
sudo mount -o ro "${nbd}p4" "$work/mnt/home"
sudo mount -o ro "${nbd}p2" "$work/mnt/boot/efi"
r="$work/mnt"

pass=0
fail=0
check() {
    local what="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "PASS  $what"
        pass=$((pass + 1))
    else
        echo "FAIL  $what"
        fail=$((fail + 1))
    fi
}
has() { sudo grep -q -- "$2" "$r$1"; }

check "partition 3 is the system (SonaRoot)" bash -c "[[ \$(sudo blkid -s LABEL -o value ${nbd}p3) == SonaRoot ]]"
check "partition 4 is /home (SonaHome)" bash -c "[[ \$(sudo blkid -s LABEL -o value ${nbd}p4) == SonaHome ]]"
check "/home is mounted from its own partition at boot" sudo awk '
    $1 !~ /^#/ && $2 == "/home" && $3 == "ext4" { found = 1 }
    END { exit !found }
' "$r/etc/fstab"
check "the system partition got the suggested size" bash -c "(( \$(sudo blockdev --getsize64 ${nbd}p3) / 1000000000 < 25 ))"
check "boot loader is on the EFI partition" sudo test -f "$r/boot/efi/EFI/Sona/grubx64.efi"
check "tester exists and is an administrator" bash -c "sudo grep -q '^tester:' '$r/etc/passwd' && sudo grep -q '^wheel:.*tester' '$r/etc/group'"
check "helper exists and is not an administrator" bash -c "sudo grep -q '^helper:' '$r/etc/passwd' && ! sudo grep -q '^wheel:.*helper' '$r/etc/group'"
check "both users have passwords" bash -c "sudo grep -q '^tester:\\\$' '$r/etc/shadow' && sudo grep -q '^helper:\\\$' '$r/etc/shadow'"
check "helper logs in automatically" has /etc/systemd/system/getty@tty1.service.d/10-sona-autologin.conf '--autologin helper '
check "SSH is turned on" sudo test -L "$r/etc/systemd/system/multi-user.target.wants/sshd.service"
check "homes are on the /home partition" sudo test -f "$r/home/tester/.bash_profile" -a -f "$r/home/helper/.bash_profile"
check "helper has Orca Bridge" sudo test -f "$r/home/helper/.local/share/orca/extensions/remote/manifest.toml"
check "XP theme is on (the default)" sudo test -f "$r/etc/sona/xp-theme"
check "the live user is gone" bash -c "! sudo grep -q '^sona:' '$r/etc/passwd'"
check "the install log was kept" sudo test -s "$r/var/log/sona-install.log"
check "the install log shows the copy method" has /var/log/sona-install.log 'method: copy'

echo
echo "$pass passed, $fail failed. Serial log: $log"
[[ $fail -eq 0 ]]
