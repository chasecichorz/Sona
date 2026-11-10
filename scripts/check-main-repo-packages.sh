#!/usr/bin/env bash
# Check that every package in the live ISO package list exists in the
# repositories this machine's pacman knows about. Reports problems only;
# it never edits the list.
#
# Usage: scripts/check-main-repo-packages.sh

set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pkg_list="$repo_dir/sona-live/packages.x86_64"
missing=0

while read -r pkg; do
    [[ -z "$pkg" || "$pkg" == \#* ]] && continue
    # Accept package groups such as "mate" as well as single packages.
    if ! pacman -Si "$pkg" >/dev/null 2>&1 && [[ -z "$(pacman -Sgq "$pkg" 2>/dev/null)" ]]; then
        echo "Missing: $pkg"
        missing=$((missing + 1))
    fi
done < "$pkg_list"

if [[ $missing -eq 0 ]]; then
    echo "All packages in sona-live/packages.x86_64 were found."
else
    echo "$missing package(s) were not found. Run pacman -Sy first if your package lists are old."
    exit 1
fi
