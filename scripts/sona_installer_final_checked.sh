#!/usr/bin/env bash
set -euo pipefail

# ─── Helper functions ───────────────────────────────────────────────────────────
log() { printf '\n==> %s\n' "$1"; }
error_exit() { printf '❌ %s\n' "$1"; exit 1; }
install() { pacman -Sy --noconfirm --needed "$@"; }

# ─── Preflight cleanup & checks ─────────────────────────────────────────────────
if [[ "$EUID" -ne 0 ]]; then
  error_exit "Please run as root (or via sudo)."
fi
clear
log "Sona Linux Installer starting..."

log "Initializing pacman keyring..."
pacman-key --init
# ─── Keyring & network check ────────────────────────────────────────────────────
pacman-key --populate archlinux

if ! ping -c1 archlinux.org &>/dev/null; then
  error_exit "No internet detected. Connect using 'iwctl' or 'nmtui'."
fi

read -rp "Full name: " FULLNAME
read -rp "Username (lowercase): " USERNAME
# ─── User configuration ─────────────────────────────────────────────────────────
USERNAME=${USERNAME,,}
read -rp "Hostname: " HOSTNAME

while true; do
  read -rsp "Password: " PASSWORD; echo
  read -rsp "Confirm password: " CONFIRM; echo
  [[ "$PASSWORD" == "$CONFIRM" ]] && break
  echo "Passwords did not match; try again."
done

read -rp "Language locale (default: en_US.UTF-8): " LANG_LOCALE
LANG_LOCALE=${LANG_LOCALE:-en_US.UTF-8}
read -rp "Console keymap (default: us): " CONSOLE_KEYMAP
CONSOLE_KEYMAP=${CONSOLE_KEYMAP:-us}
read -rp "X11 keyboard layout (default: us): " X11_KEYBOARD
X11_KEYBOARD=${X11_KEYBOARD:-us}

echo "Select a time zone:"
select TZ in UTC America/New_York America/Chicago America/Denver America/Los_Angeles Europe/London Manual; do
# ─── Timezone selection ─────────────────────────────────────────────────────────
  if [[ "$TZ" == "Manual" ]]; then
    read -rp "Enter full time zone (e.g. Europe/Berlin): " TIMEZONE
  else
    TIMEZONE=$TZ
  fi
  break
# ─── Disk partitioning ──────────────────────────────────────────────────────────
done

