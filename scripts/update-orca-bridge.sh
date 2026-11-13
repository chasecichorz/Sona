#!/usr/bin/env bash
# Rebuild orca-bridge/remote.orca-ext from an Orca Bridge checkout.
# Usage: scripts/update-orca-bridge.sh /path/to/orca-bridge
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src="${1:?usage: $0 /path/to/orca-bridge}"
"$src/build-orca-ext.sh" "$src" "$repo_dir/orca-bridge/remote.orca-ext"
cp "$src/LICENSE" "$repo_dir/orca-bridge/LICENSE"
commit="$(git -C "$src" rev-parse HEAD 2>/dev/null || echo unknown)"
version="$(awk -F '"' '/^version *=/ {print $2; exit}' "$src/manifest.toml")"
sed -i "s/^    version .*, commit .*/    version $version, commit $commit/" "$repo_dir/orca-bridge/README.txt"
echo "Updated orca-bridge/remote.orca-ext to version $version ($commit)."
