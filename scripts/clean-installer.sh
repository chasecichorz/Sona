#!/usr/bin/env bash
set -euo pipefail

INSTALLER="sona-live/airootfs/root/sona_installer_best.sh"
CLEANED_INSTALLER="sona-live/airootfs/root/sona_installer_cleaned.sh"
LOG_FILE="sona-live/installer-cleanup.log"

if [[ ! -f "$INSTALLER" ]]; then
  echo "❌ Installer script not found at $INSTALLER"
  exit 1
fi

echo "🔧 Cleaning installer script..."
cp "$INSTALLER" "$CLEANED_INSTALLER"
echo "# Lines commented out with replacement suggestions" > "$LOG_FILE"

# List of replacements
declare -A replacements=(
  [waydroid]="# Removed: 'waydroid' not in official repos. Consider using Anbox or manual install."
  [aosp-uiautomator]="# Removed: 'aosp-uiautomator' not in official repos."
  [wine]="# Removed: 'wine'. Consider using 'wine-staging'."
  [flatpak]="# Removed: 'flatpak'. Suggest installing later via script or post-setup."
)

for pkg in "${!replacements[@]}"; do
  sed -i "s/install_pkg.*\b$pkg\b.*/${replacements[$pkg]}/g" "$CLEANED_INSTALLER"
  echo "$pkg - ${replacements[$pkg]}" >> "$LOG_FILE"
done

mv "$CLEANED_INSTALLER" "$INSTALLER"
chmod +x "$INSTALLER"

echo "✅ Installer cleaned: $INSTALLER"
echo "📄 See $LOG_FILE for details on modifications."
