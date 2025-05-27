#!/usr/bin/env bash
set -euo pipefail

# ─── Helper functions ───────────────────────────────────────────────────────────
log() { printf '\n==> %s\n' "$1"; }
error_exit() { printf '❌ %s\n' "$1"; exit 1; }
install_pkg() { pacman -Sy --noconfirm --needed "$@"; }

# ─── Preflight cleanup & checks ─────────────────────────────────────────────────
[[ "$EUID" -eq 0 ]] || error_exit "Please run as root (or via sudo)."
umount -R /mnt &>/dev/null || true
command -v parted &>/dev/null || error_exit "parted not installed."
command -v pacstrap &>/dev/null || error_exit "arch-install-scripts not installed."

clear
log "Sona Linux Installer starting..."

# ─── Keyring & network check ────────────────────────────────────────────────────
log "Initializing pacman keyring..."
pacman-key --init && pacman-key --populate archlinux

log "Checking network connectivity..."
if ! ping -c1 archlinux.org &>/dev/null && ! ping -c1 1.1.1.1 &>/dev/null; then
  error_exit "No internet detected. Connect using 'iwctl' or 'nmtui'."
fi

# ─── User configuration ─────────────────────────────────────────────────────────
read -rp "Full name: " FULLNAME
read -rp "Username (lowercase): " USERNAME
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

# ─── Timezone selection ─────────────────────────────────────────────────────────
echo "Select a time zone:"
select TZ in UTC America/New_York America/Chicago America/Denver America/Los_Angeles Europe/London Manual; do
  [[ "$TZ" == "Manual" ]] && read -rp "Enter full time zone (e.g. Europe/Berlin): " TIMEZONE || TIMEZONE=$TZ
  break
done

# ─── Disk partitioning ──────────────────────────────────────────────────────────
log "Available disks:"
lsblk -d -e 7,11 -o NAME,SIZE,MODEL | nl
DISKS=( $(lsblk -d -e 7,11 -o NAME) )
while true; do
  read -rp "Install to disk number (1-${#DISKS[@]}): " DN
  [[ "$DN" =~ ^[0-9]+$ ]] && ((DN>=1 && DN<=${#DISKS[@]})) && break
  echo "Invalid selection; try again."
done
DISK="/dev/${DISKS[$((DN-1))]}"
log "Partitioning $DISK..."
parted --script "$DISK"   mklabel gpt   mkpart primary fat32 1MiB 513MiB   set 1 boot on   mkpart primary ext4 513MiB 100%   || error_exit "Partitioning failed."

parted --script "$DISK" print

# map partitions
if [[ "$DISK" =~ nvme ]]; then
  EFI_PART="${DISK}p1"; ROOT_PART="${DISK}p2"
else
  EFI_PART="${DISK}1";  ROOT_PART="${DISK}2"
fi

# format & mount
log "Formatting $EFI_PART (FAT32) and $ROOT_PART (ext4)"
mkfs.fat -F32 "$EFI_PART"
mkfs.ext4 -F "$ROOT_PART"
mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot
mount "$EFI_PART" /mnt/boot

# ─── Desktop & feature selection ───────────────────────────────────────────────
echo "Choose desktop (default: 1)"
echo " 1) mate"
echo " 2) xfce"
echo " 3) gnome"
read -rp "Enter number [1]: " DE_NUM
DE_NUM=${DE_NUM:-1}
case "$DE_NUM" in
  2) DE="xfce" ;;
  3) DE="gnome" ;;
  *) DE="mate" ;;
esac

# defaulted Y/N prompts
for var in AUTOLOGIN ENABLE_BT INSTALL_FLATPAK INSTALL_DEV INSTALL_ACC INSTALL_ANDROID; do
  read -rp "${var//_/ }? (y/N): " tmp
  declare "$var"=${tmp,,}
  eval "$var"=\${$var:-n}
done

# ─── Base install & fstab ───────────────────────────────────────────────────────
log "Installing base system..."
pacstrap /mnt   base linux linux-firmware sudo networkmanager grub efibootmgr os-prober   espeakup xdg-user-dirs xdg-utils
genfstab -U /mnt > /mnt/etc/fstab

# ─── Chroot configuration ───────────────────────────────────────────────────────
log "Configuring system..."
arch-chroot /mnt /bin/bash <<EOF
set -euo pipefail
log() { printf "   → %s\n" "\$1"; }

# timezone & locale
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc
echo "$LANG_LOCALE UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=$LANG_LOCALE" > /etc/locale.conf

# hostname & keymap
echo "$HOSTNAME" > /etc/hostname
echo "KEYMAP=$CONSOLE_KEYMAP" > /etc/vconsole.conf

# X11 layout
mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/00-keyboard.conf <<XKB
Section "InputClass"
  Identifier "system-keyboard"
  MatchIsKeyboard "on"
  Option "XkbLayout" "$X11_KEYBOARD"
EndSection
XKB

