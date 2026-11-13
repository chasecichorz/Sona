#!/bin/sh
# Play the Windows XP logoff sound after the SonicDE desktop exits.
# Called from ~/.bash_profile when startx returns. If the desktop closed
# because of a shutdown or reboot, stay quiet: xp-shutdown-sound.service
# plays the XP shutdown sound instead.
sleep 1  # give a shutdown/reboot request time to show up as a job
if systemctl list-jobs --no-legend 2>/dev/null |
    grep -qE '(poweroff|reboot|halt|kexec|shutdown)\.target'; then
  exit 0
fi
if [ "$(busctl get-property org.freedesktop.login1 /org/freedesktop/login1 \
      org.freedesktop.login1.Manager PreparingForShutdown 2>/dev/null)" = "b true" ]; then
  exit 0
fi
exec pw-play "$HOME/.local/share/sounds/windows-xp/Windows XP Logoff Sound.wav"
