#!/usr/bin/env bash
# Build the Sona Linux live ISO with archiso.
#
# Usage (on an Arch Linux system, from anywhere):
#   sudo scripts/build-iso.sh
#
# The ISO is written to out/ at the top of the repository.

set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
profile_dir="$repo_dir/sona-live"
work_dir="$repo_dir/work"
out_dir="$repo_dir/out"

if [[ $EUID -ne 0 ]]; then
    echo "Error: run this script as root, for example: sudo $0" >&2
    exit 1
fi

if ! command -v mkarchiso >/dev/null 2>&1; then
    echo "Error: mkarchiso is missing. Install it with: pacman -S archiso" >&2
    exit 1
fi

# The installer lives at the top of the repo as "Install"; the live ISO
# runs it as sona-install. It is copied in at build time so there is only
# ever one copy to edit.
install -Dm755 "$repo_dir/Install" "$profile_dir/airootfs/usr/local/bin/sona-install"

rm -rf "$work_dir"
mkdir -p "$out_dir"

echo "Building the Sona Linux ISO. This can take a while..."
mkarchiso -v -w "$work_dir" -o "$out_dir" "$profile_dir"

rm -rf "$work_dir"

if [[ -n "${SUDO_USER:-}" ]]; then
    chown -R "$SUDO_USER:" "$out_dir"
fi

echo
echo "Done. The ISO is in $out_dir:"
ls -1 "$out_dir"/*.iso
