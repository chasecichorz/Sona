# Sona Linux

Sona Linux is an accessible Arch Linux setup for blind and low-vision users.
It installs the MATE desktop with the Orca screen reader, console speech
with espeakup, XLibre, and a set of accessible everyday apps.

## What is in this repository

- `Install` - the installer. This is the only installer; edit this file.
- `sona-live/` - the archiso profile for the Sona live ISO. It is based on
  Arch Linux's official releng profile. Speech starts on every boot, and the
  installer is available as the `sona-install` command.
- `scripts/build-iso.sh` - builds the ISO into `out/`.
- `scripts/boot-sona-qemu.sh` - boots the ISO in a QEMU virtual machine with
  sound and a blank 40 GB test disk.
- `scripts/check-main-repo-packages.sh` - checks that every package in the
  ISO package list exists.
- `.github/workflows/build-and-release.yml` - builds the ISO on GitHub.
- `docs/` - the project web page.

## Installing

From the Sona live ISO, type `sona-install` and press Enter.

From a standard Arch Linux ISO, connect to the internet, then run:

    curl -LO https://raw.githubusercontent.com/chasecichorz/sona/main/Install
    bash Install

The installer asks its questions first and changes nothing on disk until you
confirm. Press Escape on any question to quit.

### Disk options

- Erase the whole drive. Creates a 1 MiB BIOS boot partition, a 1 GiB EFI
  partition, and a root partition, so the drive boots on both UEFI and legacy
  BIOS computers.
- Dual-boot. Choose a partition you already made for Sona from a menu. On
  UEFI computers the existing EFI partition is reused without formatting, and
  the Sona boot loader is added next to the one Windows uses.

## Package repositories

Installed systems use the official Arch repositories plus:

- XLibre, for the X display server.
- Stormux (packages.stormux.org). Signed. The key is trusted only if it
  matches fingerprint 52ADA49000F1FF0456F8AEEFB4CDE1CD56EF8E82.
- Jenux (repo.jenux.dev, with nashcentral.duckdns.org as a backup). Unsigned.

The community repositories come after the official ones, so official
packages win when both have a package with the same name. If a community
server cannot be reached during install, those repositories are commented
out in /etc/pacman.conf instead of stopping the install.

## Building the ISO

On an Arch Linux system:

    sudo pacman -S archiso
    sudo scripts/build-iso.sh

## Testing in a virtual machine

    sudo pacman -S qemu-desktop edk2-ovmf
    scripts/boot-sona-qemu.sh          # UEFI
    BIOS=1 scripts/boot-sona-qemu.sh   # legacy BIOS

Delete `out/sona-test-disk.qcow2` to start again with a blank test disk.
