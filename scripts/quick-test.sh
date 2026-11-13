#!/usr/bin/env bash
# Quick test of the installer's system setup, in minutes instead of an hour.
#
# Runs the part of Install that sets up the system (setup-chroot.sh, pulled
# out of Install) in a throwaway container on this computer, then checks the
# result. Disk partitioning and the GRUB boot loader are not tested here;
# use scripts/ci-install-test.sh in a virtual machine for those.
#
# How it stays fast:
#   - The base system (the installer's pacstrap step) is built once and kept
#     in out/quick/base. --fresh rebuilds it, for example after changing the
#     pacstrap package list in Install.
#   - Every run starts from a clean copy of that base: an overlay with a new,
#     empty top layer. The base is never changed.
#   - This computer's pacman package cache is shared, so each package is
#     downloaded at most once.
#
# Usage:
#   sudo scripts/quick-test.sh            test with the default answers
#   sudo scripts/quick-test.sh --fresh    rebuild the base first
#   sudo scripts/quick-test.sh --copy     test the "copy the live system"
#                                         install, using the newest ISO in out/
#   sudo scripts/quick-test.sh --copy --offline
#                                         the same with no internet at all
#   sudo scripts/quick-test.sh --shell    open a shell in the result afterwards
#   sudo scripts/quick-test.sh --keep     leave the result mounted afterwards
#
# The result is kept in out/quick/run (the changes on top of the base) until
# the next run; with --keep it also stays mounted at out/quick/run/root.
# Needs: arch-install-scripts (pacstrap, arch-chroot), on an Arch computer.

set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
quick="$repo_dir/out/quick"
base="$quick/base"
run="$quick/run"
root="$run/root"
cache=/var/cache/pacman/pkg
user=tester

fresh=no
shell=no
keep=no
method=download
online=y
for arg in "$@"; do
    case "$arg" in
        --fresh) fresh=yes ;;
        --shell) shell=yes ;;
        --keep) keep=yes ;;
        --copy) method=copy ;;
        --offline) online=n ;;
        -h|--help) sed -n '2,29p' "$0"; exit 0 ;;
        *) echo "Unknown option: $arg (see --help)" >&2; exit 1 ;;
    esac
done

[[ $EUID -eq 0 ]] || { echo "Error: run as root, for example: sudo $0" >&2; exit 1; }
[[ "$online" == y || "$method" == copy ]] || { echo "Error: --offline only works with --copy." >&2; exit 1; }
command -v pacstrap >/dev/null || { echo "Error: install arch-install-scripts first." >&2; exit 1; }

cleanup() {
    for m in "$root/var/cache/pacman/pkg" "$root"; do
        mountpoint -q "$m" && umount -R "$m"
    done
    return 0
}
cleanup
trap '[[ "$keep" == yes ]] || cleanup' EXIT

start=$(date +%s)

# The package lists, from Install's SONA PACKAGES block.
eval "$(sed -n '/^# BEGIN SONA PACKAGES$/,/^# END SONA PACKAGES$/p' "$repo_dir/Install")"