# users & sudo
echo "root:$PASSWORD" | chpasswd
useradd -m -c "$FULLNAME" -G wheel,audio,video,storage -s /bin/bash $USERNAME
echo "$USERNAME:$PASSWORD" | chpasswd
echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/10-wheel
chmod 0440 /etc/sudoers.d/10-wheel

# enable services & speakup
systemctl enable NetworkManager speech-dispatcher espeakup systemd-timesyncd
echo speakup_soft > /etc/modules-load.d/speakup.conf

# microcode
vendor=\$(lscpu | awk '/Vendor ID/ {print \$3}')
if [[ "\$vendor" == "GenuineIntel" ]]; then install_pkg intel-ucode; fi
if [[ "\$vendor" == "AuthenticAMD" ]]; then install_pkg amd-ucode; fi

# GPU drivers & hybrid
GPU=\$(lspci | grep -Ei 'VGA|3D' || true)
HAS_NVIDIA=\$(echo "\$GPU" | grep -qi nvidia && echo yes || echo no)
HAS_INTEL=\$(echo "\$GPU" | grep -qi intel && echo yes || echo no)
HAS_AMD=\$(echo "\$GPU" | grep -Ei 'AMD|ATI' && echo yes || echo no)
[[ "\$HAS_INTEL" == yes ]] && install_pkg xf86-video-intel
[[ "\$HAS_AMD" == yes ]] && install_pkg xf86-video-amdgpu
[[ "\$HAS_NVIDIA" == yes ]] && install_pkg nvidia nvidia-utils nvidia-settings
if [[ "\$HAS_NVIDIA" == yes && "\$HAS_INTEL" == yes ]]; then
  log "Hybrid Intel+NVIDIA detected, installing nvidia-prime"
  install_pkg nvidia-prime
fi

# network drivers
NET=\$(lspci | grep -i network || true)
[[ "\$NET" =~ [Rr]ealtek ]] && install_pkg r8168
[[ "\$NET" =~ [Bb]roadcom ]] && install_pkg broadcom-wl

# virtualization
grep -qi microsoft /sys/class/dmi/id/sys_vendor &>/dev/null && install_pkg hyperv-guest-utils

# DE install & autologin
if [[ "$DE" == mate ]]; then
  install_pkg mate mate-extra lightdm lightdm-gtk-greeter network-manager-applet
  systemctl enable lightdm
  [[ "$AUTOLOGIN" == y ]] &&     { mkdir -p /etc/lightdm/lightdm.conf.d;       echo -e "[Seat:*]\nautologin-user=$USERNAME\nautologin-session=mate"       > /etc/lightdm/lightdm.conf.d/50-autologin.conf; }
elif [[ "$DE" == xfce ]]; then
  install_pkg xfce4 xfce4-goodies lightdm lightdm-gtk-greeter network-manager-applet
  systemctl enable lightdm
  [[ "$AUTOLOGIN" == y ]] &&     { mkdir -p /etc/lightdm/lightdm.conf.d;       echo -e "[Seat:*]\nautologin-user=$USERNAME\nautologin-session=xfce"       > /etc/lightdm/lightdm.conf.d/50-autologin.conf; }
else
  install_pkg gnome gdm
  cat > /etc/gdm/custom.conf <<GDM
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=$USERNAME
WaylandEnable=false
GDM
  systemctl enable gdm
fi

# Orca autostart with welcome message
mkdir -p /home/$USERNAME/.config/autostart
cat > /home/$USERNAME/.config/autostart/orca.desktop <<DESKTOP
[Desktop Entry]
Type=Application
Name=Orca Screen Reader
Exec=bash -lc 'orca & sleep 3 && spd-say "Welcome to Sona Linux. The installer is ready."'
X-GNOME-Autostart-enabled=true
OnlyShowIn=MATE;GNOME;XFCE;
DESKTOP
chown -R $USERNAME:$USERNAME /home/$USERNAME

# optional extras
[[ "$ENABLE_BT" == y ]] && install_pkg bluez bluez-utils && systemctl enable bluetooth
[[ "$INSTALL_FLATPAK" == y ]] && install_pkg flatpak && flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
[[ "$INSTALL_DEV" == y ]] && install_pkg base-devel git python python-pip rust nodejs npm go jdk-openjdk
[[ "$INSTALL_ACC" == y ]] && install_pkg wine festival speech-tools speech-dispatcher espeak-ng
[[ "$INSTALL_ANDROID" == y ]] && install_pkg waydroid aosp-uiautomator && echo "Waydroid ready — run 'sudo waydroid init' after reboot"

# GRUB installation
sed -i 's/^GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub ||   echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub
if [[ -d /sys/firmware/efi ]]; then
  grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
else
  grub-install --target=i386-pc --recheck $DISK
fi
grub-mkconfig -o /boot/grub/grub.cfg

EOF

log "✅ Installation complete! Run: umount -R /mnt && reboot"
