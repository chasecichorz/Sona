# Sona Project Consolidation

This document brings together **all scripts, tools, and key decisions** from the Sona installer project into one place. Download the full archive of files here:

[Download sona_project_all.zip](sona_project_all.zip)

---

## 1. Interactive Installer (`install.sh`)
- Prompts for user info (name, username, password)
- Locale, keymap, X11 layout, timezone
- Disk selection: single- or dual-boot with partitioning logic
- MATE desktop + accessibility options (autologin, Bluetooth, Flatpak, dev tools)
- Hardware detection (CPU microcode, GPU, network drivers)
- Accessibility stack (Orca, speech-dispatcher, espeak-ng, brltty)
- Services enabled and GRUB configured (EFI & BIOS)

## 2. Automated Mate-Only Installer (`install-mate-auto.sh`)
- Zero prompts: defaults for user, hostname, locale, timezone
- Installs MATE + accessibility, all features auto-enabled
- Ideal for rapid VM testing

## 3. ISO Builder (`build-sona-iso.sh`)
- Uses `archiso` & `reflector`
- Injects `install.sh` and configs into live ISO
- Orca autostart & LightDM autologin in live environment
- Produces date-stamped ISO in `/root/sona-out/`

## 4. VM Creation Script (`create_arch_vm.bat`)
- Headless VirtualBox VM: 16 GB RAM, 8 CPUs, 100 GB disk
- Attaches Arch ISO from Downloads directory

## 5. Accessibility & Kernel Update (`update_accessibility.sh`)
- Builds latest Orca & Speech-Dispatcher from source
- ESpeak-NG backend
- Installs Ubuntu mainline kernel with `ubuntu-mainline-kernel.sh`

## 6. Repo Sync Setup (`clone_and_setup_repo.sh`, `sync_repo.sh`)
- Scripts + systemd units for periodic `git pull` synchronization

## 7. VPN & Networking Tools
- OpenVPN server/client setup (Linode guide + `openvpn_linode_setup.sh`)
- WireGuard quick-install (`install_wireguard.sh`)
- Archer AX4400 OpenVPN client steps

## 8. WSL-Compatible Installer (`sona_wsl_installer_full.sh`)
- Detects ArchWSL vs. Ubuntu WSL
- Installs MATE & accessibility under WSLg
- Configures Orca autostart and `.xinitrc`

## 9. Packstrap-First Installer Variant (`sona_installer_packstrapped.sh`)
- All packages in `pacstrap` before chroot
- Ensures services exist for enablement

## 10. Enhanced Variants & Deep Features
- Custom `pacman.conf` swap from Nash Central
- User/unattended mode toggle
- Preset package lists (base, basegui, mate, etc.)
- Encryption option and manual partition mode

---

### Usage Guide
1. **Download** the ZIP archive above.
2. **Choose** your workflow:
   - **Interactive**: `install.sh` on an Arch live USB.
   - **Automated**: `install-mate-auto.sh` in a VM.
   - **ISO Build**: `build-sona-iso.sh` on an Arch host.
3. **Support Tools**:
   - Windows script: `create_arch_vm.bat` for CLI VM spins.
   - Accessibility update: `update_accessibility.sh` on Mint/Ubuntu.
   - VPN: `openvpn_linode_setup.sh` or `install_wireguard.sh`.
   - Repo sync: use the tarball with clone/sync scripts and systemd units.
4. **Testing**: Use a fresh VM or hardware, iterate on feedback.
