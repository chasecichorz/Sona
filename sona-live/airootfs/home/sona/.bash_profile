#
# ~/.bash_profile (Sona live system)
#

[[ -f ~/.bashrc ]] && . ~/.bashrc

# Start the SonicDE desktop after the automatic login on tty1, the same way
# an installed Sona system does. Exiting the desktop leaves a shell here.
if [ -z "$DISPLAY" ] && [ "$XDG_VTNR" = 1 ]; then
  startx -- -keeptty >~/.xorg-startx.log 2>&1
fi
