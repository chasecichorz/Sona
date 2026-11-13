Orca Bridge for Sona Linux

Orca Bridge lets Orca control, and be controlled by, NVDA Remote-compatible
computers (speech, braille, keyboard, and clipboard) over the NVDA Remote v2
protocol. It is maintained by Chase and is a fork of Orca Remote by
SerrebiDev; both are licensed under the GNU LGPL 2.1 or later (see LICENSE).
The archive holds the Python source.

remote.orca-ext here was built from:
    https://github.com/chasecichorz/orca-bridge
    version 1.0.0, commit fc0879e4aea60ee24862c8dd1682e32430fd7bed

(Inside Orca the extension's folder is still named "remote".)

Sona installs it for every user, already approved, so it loads with Orca
from the first login:
    /usr/share/sona/orca-bridge/remote.orca-ext   the archive
    /usr/local/bin/sona-orca-extensions            installs and approves
                                                   Sona's Orca extensions
To set it up again for yourself:  sona-orca-extensions && orca --replace

To update the copy in this repository from an Orca Bridge checkout:
    scripts/update-orca-bridge.sh /path/to/orca-bridge
