Windows XP theme for Sona Linux (SonicDE)

The installer asks "Make the desktop sound like Windows XP?". If you say yes,
this kit is copied to /usr/share/sona/xp-theme and runs once, by itself, the
first time you log in (sona-session-init). You can also run it yourself at any
time:

    /usr/share/sona/xp-theme/install-xp-theme.sh

It downloads the Windows XP sound pack from archive.org (the checksum is
checked; no Microsoft sounds are stored in this repository), copies the XP
scripts to ~/.local/share/xp-theme, and runs install-sonicde-xp.sh. That sets
up the WindowsXP sound theme, the xpsounds window-sounds script, XP keyboard
shortcuts, Safely Remove Hardware and AutoPlay, and the startup, logon,
logoff, and shutdown sounds.

Options: --no-packages, --no-download, --help

payload/scripts holds the XP helper scripts. @HOME@ is replaced with your
home folder when installing. payload/sonicde holds the window-sounds script
and the shutdown sound service.
