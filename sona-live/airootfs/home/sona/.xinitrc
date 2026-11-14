#!/bin/sh
# Sona live system: start SonicDE (run by startx from ~/.bash_profile).
if [ -d /etc/X11/xinit/xinitrc.d ]; then
  for f in /etc/X11/xinit/xinitrc.d/?*.sh; do
    [ -r "$f" ] && . "$f"
  done
  unset f
fi
export XDG_CURRENT_DESKTOP=KDE XDG_SESSION_DESKTOP=KDE DESKTOP_SESSION=sonicde
exec /usr/bin/startplasma-x11
