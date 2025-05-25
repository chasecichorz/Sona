#!/bin/bash
set -euo pipefail

log() { echo -e "\n==> $1"; }
error_exit() { echo "❌ $1"; exit 1; }
install() { pacman -S --noconfirm --needed "$@"; }

# Show system info
clear
echo "=== Sona Linux Automated Installer ==="
uname -a
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT
echo

# Check internet
if ! ping -c 1 archlinux.org &>/dev/null; then
  error_exit "No internet. Connect using 'iwctl' or 'nmtui' and try again."
fi

# Auto-mirror optimization
install reflector
reflector --latest 10 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
log "Mirrorlist optimized."

# Static config values
USERNAME="sona"
PASSWORD="sona"
HOSTNAME="sona-pc"
FULLNAME="Sona User"
LANG_LOCALE="en_US.UTF-8"
TIMEZONE="America/New_York"
CONSOLE_KEYMAP="us"
X11_KEYBOARD="us"

# Disk selection
lsblk -d -e 7,11 -o NAME,SIZE,MODEL | nl
DISKS=($(lsblk -d -e 7,11 -o NAME))
disk_count=${#DISKS[@]}

while true; do
  read -rp "Disk number to install to (1-$disk_count): " DISK_NUM
  if [[ "$DISK_NUM" =~ ^[0-9]+$ ]] && [ "$DISK_NUM" -ge 1 ] && [ "$DISK_NUM" -le "$disk_count" ]; then
    DISK_NAME="${DISKS[$((DISK_NUM-1))]}"
    DISK="/dev/$DISK_NAME"
    log "Selected disk: $DISK"
    break
  else
    echo "Invalid input. Try again."
  fi
done

# Wipe and partition disk
echo "⚠️ ALL DATA ON $DISK WILL BE ERASED!"
read -rp "Continue? Type YES to proceed: " confirm
[[ "$confirm" == "YES" ]] || exit 1

parted --script "$DISK" \
  mklabel gpt \
  mkpart primary fat32 1MiB 513MiB \
  set 1 esp on \
  mkpart primary ext4 513MiB 100%

if [[ "$DISK_NAME" =~ nvme ]]; then
  EFI_PART="${DISK}p1"
  ROOT_PART="${DISK}p2"
else
  EFI_PART="${DISK}1"
  ROOT_PART="${DISK}2"
fi

mkfs.fat -F32 "$EFI_PART"
mkfs.ext4 -F "$ROOT_PART"
mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot
mount "$EFI_PART" /mnt/boot

# Install base system
log "Installing base system..."
install base linux linux-firmware sudo networkmanager grub efibootmgr os-prober xdg-user-dirs xdg-utils espeakup
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot configuration
arch-chroot /mnt /bin/bash <<EOFCHROOT
set -euo pipefail
log() { echo "==> \$1"; }

ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc
echo "$LANG_LOCALE UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=$LANG_LOCALE" > /etc/locale.conf
echo "$HOSTNAME" > /etc/hostname
echo "KEYMAP=$CONSOLE_KEYMAP" > /etc/vconsole.conf

mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/00-keyboard.conf <<XKB
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "$X11_KEYBOARD"
EndSection
XKB

echo "root:$PASSWORD" | chpasswd
useradd -m -c "$FULLNAME" -G wheel,audio,video,storage $USERNAME
echo "$USERNAME:$PASSWORD" | chpasswd
echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/10-sona-wheel
chmod 440 /etc/sudoers.d/10-sona-wheel

systemctl enable NetworkManager
systemctl enable speech-dispatcher
systemctl enable espeakup
systemctl enable systemd-timesyncd

# Install CPU microcode
vendor=\$(lscpu | grep -i 'vendor' | awk '{print \$3}')
if [[ "\$vendor" == "GenuineIntel" ]]; then
  install intel-ucode
elif [[ "\$vendor" == "AuthenticAMD" ]]; then
  install amd-ucode
fi

# NVIDIA driver detection
if lspci | grep -E "VGA|3D" | grep -qi nvidia; then
  install nvidia nvidia-utils nvidia-settings
  echo "NVIDIA GPU detected and drivers installed."
fi

# Install packages
install xorg xorg-xinit orca espeak-ng brltty gnome-terminal pipewire pipewire-pulse pipewire-alsa pipewire-jack wireplumber alsa-utils
install mate mate-extra lightdm lightdm-gtk-greeter network-manager-applet
install flatpak bluez bluez-utils virtualbox virtualbox-host-modules-arch base-devel git python python-pip rust nodejs npm go jdk-openjdk
install wine festival speech-tools speech-dispatcher espeak-ng
install waydroid aosp-uiautomator wireshark-qt hashcat metasploit fish zsh emacs vim tmux bspwm

systemctl enable lightdm
systemctl enable bluetooth

# Flatpak remote
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# Add user to vboxusers
usermod -aG vboxusers $USERNAME

# Orca autostart
mkdir -p /home/$USERNAME/.config/autostart
cat > /home/$USERNAME/.config/autostart/orca.desktop <<DESKTOP
[Desktop Entry]
Type=Application
Name=Orca
Exec=orca
X-GNOME-Autostart-enabled=true
OnlyShowIn=MATE;GNOME;XFCE;
DESKTOP
chown -R $USERNAME:$USERNAME /home/$USERNAME

# LightDM autologin
mkdir -p /etc/lightdm/lightdm.conf.d
echo -e "[Seat:*]\nautologin-user=$USERNAME\nautologin-session=mate" > /etc/lightdm/lightdm.conf.d/50-autologin.conf

# Enable os-prober
if ! grep -q "GRUB_DISABLE_OS_PROBER=false" /etc/default/grub; then
  echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub
fi

# Install GRUB
if [[ -d /sys/firmware/efi ]]; then
  grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
else
  grub-install --target=i386-pc --recheck $DISK
fi

grub-mkconfig -o /boot/grub/grub.cfg

echo "✅ Install complete! Run: umount -R /mnt && reboot" EOFCHROOT