# --- 1b. For --copy: the live system image from the newest ISO, unpacked
# once per ISO. This is what the installer copies to the disk.
if [[ "$method" == copy ]]; then
    iso=$(ls -1t "$repo_dir"/out/*.iso 2>/dev/null | head -n 1 || true)
    [[ -n "$iso" ]] || { echo "Error: no ISO in out/. Build one with: sudo scripts/build-iso.sh" >&2; exit 1; }
    base="$quick/copy-base"
    stamp="$(basename "$iso") $(stat -c %Y "$iso")"
    if [[ "$fresh" == yes || "$(cat "$base/.sona-iso" 2>/dev/null)" != "$stamp" ]]; then
        echo "== Unpacking the live system from $(basename "$iso") (once per ISO)"
        rm -rf "$base" "$quick/copy-tmp"
        mkdir -p "$quick/copy-tmp"
        bsdtar -xf "$iso" -C "$quick/copy-tmp" arch/x86_64/airootfs.sfs
        unsquashfs -no-progress -d "$base" "$quick/copy-tmp/arch/x86_64/airootfs.sfs" >/dev/null
        rm -rf "$quick/copy-tmp"
        echo "$stamp" > "$base/.sona-iso"
    fi
    touch "$base/.sona-base-done"
    fresh=no
fi

# --- 1. The base system, built once.
if [[ "$fresh" == yes ]]; then
    rm -rf "$base"
fi
if [[ ! -f "$base/.sona-base-done" ]]; then
    echo "== Building the base system (only needed once)"
    rm -rf "$base"
    mkdir -p "$base"
    # The same packages as the pacstrap step in Install.
    pkgs=("${SONA_BASE_PKGS[@]}")
    [[ ${#pkgs[@]} -gt 20 ]] || { echo "Error: could not read the package list from Install." >&2; exit 1; }
    # A plain Arch package setup, like the Arch ISO the installer starts
    # from, so this computer's extra repositories never leak into the test.
    cat > "$quick/pacman.conf" <<'PACCONF'
[options]
HoldPkg = pacman glibc
Architecture = auto
ParallelDownloads = 5
SigLevel = Required DatabaseOptional
LocalFileSigLevel = Optional

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist
PACCONF
    pacstrap -C "$quick/pacman.conf" -c -K "$base" "${pkgs[@]}"
    touch "$base/.sona-base-done"
fi

# --- 2. A clean copy of the base for this run.
echo "== Preparing a clean copy of the base"
rm -rf "$run"
mkdir -p "$run/upper" "$run/work" "$root"
mount -t overlay overlay -o "lowerdir=$base,upperdir=$run/upper,workdir=$run/work" "$root"
mount --bind "$cache" "$root/var/cache/pacman/pkg"

if [[ "$method" == copy ]]; then
    # What Install does right after unpacking the image onto the disk.
    mkdir -p "$root/boot"
    cp "$root"/usr/share/sona/boot/* "$root/boot/"
    rm -rf "$root/usr/share/sona/boot"
    rm -f "$root/etc/resolv.conf"
    touch "$root/etc/resolv.conf"
    # Test this repository's build script, not the one that made the ISO:
    # the same live-file list and bundled keys scripts/build-iso.sh makes.
    {
        (cd "$repo_dir/sona-live/airootfs" && find . \( -type f -o -type l \) -printf '%P\n')
        echo "usr/local/bin/sona-install"
    } | grep -v -x -E 'etc/(passwd|group|shadow|gshadow|hostname|locale\.conf|localtime|environment|resolv\.conf|pacman\.conf)' \
        | sort -u > "$root/usr/share/sona/live-files.txt"
    if [[ -f "$repo_dir/sona-live/airootfs/etc/pacman.conf" ]]; then
        cp "$repo_dir/sona-live/airootfs/etc/pacman.conf" "$root/etc/pacman.conf"
    fi
    mkdir -p "$quick/keys"
    if [[ ! -s "$quick/keys/stormux_repo.pub" ]]; then
        curl -fsSL --retry 5 --retry-delay 10 -o "$quick/keys/stormux_repo.pub" \
            https://git.stormux.org/storm/stormux/raw/branch/master/x86_64/stormux_repo.pub
    fi
    install -Dm644 "$quick/keys/stormux_repo.pub" "$root/usr/share/sona/keys/stormux_repo.pub"
    # The Kokoro model and Python packages the ISO carries (from the build
    # cache, if a build has made one and the ISO does not have them yet).
    kokoro_cache=$(ls -d "$repo_dir"/out/cache/kokoro-py* 2>/dev/null | head -n 1 || true)
    if [[ -n "$kokoro_cache" && ! -d "$root/opt/kokoro-speechd/models" ]]; then
        mkdir -p "$root/opt/kokoro-speechd"
        cp -r "$kokoro_cache/models" "$kokoro_cache/site-packages" "$root/opt/kokoro-speechd/"
    fi
fi

# The installer's answers, as Install would write them.
cat > "$root/root/install.conf" <<EOF
FULLNAME='Sona Quick Test'
USERNAME=$user
PASSWORD=sona-quick-test
ROOT_PASSWORD=sona-quick-test
HOSTNAME=sona-quick
TIMEZONE=UTC
LANG_LOCALE=en_US.UTF-8
CONSOLE_KEYMAP=us
X11_KEYBOARD=us
DISK=/dev/null
AUTOLOGIN=y
XP_THEME=y
BOOT_MODE=uefi
GRUB_REMOVABLE=no
INSTALL_AUR=n
SERIAL_CONSOLE=n
QUICK_TEST=y
INSTALL_METHOD=$method
ONLINE=$online
SONA_X_PKGS=(${SONA_X_PKGS[*]})
SONA_DESKTOP_PKGS=(${SONA_DESKTOP_PKGS[*]})
SONA_APP_PKGS=(${SONA_APP_PKGS[*]})
SONA_XP_PKGS=(${SONA_XP_PKGS[*]})
SONA_KOKORO_PKGS=(${SONA_KOKORO_PKGS[*]})
SONA_STORMUX_PKGS=(${SONA_STORMUX_PKGS[*]})
SONA_NVIDIA_PKGS=(${SONA_NVIDIA_PKGS[*]})
EOF
chmod 600 "$root/root/install.conf"

sed -n "/^cat << 'EOF' > \/mnt\/root\/setup-chroot.sh$/,/^EOF$/p" "$repo_dir/Install" |
    sed '1d;$d' > "$root/root/setup-chroot.sh"
chmod 755 "$root/root/setup-chroot.sh"

mkdir -p "$root/root/sona-extras"
cp -r "$repo_dir/orca-bridge" "$repo_dir/kokoro" "$repo_dir/xp-theme" "$repo_dir/packages" "$root/root/sona-extras/"

# --- 3. Run the setup, exactly as the installer does.
echo "== Running setup-chroot.sh"
log="$quick/setup.log"
set +e
if [[ "$online" == n ]]; then
    # A new, empty network namespace: truly no internet inside.
    unshare -n arch-chroot "$root" /root/setup-chroot.sh 2>&1 | tee "$log"
else
    arch-chroot "$root" /root/setup-chroot.sh 2>&1 | tee "$log"
fi
setup_rc=${PIPESTATUS[0]}
set -e
rm -f "$root/root/setup-chroot.sh" "$root/root/install.conf"

# --- 4. Check the result.
echo
echo "== Checking the result"
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
in_root() { arch-chroot "$root" "$@"; }
has() { grep -q -- "$2" "$root$1"; }
hasnt() { ! grep -q -- "$2" "$root$1"; }

check "setup-chroot.sh finished without errors" test "$setup_rc" -eq 0
check "SonicDE is installed" in_root pacman -Q sonicde-meta
check "Orca is installed" in_root pacman -Q orca
check "Terminator is installed" in_root pacman -Q terminator
check "XLibre is the X server" in_root pacman -Q xlibre-xserver
check "MATE is not installed" bash -c "! arch-chroot '$root' pacman -Q mate-panel"
check "LightDM is not installed" bash -c "! arch-chroot '$root' pacman -Q lightdm"
check "SonicDE repository is set up" has /etc/pacman.conf '^\[sonicde-stable\]'
check "Stormux repository is set up" has /etc/pacman.conf '^\[stormux\]'
check "Jenux repository is set up" has /etc/pacman.conf '^\[jenux\]'
check "Stormux key is trusted" in_root pacman-key --list-keys 52ADA49000F1FF0456F8AEEFB4CDE1CD56EF8E82
check "XLibre key is trusted" in_root pacman-key --list-keys 0C92313001CFCA27627B9098B97F7C613F359424
check "Firefox is installed (browser without the AUR)" in_root pacman -Q firefox
check "browser icon is Firefox when Chrome is not installed" test -f "$root/home/$user/Desktop/Firefox.desktop"
check "espeakup starts at boot" in_root systemctl is-enabled espeakup.service
check "NetworkManager starts at boot" in_root systemctl is-enabled NetworkManager.service
check "tty1 logs in $user automatically" has /etc/systemd/system/getty@tty1.service.d/10-sona-autologin.conf "--autologin $user"
check "auto-login has the -f fix" has /etc/systemd/system/getty@tty1.service.d/10-sona-autologin.conf "-p -f -- \\\\\\\\u"
check "sudoers rule for espeakup is valid" in_root visudo -c -f /etc/sudoers.d/20-sona-espeakup
check ".bash_profile starts the desktop" has "/home/$user/.bash_profile" '^  startx '
check ".bash_profile hands off Speakup" has "/home/$user/.bash_profile" 'systemctl stop espeakup.service'
check ".xinitrc starts SonicDE" has "/home/$user/.xinitrc" 'exec /usr/bin/startplasma-x11'
check "/etc/skel has the login files too" test -f "$root/etc/skel/.bash_profile" -a -x "$root/etc/skel/.xinitrc"
check "Orca starts with SonicDE" has /etc/xdg/autostart/sona-orca.desktop 'OnlyShowIn=KDE;'
check "first-login helper starts with SonicDE" has /etc/xdg/autostart/sona-session-init.desktop 'sona-session-init'
check "Welcome Center does not pop up" has /etc/xdg/kded6rc 'autoload=false'
check "Sona AI has its shortcut" has /usr/share/applications/sona-ai.desktop 'X-KDE-Shortcuts=Meta+Alt+H'
check "OCR has its shortcut" has /usr/share/applications/sona-ocr.desktop 'X-KDE-Shortcuts=Meta+Alt+O'
check "Restart Orca has its shortcut" has /usr/share/applications/sona-orca-restart.desktop 'X-KDE-Shortcuts=Meta+Alt+S'
check "SonicDE registers Sona's shortcuts" test -L "$root/usr/share/kglobalaccel/sona-ai.desktop" -a -L "$root/usr/share/kglobalaccel/sona-ocr.desktop" -a -L "$root/usr/share/kglobalaccel/sona-orca-restart.desktop"
check "no MATE commands left in menu files" bash -c "! grep -rl 'mate-terminal' '$root/usr/share/applications' '$root/home/$user/Desktop'"
check "desktop icons are in place" test -f "$root/home/$user/Desktop/Word Processor.desktop"
approved() {  # extension folder name
    in_root su - "$user" -c "
        want=\$(python3 -c 'import os; from orca.extension_loader import ExtensionLoader as E; print(E._compute_hash(os.path.expanduser(\"~/.local/share/orca/extensions/$1\")))')
        got=\$(XDG_RUNTIME_DIR=/tmp dconf read /org/gnome/orca/default/extensions/approved-user-extensions)
        [[ \"\$got\" == *\"\$want\"* ]]"
}
check "Orca Bridge is version 1.0.0" has "/home/$user/.local/share/orca/extensions/remote/manifest.toml" 'display-name = "Orca Bridge"'
check "Orca Bridge is installed in /etc/skel" test -f "$root/etc/skel/.local/share/orca/extensions/remote/manifest.toml"
check "Orca Bridge is approved for $user" approved remote
check "first-login helper keeps Orca extensions approved" has /usr/local/bin/sona-session-init 'sona-orca-extensions --refresh'
# Offline, these can only come from the ISO: skip them for an older ISO
# that was built before Kokoro and wine-access were added.
if [[ "$online" == y || -d "$base/usr/share/sona/kokoro" ]]; then
    full=y
else
    full=n
    echo "NOTE  this ISO is older than Kokoro and wine-access; their offline checks are skipped"
fi
if [[ "$full" == y ]]; then
    check "Kokoro Python packages are installed" in_root pacman -Q python-onnxruntime-cpu python-soundfile
    check "wine-access is installed (from Stormux)" in_root pacman -Q wine-access
    check "wine-access Orca extension is linked for $user" test -L "$root/home/$user/.local/share/orca/extensions/wine_access"
    check "wine-access Orca extension is approved for $user" approved wine_access
    check "Kokoro voice model is in place" test -s "$root/opt/kokoro-speechd/models/kokoro-v1.0.onnx" -a -s "$root/opt/kokoro-speechd/models/voices-v1.0.bin"
    check "Kokoro loads in its Python environment" in_root /opt/kokoro-speechd/venv/bin/python -I -c 'import kokoro_onnx, onnxruntime, numpy'
    check "Kokoro is a Speech Dispatcher synthesizer" test -f "$root/etc/speech-dispatcher/modules/kokoro-generic.conf" -a -x "$root/usr/local/bin/kokoro-speak"
fi
# This test computer has no NVIDIA RTX card, so the driver must not stay.
if ! lspci -nn | grep -Ei 'VGA|3D|Display' | grep -i nvidia | grep -Eqi '\b(TU|GA|AD|GB|GH)[0-9]{3}'; then
    check "NVIDIA driver is not left on a computer without an RTX card" bash -c "! arch-chroot '$root' pacman -Q nvidia-utils"
fi
check "$user owns everything in their home" bash -c "[[ -z \$(arch-chroot '$root' find /home/$user ! -user $user -print -quit) ]]"
check "XP theme kit is installed" test -x "$root/usr/share/sona/xp-theme/install-xp-theme.sh"
check "XP theme is switched on" test -f "$root/etc/sona/xp-theme"
check "XP first-run setup is installed" test -x "$root/usr/local/bin/sona-xp-firstrun"
check "first-login helper starts the XP setup" has /usr/local/bin/sona-session-init sona-xp-firstrun
if [[ "$online" == y ]]; then
    check "OpenEVV is built and installed" in_root pacman -Q openevv-git
    check "OpenEVV is the default voice" has /etc/speech-dispatcher/speechd.conf '^DefaultModule openevv'
    check "build user cannot log in" bash -c "grep -q '^sona-build:.*nologin' '$root/etc/passwd'"
else
    check "offline: OpenEVV waits for internet (not installed yet)" bash -c "! arch-chroot '$root' pacman -Q openevv-git"
fi
if [[ "$method" == copy ]]; then
    check "copy: live user sona is gone" bash -c "! grep -q '^sona:' '$root/etc/passwd' '$root/etc/shadow' '$root/etc/group'"
    check "copy: live home folder is gone" test ! -e "$root/home/sona"
    check "copy: live sudo rule is gone" test ! -e "$root/etc/sudoers.d/10-sona-live"
    check "copy: live root auto-login is gone" test ! -e "$root/etc/systemd/system/getty@tty1.service.d/autologin.conf"
    check "copy: live services are gone" bash -c "! ls '$root'/etc/systemd/system/multi-user.target.wants/ | grep -E 'livecd|sona-pick-sound|sona-live|choose-mirror|pacman-init|sshd|cloud|vbox|vmtoolsd|iwd|systemd-networkd'"
    check "copy: live boot hooks are gone" bash -c "! ls '$root'/etc/mkinitcpio.conf.d/archiso.conf && ! arch-chroot '$root' pacman -Q mkinitcpio-archiso"
    check "copy: cloud-init is not installed" bash -c "! arch-chroot '$root' pacman -Q cloud-init"
    check "copy: kernel is in /boot" test -s "$root/boot/vmlinuz-linux"
    check "copy: CPU microcode is in /boot" test -s "$root/boot/amd-ucode.img" -a -s "$root/boot/intel-ucode.img"
    check "copy: a normal boot image was made" test -s "$root/boot/initramfs-linux.img"
    check "copy: boot image has no live ISO hooks" bash -c "! arch-chroot '$root' lsinitcpio /boot/initramfs-linux.img | grep -q archiso"
    check "copy: this install has its own machine ID" bash -c "[[ \$(wc -c < '$root/etc/machine-id') -eq 33 ]]"
    check "copy: root uses bash" bash -c "grep -q '^root:.*:/bin/bash\$' '$root/etc/passwd'"
    check "copy: pacman has its own keyring" in_root pacman-key --list-keys A85BB166B49A4C58C39125073B87898C73F11DF5
    check "copy: live-file list was cleaned up" test ! -e "$root/usr/share/sona/live-files.txt"
    check "copy: screen locking is not switched off" test ! -e "$root/etc/xdg/kscreenlockerrc"
    check "copy: pacman.conf is still there" has /etc/pacman.conf '^\[core\]'
    check "copy: new user can log in (password is set)" bash -c "grep -q '^$user:\\\$' '$root/etc/shadow'"
fi
check "OpenEVV update timer is on" in_root systemctl is-enabled sona-openevv-update.timer
check "install passwords were removed" test ! -e "$root/root/install.conf"

took=$(( $(date +%s) - start ))
echo
echo "$pass passed, $fail failed, in $((took / 60)) min $((took % 60)) s. Setup log: $log"

if [[ "$shell" == yes ]]; then
    echo "Opening a shell in the result. Type exit when done."
    arch-chroot "$root" /bin/bash || true
fi

[[ "$fail" -eq 0 ]]
