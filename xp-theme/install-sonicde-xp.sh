#!/usr/bin/env bash
# Windows XP sounds, AutoPlay and keyboard shortcuts for SonicDE.
# Run install-xp-theme.sh first (it installs the sounds and scripts);
# it runs this one for you when SonicDE is installed. Safe to run again.
set -euo pipefail

kitDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
xp="$HOME/.local/share/sounds/windows-xp"
scripts="$HOME/.local/share/xp-theme"
say() { printf '\n== %s\n' "$*"; }

command -v kwriteconfig6 > /dev/null || { echo "SonicDE isn't installed; skipping."; exit 0; }
[[ -f "$xp/Windows XP Startup.wav" ]] || { echo "XP sounds are missing; run install-xp-theme.sh first."; exit 1; }
[[ -f "$scripts/xp_sonicde.py" ]] || { echo "XP scripts are missing; run install-xp-theme.sh first."; exit 1; }

say "Making the Windows XP sound theme"
theme="$HOME/.local/share/sounds/WindowsXP"
mkdir -p "$theme/stereo"
cat > "$theme/index.theme" << 'EOF'
[Sound Theme]
Name=Windows XP
Comment=Windows XP sounds for SonicDE
Directories=stereo

[stereo]
OutputProfile=stereo
EOF
while IFS='|' read -r event file; do
    ln -sfn "$xp/$file" "$theme/stereo/$event.wav"
done << 'EOF'
desktop-login|Windows XP Startup.wav
desktop-logout|Windows XP Shutdown.wav
dialog-error|Windows XP Critical Stop.wav
dialog-error-critical|Windows XP Critical Stop.wav
dialog-error-serious|Windows XP Critical Stop.wav
dialog-warning|Windows XP Exclamation.wav
dialog-warning-auth|Windows XP Exclamation.wav
dialog-information|Windows XP Ding.wav
dialog-question|Windows XP Exclamation.wav
bell|Windows XP Ding.wav
bell-window-system|Windows XP Ding.wav
device-added|Windows XP Hardware Insert.wav
device-removed|Windows XP Hardware Remove.wav
device-added-media|Windows XP Hardware Insert.wav
device-removed-media|Windows XP Hardware Remove.wav
power-plug|Windows XP Hardware Insert.wav
power-unplug|Windows XP Hardware Remove.wav
battery-caution|Windows XP Battery Low.wav
battery-low|Windows XP Battery Critical.wav
battery-full|Windows XP Notify.wav
trash-empty|Windows XP Recycle.wav
message-new-instant|Windows XP Balloon.wav
message|Windows XP Balloon.wav
complete|Windows XP Print complete.wav
completion-fail|Windows XP Ding.wav
EOF
kwriteconfig6 --file kdeglobals --group Sounds --key Theme WindowsXP
kwriteconfig6 --file kdeglobals --group Sounds --key Enable true
# The shutdown sound comes from xp-shutdown-sound.service (plays on any
# shutdown/reboot, even systemctl reboot), so SonicDE's own logout sound is off
# to avoid hearing it twice.
kwriteconfig6 --file plasma_workspace.notifyrc --group Event/exitkde --key Action ""
kwriteconfig6 --file plasma_workspace.notifyrc --group Event/exitkde --key Sound desktop-logout

say "Installing the shutdown sound service"
mkdir -p "$HOME/.config/systemd/user"
cp "$kitDir/payload/sonicde/xp-shutdown-sound.service" "$HOME/.config/systemd/user/"
systemctl --user daemon-reload
systemctl --user enable --now xp-shutdown-sound.service

say "Hooking the XP logoff sound into ~/.bash_profile"
if ! grep -q 'xp_logoff.sh' "$HOME/.bash_profile" 2>/dev/null; then
  if grep -q '^  startx ' "$HOME/.bash_profile" 2>/dev/null; then
    sed -i '/^  startx /a\  # Windows XP logoff sound (skipped on shutdown/reboot)\n  [ -x ~/.local/share/xp-theme/xp_logoff.sh ] \&\& ~/.local/share/xp-theme/xp_logoff.sh' "$HOME/.bash_profile"
  else
    echo "  No startx line in ~/.bash_profile; add a call to ~/.local/share/xp-theme/xp_logoff.sh after startx yourself."
  fi
