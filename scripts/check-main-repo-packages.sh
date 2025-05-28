#!/usr/bin/env bash
set -euo pipefail

PKG_LIST="sona-live/packages.x86_64"
echo "🔍 Checking all packages in: $PKG_LIST"
echo

while read -r pkg; do
  [[ "$pkg" =~ ^#.*$ || -z "$pkg" ]] && continue
  if pacman -Si "$pkg" &>/dev/null; then
    echo "✅ $pkg"
  else
    echo "❌ $pkg NOT found in official repos"
  fi
done < "$PKG_LIST"
