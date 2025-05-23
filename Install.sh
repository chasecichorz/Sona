#!/bin/bash
set -euo pipefail

echo "Welcome to Arch Installer for Accessible Systems"
echo "This script will install Arch Linux with Orca screen reader and a desktop environment."
echo

# ========== USERNAME ==========
read -rp "Enter desired username: " USERNAME
USERNAME=${USERNAME,,}

# ========== PASSWORD ==========
while true; do
 read -rsp "Enter password: " PASSWORD; echo
 read -rsp "Confirm password: " CONFIRM; echo
 [[ "$PASSWORD" == "$CONFIRM" ]] && break
 echo "Passwords do not match. Try again."
done

# ========== TIME ZONE ==========
echo "Select your time zone:"
select TIMEZONE in \
 "UTC" \
 "America/New_York (Eastern)" \
 "America/Chicago (Central)" \
 "America/Denver (Mountain)" \
 "America/Los_Angeles (Pacific)" \
 "Enter manually"; do
 case $REPLY in
   1) TIMEZONE="UTC"; break ;;
   2) TIMEZONE="America/New_York"; break ;;
   3) TIMEZONE="America/Chicago"; break ;;
   4) TIMEZONE="America/Denver"; break ;;
   5) TIMEZONE="America/Los_Angeles"; break ;;
   6) read -rp "Enter full timezone (e.g., Europe/London): " TIMEZONE; break ;;
   *) echo "Invalid option." ;;
 esac
done

# ========== DISK SELECTION ==========
echo "Available disks:"
lsblk -d -e 7,11 -o NAME,SIZE,MODEL | nl
read -rp "Enter the number of the disk to install to: " DISK_NUM
DISK_NAME=$(lsblk -d -e 7,11 -o NAME | sed -n "${DISK_NUM}p")
DISK="/dev/$DISK_NAME"

# ========== DUAL BOOT ==========
read -rp "Are you dual-booting with Windows or another OS? (y/N): " DUALBOOT
DUALBOOT=${DUALBOOT,,}
if [[ "$DUALBOOT" == "y" || "$DUALBOOT" == "yes" ]]; then
 echo "You will now select an existing EFI partition and a root partition."
 lsblk -f
 read -rp "Enter your EFI partition (e.g., /dev/sda1): " EFI_PART
 read -rp "Enter your root (/) partition (e.g., /dev/sda5): " ROOT_PART

 mount "$ROOT_PART" /mnt
 mkdir -p /mnt/boot
 mount "$EFI_PART" /mnt/boot
else
 read -rp "This will erase all data on $DISK. Are you sure? (y/N): " confirm
 [[ "$confirm" =~ ^[Yy]$ ]] || exit 1

 parted --script "$DISK" \
   mklabel gpt \
   mkpart primary fat32 1MiB 513MiB \
   set 1 esp on \
   mkpart primary ext4 513MiB 100%

 mkfs.fat -F32 "${DISK}p1"
 mkfs.ext4 -F "${DISK}p2"

 mount "${DISK}p2" /mnt
 mkdir -p /mnt/boot
 mount "${DISK}p1" /mnt/boot
fi

# ========== DESKTOP ENVIRONMENT ==========
echo "Choose a desktop environment:"
select DE in "MATE" "XFCE" "GNOME"; do
 case $REPLY in
   1) DE="mate"; break ;;
   2) DE="xfce"; break ;;
   3) DE="gnome"; break ;;
   *) echo "Invalid option." ;;
 esac
done

# ========== AUTOLOGIN ==========
read -rp "Enable autologin? (y/N): " AUTOLOGIN
AUTOLOGIN=${AUTOLOGIN,,}
[[ "$AUTOLOGIN" == "y" || "$AUTOLOGIN" == "yes" ]] && AUTOLOGIN="yes" || AUTOLOGIN="no"

# ========== BLUETOOTH ==========
read -rp "Enable Bluetooth support? (y/N): " ENABLE_BT
ENABLE_BT=${ENABLE_BT,,}
[[ "$ENABLE_BT" == "y" || "$ENABLE_BT" == "yes" ]] && ENABLE_BT="yes" || ENABLE_BT="no"