fi

say "Installing the window sounds script"
mkdir -p "$HOME/.local/share/kwin/scripts" "$HOME/.local/share/kwin-x11/scripts"
rm -rf "$HOME/.local/share/kwin/scripts/xpsounds"
cp -r "$kitDir/payload/sonicde/xpsounds" "$HOME/.local/share/kwin/scripts/xpsounds"
ln -sfn "$HOME/.local/share/kwin/scripts/xpsounds" "$HOME/.local/share/kwin-x11/scripts/xpsounds"
kwriteconfig6 --file kwinrc --group Plugins --key xpsoundsEnabled true
kwriteconfig6 --file kwinrc --group Plugins --key minimizeallEnabled true

say "Setting XP keyboard shortcuts"
k() { kwriteconfig6 --file kglobalshortcutsrc "$@"; }
tab=$'\t'
k --group kwin --key "Window Operations Menu" "Alt+Space${tab}Alt+F3,Alt+F3,Window Menu"
k --group services --group org.kde.krunner.desktop --key _launch "Meta+R${tab}Alt+F2${tab}Search"
k --group kwin --key MinimizeAll "Meta+M,Meta+Shift+D,MinimizeAll"
k --group plasmashell --key "activate application launcher" "Meta${tab}Alt+F1${tab}Ctrl+Esc,Meta${tab}Alt+F1,Activate Application Launcher"
k --group services --group org.kde.plasma-systemmonitor.desktop --key _launch "Ctrl+Shift+Esc${tab}Ctrl+Alt+Del"
k --group ksmserver --key "Log Out" "none,Ctrl+Alt+Del,Show Logout Screen"
k --group services --group org.kde.kinfocenter.desktop --key _launch "Meta+Pause"
k --group services --group xp-safely-remove.desktop --key _launch "Meta+Alt+E"
k --group services --group xp-autoplay-again.desktop --key _launch "Meta+Alt+A"
# Terminator is the terminal: Ctrl+Alt+T opens it (taken from Konsole)
k --group services --group org.kde.konsole.desktop --key _launch "none"
k --group services --group terminator.desktop --key _launch "Ctrl+Alt+T"
kwriteconfig6 --file kdeglobals --group General --key TerminalApplication terminator
kwriteconfig6 --file kdeglobals --group General --key TerminalService terminator.desktop

say "Adding menu items and startup entries"
mkdir -p "$HOME/.local/share/applications" "$HOME/.config/autostart"
cat > "$HOME/.local/share/applications/xp-safely-remove.desktop" << EOF
[Desktop Entry]
Type=Application
Name=Safely Remove Hardware
Comment=Choose a USB drive or memory card to stop and eject
Exec=$scripts/xp_autoplay.py --safely-remove
Icon=drive-removable-media
Categories=System;
EOF
cat > "$HOME/.local/share/applications/xp-autoplay-again.desktop" << EOF
[Desktop Entry]
Type=Application
Name=AutoPlay
Comment=Show the AutoPlay window again for a plugged-in drive
Exec=$scripts/xp_autoplay.py --autoplay
Icon=media-removable
Categories=System;
EOF
cat > "$HOME/.config/autostart/xp-sonicde.desktop" << EOF
[Desktop Entry]
Type=Application
Name=Windows XP sounds
Exec=$scripts/xp_sonicde.py
OnlyShowIn=KDE;
X-KDE-autostart-phase=2
EOF
cat > "$HOME/.config/autostart/xp-autoplay-sonicde.desktop" << EOF
[Desktop Entry]
Type=Application
Name=Windows XP AutoPlay
Exec=$scripts/xp_autoplay.py
OnlyShowIn=KDE;
X-KDE-autostart-phase=2
EOF

say "Done. Log out and back in to SonicDE to hear it."
