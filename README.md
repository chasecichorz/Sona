# Sona Linux

Sona Linux is an accessible Arch Linux setup for blind and low-vision users.
It installs the SonicDE desktop (an X11 fork of KDE Plasma) with the Orca
screen reader, console speech with espeakup, XLibre, and a set of accessible
everyday apps. The default voice is OpenEVV (ViaVoice / Eloquence), with the
Kokoro neural voices and espeak-ng also there. Orca Bridge (NVDA Remote
compatible) and wine-access are set up for every user. Windows XP sounds
are on unless you say no.

## What is in this repository

- `Install` - the installer. This is the only installer; edit this file.
- `sona-live/` - the archiso profile for the Sona live ISO. It is based on
  Arch Linux's official releng profile.
- `scripts/build-iso.sh` - builds the ISO into `out/`.
- `scripts/boot-sona-qemu.sh` - boots the ISO in a QEMU virtual machine with
  sound and a blank 40 GB test disk.
- `scripts/check-main-repo-packages.sh` - checks that every package in the
  ISO package list exists.
- `scripts/ci-install-test.sh` - the automated install test.
- `scripts/quick-test.sh` - a quick (about 2 minute) test of the system setup.
- `examples/unattended-answers.conf` - a sample answer file.
- `orca-bridge/` - Orca Bridge (NVDA Remote-compatible remote access for
  Orca; Chase's fork of Orca Remote by SerrebiDev, LGPL), installed and
  approved for every user (see `orca-bridge/README.txt`).
- `kokoro/` - the Kokoro neural voices, an extra Speech Dispatcher
  synthesizer that is on the ISO ready to use (see `kokoro/README.txt`).
- `packages/openevv-git/` - builds OpenEVV (the IBM ViaVoice / Eloquence
  voice, Sona's default) from source on each computer, and keeps it updated.
- `xp-theme/` - the optional Windows XP sound theme for SonicDE (see
  `xp-theme/README.txt`).
- `.github/workflows/build-and-release.yml` - checks the scripts, builds the
  ISO on GitHub, and publishes releases (see below).
- `docs/` - the project web page.

## The live ISO

The boot menu has two main choices:

- Sona Linux live desktop (the default). Logs in automatically to the SonicDE
  desktop with Orca talking. Firefox is included for trying things out. The
  "Install Sona Linux" icon on the desktop starts the installer.
- Sona Linux live console with speech. A text console with espeakup, for
  computers where the desktop does not work. Type `sona-install` to install.

While the live desktop loads, the computer says out loud that Sona is
starting, so the wait is not silent. If the computer has more than one sound
device (for example speakers, a USB headset, and HDMI on a graphics card),
each device in turn asks you to press Enter to use it. The one you choose is
where Orca talks. Add `sona.nosoundpick` to the boot options to skip this. The volume is raised to 70% at login.
The desktop has a network icon for Wi-Fi.

The live desktop uses the standard Arch X server; installed systems use
XLibre. The live user is `sona`, with no password and full sudo access.

## Installing

From the Sona live desktop, press Windows+Alt+I, or open the Start menu,
type "install", and press Enter on "Install Sona Linux". (The live desktop
says this out loud after it loads; there is also an icon on the desktop.)
From a terminal or the live console, type `sudo sona-install`.

From a standard Arch Linux ISO, connect to the internet, then run:

    curl -LO https://raw.githubusercontent.com/chasecichorz/sona/main/Install
    bash Install

The installer asks its questions first and changes nothing on disk until you
confirm. Press Escape on any question to quit.

### No internet needed from the Sona ISO

The Sona ISO holds everything an installed system has. Run from it, the
installer copies the live system to the disk, removes the live-only parts
(the `sona` live user, the live login and boot setup), and creates your own
account. This takes minutes and works with no internet. Without internet
three things wait until the computer is online: system updates, the AUR apps
(Google Chrome, Pamac, Thorium; Firefox is the browser until then), and the
OpenEVV voice (espeak-ng speaks until it is built, which happens by itself).

Run from a standard Arch ISO, the installer downloads everything instead.

### Disk options

- Erase the whole drive. Creates a 1 MiB BIOS boot partition, a 1 GiB EFI
  partition, and a root partition, so the drive boots on both UEFI and legacy
  BIOS computers.
- Dual-boot. Choose a partition you already made for Sona from a menu. On
  UEFI computers the existing EFI partition is reused without formatting, and
  the Sona boot loader is added next to the one Windows uses.

### Unattended installs

The installer can run with no questions, using an answer file:

    sona-install --unattended my-answers.conf

Copy `examples/unattended-answers.conf`, fill it in, and set
`CONFIRM_ERASE=yes`. The installer refuses to touch any disk without it.
`DISK=auto` only works when the computer has exactly one drive.

### Logging in

Installed systems have no graphical login screen. Speakup (espeakup) talks
at the text console login on tty1, and as soon as you log in the SonicDE
desktop starts with Orca. Speakup is turned off while the desktop runs, so
it never talks over Orca, and comes back when you log off. If you chose
automatic login, tty1 logs you in by itself. To start the desktop again
after logging off, type `exit`.

## Package repositories

Installed systems use the official Arch repositories plus:

- XLibre, for the X display server.
- SonicDE (github.com/sonicde-arch/stable), for the desktop. Signed. The key
  is trusted only if it matches fingerprint
  A85BB166B49A4C58C39125073B87898C73F11DF5.
- Stormux (packages.stormux.org). Signed. The key is trusted only if it
  matches fingerprint 52ADA49000F1FF0456F8AEEFB4CDE1CD56EF8E82.
- Jenux (repo.jenux.dev, with nashcentral.duckdns.org as a backup). Unsigned.

The community repositories come after the official ones, so official
packages win when both have a package with the same name. If a community
server cannot be reached during install, Stormux and Jenux are commented
out in /etc/pacman.conf instead of stopping the install. SonicDE is
required. The live ISO has the same repositories set up.

## Building the ISO

On an Arch Linux system:

    sudo pacman -S archiso python-pip
    sudo scripts/build-iso.sh

The ISO is about 4 GB. The package lists come from the SONA PACKAGES block
at the top of `Install`, so the ISO and installed systems never drift apart.

## Quick test (about 2 minutes)

    sudo scripts/quick-test.sh

Runs the installer's system setup (everything after the disk is
partitioned) in a throwaway container on this computer, then checks the
result: SonicDE, login and Speakup handoff, Orca, Orca Bridge, shortcuts,
the XP theme, and the repositories. It shares this computer's package cache,
and keeps a base system in `out/quick/base`, so repeat runs are fast. It does
not test partitioning or the boot loader; the virtual machine test below
does. Options: `--copy` (test the "copy the live system" install, using the
newest ISO in `out/`), `--copy --offline` (the same with no internet),
`--shell` (look around inside the result), `--keep` (leave it mounted),
`--fresh` (rebuild the base after changing the package lists).

## Testing in a virtual machine

    sudo pacman -S qemu-desktop edk2-ovmf
    scripts/boot-sona-qemu.sh          # UEFI
    BIOS=1 scripts/boot-sona-qemu.sh   # legacy BIOS

Delete `out/sona-test-disk.qcow2` to start again with a blank test disk.

## Automatic builds

GitHub builds the ISO automatically:

- On every push to main that changes the installer, the ISO profile, or the
  scripts. The ISO can be downloaded from the run's page in the Actions tab
  for 14 days.
- Every Monday, and whenever the workflow is started by hand from the
  Actions tab. These builds are also published as releases with a SHA-256
  checksum. Only the 5 newest releases are kept.

Every build first checks all shell scripts with bash and shellcheck. After
the ISO is built, `scripts/ci-install-test.sh` boots it in a virtual
machine, installs Sona with `scripts/ci/answers.conf`, and boots the
installed system, once with UEFI and once with legacy BIOS. A release is
only published when both pass. The test logs are saved with each run.

You can run the same test on your own computer:

    sudo pacman -S qemu-desktop edk2-ovmf libarchive
    scripts/ci-install-test.sh out/sona-*.iso uefi