# ========== FLATPAK ==========
read -rp "Install Flatpak and Flathub? (y/N): " ENABLE_FLATPAK
ENABLE_FLATPAK=${ENABLE_FLATPAK,,}
[[ "$ENABLE_FLATPAK" == "y" || "$ENABLE_FLATPAK" == "yes" ]] && ENABLE_FLATPAK="yes" || ENABLE_FLATPAK="no"

# ========== VIRTUALBOX ==========
read -rp "Install VirtualBox? (y/N): " INSTALL_VBOX
INSTALL_VBOX=${INSTALL_VBOX,,}
[[ "$INSTALL_VBOX" == "y" || "$INSTALL_VBOX" == "yes" ]] && INSTALL_VBOX="yes" || INSTALL_VBOX="no"

echo "Installing base system..."

# ========== BASE SYSTEM ==========
pacstrap /mnt base linux linux-firmware sudo networkmanager grub efibootmgr os-prober

genfstab -U /mnt >> /mnt/etc/fstab

# ========== CHROOT SETUP ==========
arch-chroot /mnt /bin/bash <<EOF
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "archblind" > /etc/hostname

systemctl enable NetworkManager

echo "root:$PASSWORD" | chpasswd
useradd -m -G wheel,audio,video,storage $USERNAME
echo "$USERNAME:$PASSWORD" | chpasswd
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

# Desktop + accessibility
pacman -Sy --noconfirm xorg xorg-xinit speech-dispatcher orca espeak brltty gnome-terminal

[[ "$DE" == "mate" ]] && pacman -S --noconfirm mate mate-extra lightdm lightdm-gtk-greeter network-manager-applet
[[ "$DE" == "xfce" ]] && pacman -S --noconfirm xfce4 xfce4-goodies lightdm lightdm-gtk-greeter network-manager-applet
[[ "$DE" == "gnome" ]] && pacman -S --noconfirm gnome gdm && systemctl enable gdm
[[ "$DE" != "gnome" ]] && systemctl enable lightdm

# Orca autostart
mkdir -p /home/$USERNAME/.config/autostart
cat > /home/$USERNAME/.config/autostart/orca.desktop <<EOL
[Desktop Entry]
Type=Application
Name=Orca Screen Reader
Exec=orca
X-GNOME-Autostart-enabled=true
EOL
chown -R $USERNAME:$USERNAME /home/$USERNAME

# GRUB beep
echo 'echo -e "\a"' >> /etc/grub.d/00_header
modprobe pcspkr
echo pcspkr >> /etc/modules-load.d/pcspkr.conf

# Bluetooth
[[ "$ENABLE_BT" == "yes" ]] && pacman -S --noconfirm bluez bluez-utils pulseaudio-bluetooth && systemctl enable bluetooth

# Flatpak
if [[ "$ENABLE_FLATPAK" == "yes" ]]; then
 pacman -S --noconfirm flatpak
 flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
fi

# VirtualBox
if [[ "$INSTALL_VBOX" == "yes" ]]; then
 pacman -S --noconfirm virtualbox virtualbox-host-modules-arch
 usermod -aG vboxusers $USERNAME
fi

# Thunderbird
pacman -S --noconfirm thunderbird

# Utilities
pacman -S --noconfirm firefox libreoffice-fresh wget git unzip zip p7zip htop neofetch rsync

# yay AUR helper
sudo -u $USERNAME bash -c "
cd /home/$USERNAME
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm
"

# Autologin
if [[ "$AUTOLOGIN" == "yes" && "$DE" != "gnome" ]]; then
mkdir -p /etc/lightdm/lightdm.conf.d
cat > /etc/lightdm/lightdm.conf.d/50-autologin.conf <<ALOGIN
[Seat:*]
autologin-user=$USERNAME
autologin-session=$DE
ALOGIN
fi

grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
EOF

echo "Installation complete! Reboot and remove installation media."
