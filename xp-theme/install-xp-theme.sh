#!/usr/bin/env bash
# install-xp-theme.sh: rebuild the Windows XP theme on SonicDE.
#
# What it does, in order:
#   1. Installs the packages the XP scripts need (pacman, with sudo).
#   2. Downloads the Windows XP sound pack from archive.org, checks its
#      checksum, and unpacks only the .wav files to ~/.local/share/sounds/windows-xp.
#   3. Copies the XP scripts from payload/scripts into ~/.local/share/xp-theme.
#   4. Runs install-sonicde-xp.sh (sound theme, window sounds, keys, startup).
#
# Safe to run again any time.
# Every script it replaces is backed up first to ~/.local/share/xp-theme/backups/<date-time>/.
#
# Options:
#   --no-packages   skip installing packages
#   --no-download   skip downloading the sounds
#   --help          show this help

set -euo pipefail

kitDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
scriptDir="${HOME}/.local/share/xp-theme"
soundDir="${HOME}/.local/share/sounds/windows-xp"
backupDir="${scriptDir}/backups/$(date +%Y%m%d-%H%M%S)"

archiveId="windows-xp-system-sounds-16-bit-44100-hz"
zipName="Windows XP System Sounds 16 Bit 44100 Hz.zip"
zipMd5="1bfb0fc6551e13d58051f0343b7eb317"

packages=(
    sox python-dbus python-gobject gtk3 libgudev libnotify
    udisks2 gvfs gvfs-mtp gvfs-gphoto2 curl unzip
)

doPackages=1
doDownload=1
for arg in "$@"; do
    case "$arg" in
        --no-packages) doPackages=0 ;;
        --no-download) doDownload=0 ;;
        -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $arg (try --help)" >&2; exit 2 ;;
    esac
done

say() { printf '\n== %s\n' "$*"; }
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

# Copy a file into the backup folder once per run
backup() {
    local file="$1"
    [[ -e "$file" ]] || return 0
    local rel="${file#"${scriptDir}"/}"
    [[ -e "${backupDir}/${rel}" ]] && return 0
    mkdir -p "$(dirname "${backupDir}/${rel}")"
    cp -p "$file" "${backupDir}/${rel}"
}

[[ $EUID -ne 0 ]] || die "Run this as your normal user, not root. It uses sudo only for packages."
[[ -d "${kitDir}/payload/scripts" ]] || die "payload/scripts is missing next to this script."
command -v startplasma-x11 > /dev/null || die "SonicDE is not installed."

# ---------------------------------------------------------------- 1. packages
if (( doPackages )); then
    say "Installing packages"
    command -v pacman > /dev/null || die "pacman not found. This script is for Arch Linux. Use --no-packages to skip."
    sudo pacman -S --needed --noconfirm "${packages[@]}"
fi

# ---------------------------------------------------------------- 2. sounds
if (( doDownload )); then
    say "Windows XP sounds"
    have=0
    [[ -d "$soundDir" ]] && have=$(find "$soundDir" -maxdepth 1 -iname '*.wav' | wc -l)
    if (( have >= 34 )) && [[ -f "${soundDir}/Windows XP Startup.wav" ]]; then
        echo "Already installed (${have} sounds in ${soundDir})."
    else
        tmp="$(mktemp -d)"
        trap 'rm -rf "$tmp"' EXIT
        zip="${tmp}/sounds.zip"
        url="https://archive.org/download/${archiveId}/${zipName// /%20}"
        echo "Downloading ${url}"
        curl -fsSL --retry 3 -m 300 -A 'Mozilla/5.0' -o "$zip" "$url"
        got="$(md5sum "$zip" | cut -d' ' -f1)"
        [[ "$got" == "$zipMd5" ]] || die "Checksum mismatch (expected ${zipMd5}, got ${got}). Not installing."
        echo "Checksum OK."
        mkdir -p "$soundDir"
        # -j drops folders, -n never overwrites; only .wav files come out
        unzip -qjn "$zip" '*.wav' '*.WAV' -d "$soundDir" 2> /dev/null || unzip -qjn "$zip" '*.wav' -d "$soundDir"
        echo "Installed $(find "$soundDir" -maxdepth 1 -iname '*.wav' | wc -l) sounds to ${soundDir}."
    fi
fi

# ---------------------------------------------------------------- 3. scripts
say "Installing XP scripts"
mkdir -p "$scriptDir"
for src in "${kitDir}"/payload/scripts/*; do
    name="$(basename "$src")"
    dest="${scriptDir}/${name}"
    new="$(sed "s#@HOME@#${HOME}#g" "$src")"
    if [[ -f "$dest" ]] && [[ "$(cat "$dest")" == "$new" ]]; then
        echo "  ${name}: already up to date"
        continue
    fi
    backup "$dest"
    printf '%s\n' "$new" > "$dest"
    [[ "$name" == xp_common.py ]] && chmod 644 "$dest" || chmod 755 "$dest"
    echo "  ${name}: installed"
done

if [[ -d "$backupDir" ]]; then
    echo
    echo "Backups of replaced scripts: ${backupDir}"
fi
bash "${kitDir}/install-sonicde-xp.sh"
say "Done. The XP theme is installed."
