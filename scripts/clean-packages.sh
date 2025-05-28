#!/usr/bin/env bash
set -euo pipefail

PKG_LIST="sona-live/packages.x86_64"
CLEANED_LIST="sona-live/packages.cleaned.x86_64"
LOG_FILE="sona-live/invalid-packages.log"

echo "🔍 Validating packages in: $PKG_LIST"
echo "# Cleaned package list for SONA Linux ISO" > "$CLEANED_LIST"
echo "# Invalid packages removed with notes" > "$LOG_FILE"

while read -r pkg; do
  [[ "$pkg" =~ ^#.*$ || -z "$pkg" ]] && continue
  if pacman -Si "$pkg" &>/dev/null; then
    echo "$pkg" >> "$CLEANED_LIST"
    echo "✅ $pkg"
  else
    echo "❌ $pkg not in repos — removed"
    echo "$pkg - not in repo" >> "$LOG_FILE"
  fi
done < "$PKG_LIST"

mv "$CLEANED_LIST" "$PKG_LIST"
echo "🎉 Cleaned package list saved to: $PKG_LIST"
echo "📄 See $LOG_FILE for details on removed packages."