lsblk -d -e 7,11 -o NAME,SIZE,MODEL | nl
DISKS=( $(lsblk -d -e 7,11 -o NAME) )
while true; do
  read -rp "Disk number to install to (1-${#DISKS[@]}): " DN
  if [[ "$DN" =~ ^[0-9]+$ ]] && (( DN >= 1 && DN <= ${#DISKS[@]} )); then
    DISK="/dev/${DISKS[$((DN-1))]}"
    log "Selected disk: $DISK"
    break
  fi
  echo "Invalid selection; try again."
done

# map partitions
log "Partitioning disk ${DISK}..."
parted --script "${DISK}"   mklabel gpt   mkpart primary fat32 1MiB 513MiB   set 1 boot on   mkpart primary ext4 513MiB 100%   || error_exit "Partitioning failed on ${DISK}"

log "Verifying partitions..."
parted --script "${DISK}" print || error_exit "Failed to list partitions"

# format & mount
if [[ "${DISK}" =~ nvme ]]; then
  EFI_PART="${DISK}p1"; ROOT_PART="${DISK}p2"
else
  EFI_PART="${DISK}1";  ROOT_PART="${DISK}2"
fi
log "EFI: ${EFI_PART}, ROOT: ${ROOT_PART}"

# Skipping desktop selection logic; defaulting to MATE only
log "Installing base system with pacstrap..."
log "Installing base system with full desktop and accessibility support..."
# Installing all required packages including base system and MATE
pacstrap /mnt \
  base linux linux-firmware sudo networkmanager \
  mate mate-extra lightdm lightdm-gtk-greeter network-manager-applet \
  espeakup speech-dispatcher orca xdg-user-dirs xdg-utils \
  grub efibootmgr os-prober reflector
genfstab -U /mnt > /mnt/etc/fstab
genfstab -U /mnt > /mnt/etc/fstab
genfstab -U /mnt > /mnt/etc/fstab
mkfs.fat -F32 "${EFI_PART}" || error_exit "mkfs.fat failed on ${EFI_PART}"
log "Formatting ${ROOT_PART} as ext4"
mkfs.ext4 -F "${ROOT_PART}" || error_exit "mkfs.ext4 failed on ${ROOT_PART}"

log "Mounting ${ROOT_PART} to /mnt"
mount "${ROOT_PART}" /mnt || error_exit "Failed to mount ${ROOT_PART}"
mkdir -p /mnt/boot
log "Mounting ${EFI_PART} to /mnt/boot"
mount "${EFI_PART}" /mnt/boot || error_exit "Failed to mount ${EFI_PART}"

echo "Choose a desktop environment:"
# defaulted Y/N prompts
echo "1) mate (default)"
read -rp "Enter number (1-3) [default: 1]: " DE_NUM
DE_NUM=${DE_NUM:-1}
case "$DE_NUM" in
# ─── Base install & fstab ───────────────────────────────────────────────────────
  1) DE="mate" ;;
  *) echo "Invalid choice, defaulting to mate."; DE="mate" ;;
# ─── Chroot configuration ───────────────────────────────────────────────────────
esac

read -rp "Enable autologin? (y/N): " AUTOLOGIN; AUTOLOGIN=${AUTOLOGIN,,}; AUTOLOGIN=${AUTOLOGIN:-n}
read -rp "Enable Bluetooth? (y/N): " ENABLE_BT; ENABLE_BT=${ENABLE_BT,,}; ENABLE_BT=${ENABLE_BT:-n}
read -rp "Enable Flatpak? (y/N): " INSTALL_FLATPAK; INSTALL_FLATPAK=${INSTALL_FLATPAK,,}; INSTALL_FLATPAK=${INSTALL_FLATPAK:-n}
# timezone & locale
read -rp "Install Dev Tools? (y/N): " INSTALL_DEV; INSTALL_DEV=${INSTALL_DEV,,}; INSTALL_DEV=${INSTALL_DEV:-n}
read -rp "Install Accessibility Extras? (y/N): " INSTALL_ACC; INSTALL_ACC=${INSTALL_ACC,,}; INSTALL_ACC=${INSTALL_ACC:-n}
read -rp "Install Android/Waydroid? (y/N): " INSTALL_ANDROID; INSTALL_ANDROID=${INSTALL_ANDROID,,}; INSTALL_ANDROID=${INSTALL_ANDROID:-n}

log "Installing base system..."
# hostname & keymap
genfstab -U /mnt >> /mnt/etc/fstab

log "Entering chroot..."
# X11 layout
arch-chroot /mnt /bin/bash <<EOF
set -euo pipefail
log() { printf "   → %s\n" "\$1"; }

ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
hwclock --systohc
echo "${LANG_LOCALE} UTF-8" >> /etc/locale.gen; locale-gen
echo "LANG=${LANG_LOCALE}" > /etc/locale.conf
echo "${HOSTNAME}" > /etc/hostname
# users & sudo
echo "KEYMAP=${CONSOLE_KEYMAP}" > /etc/vconsole.conf

mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/00-keyboard.conf <<XKB
Section "InputClass"
    Identifier "system-keyboard"
# enable services & speakup
    MatchIsKeyboard "on"
    Option "XkbLayout" "${X11_KEYBOARD}"
EndSection
# microcode
XKB

echo "root:\${PASSWORD}" | chpasswd
useradd -m --shell /bin/bash -c "\${FULLNAME}" -G wheel,audio,video,storage "\${USERNAME}"
# GPU drivers & hybrid
echo "\${USERNAME}:\${PASSWORD}" | chpasswd
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/10-sona; chmod 0440 /etc/sudoers.d/10-sona

systemctl enable NetworkManager speech-dispatcher espeakup systemd-timesyncd
echo speakup_soft > /etc/modules-load.d/speakup.conf

vendor=\$(lscpu | awk '/Vendor ID/ {print \$3}')
if [[ "\$vendor" == "GenuineIntel" ]]; then install intel-ucode; elif [[ "\$vendor" == "AuthenticAMD" ]]; then install amd-ucode; fi

GPU=\$(lspci | grep -Ei 'VGA|3D' || true)
HAS_NVIDIA=false; HAS_INTEL=false; HAS_AMD=false
if echo "\$GPU" | grep -qi nvidia; then HAS_NVIDIA=true; fi
# network drivers
if echo "\$GPU" | grep -qi intel; then HAS_INTEL=true; fi
if echo "\$GPU" | grep -Ei 'AMD|ATI'; then HAS_AMD=true; fi
\$HAS_INTEL && install xf86-video-intel
\$HAS_AMD && install xf86-video-amdgpu
# virtualization
\$HAS_NVIDIA && install nvidia nvidia-utils nvidia-settings
if \$HAS_NVIDIA && \$HAS_INTEL; then log "Hybrid graphics (Intel + NVIDIA) detected. Installing PRIME/Optimus tools."; install nvidia-prime; fi
# DE install & autologin
if \$HAS_NVIDIA && \$HAS_AMD; then log "Hybrid graphics (AMD + NVIDIA) detected. Consider manual dGPU management."; fi

NET=\$(lspci | grep -i network || true)
if echo "\$NET" | grep -qi broadcom; then install broadcom-wl; fi
if grep -qi microsoft /sys/class/dmi/id/sys_vendor 2>/dev/null; then install hyperv-guest-utils; fi

if [[ "\${DE}" == "mate" ]]; then
  install mate mate-extra lightdm lightdm-gtk-greeter network-manager-applet
  systemctl enable lightdm
  if [[ "\${AUTOLOGIN}" == "y" ]]; then
    mkdir -p /etc/lightdm/lightdm.conf.d
    cat > /etc/lightdm/lightdm.conf.d/50-autologin.conf <<AUTOSTART
[Seat:*]
autologin-user=\${USERNAME}
autologin-session=mate
AUTOSTART
  fi
# Orca autostart with welcome message
  systemctl enable lightdm
  if [[ "\${AUTOLOGIN}" == "y" ]]; then
    mkdir -p /etc/lightdm/lightdm.conf.d
    cat > /etc/lightdm/lightdm.conf.d/50-autologin.conf <<AUTOSTART
[Seat:*]
autologin-user=\${USERNAME}
AUTOSTART
  fi
# optional extras
  cat > /etc/gdm/custom.conf <<GDMCONF
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=\${USERNAME}
WaylandEnable=false
GDMCONF
# GRUB installation
  systemctl enable gdm
fi

mkdir -p /home/\${USERNAME}/.config/autostart
cat > /home/\${USERNAME}/.config/autostart/orca.desktop <<DESKTOP
[Desktop Entry]
Type=Application
Name=Orca
Exec=orca
X-GNOME-Autostart-enabled=true
OnlyShowIn=MATE;GNOME;XFCE;
DESKTOP
chown -R \${USERNAME}:\${USERNAME} /home/\${USERNAME}

[[ "\${ENABLE_BT}" == "y" ]] && install bluez bluez-utils && systemctl enable bluetooth
[[ "\${INSTALL_FLATPAK}" == "y" ]] && install flatpak && flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
[[ "\${INSTALL_DEV}" == "y" ]] && install base-devel git python python-pip rust nodejs npm go jdk-openjdk
[[ "\${INSTALL_ACC}" == "y" ]] && install wine festival speech-tools speech-dispatcher espeak-ng
[[ "\${INSTALL_ANDROID}" == "y" ]] && install waydroid aosp-uiautomator && echo "Waydroid installed — run 'sudo waydroid init' after reboot"

if ! grep -q "^GRUB_DISABLE_OS_PROBER=false" /etc/default/grub; then
  echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub
fi
if [[ -d /sys/firmware/efi ]]; then
  grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
else
  grub-install --target=i386-pc --recheck \$DISK
fi
grub-mkconfig -o /boot/grub/grub.cfg
EOF

log "✅ Installation complete! Run: umount -R /mnt && reboot"
