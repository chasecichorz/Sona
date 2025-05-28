#!/bin/bash
set -euo pipefail

echo "🔄 Updating system..."
sudo dnf upgrade -y

echo "🧱 Installing MATE desktop..."
sudo dnf groupinstall -y "MATE Desktop"

echo "🗣 Installing accessibility tools..."
sudo dnf install -y orca speech-dispatcher espeak

echo "🛒 Installing DNF Dragora (GUI package manager)..."
sudo dnf install -y dnfdragora

echo "🔗 Enabling RPM Fusion Free & Non-Free..."
sudo dnf install -y \
  https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
  https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

echo "📦 Enabling Flathub repository..."
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

echo "🔐 Enabling LightDM autologin for user 'sona'..."
sudo mkdir -p /etc/lightdm/lightdm.conf.d
echo -e "[Seat:*]\nautologin-user=sona\nautologin-session=mate" | sudo tee /etc/lightdm/lightdm.conf.d/50-autologin.conf

echo "📁 Creating user 'sona' with home directory..."
sudo useradd -m -G wheel,audio,video -s /bin/bash sona
echo "sona:sona" | sudo chpasswd

echo "✅ Enabling services..."
sudo systemctl enable lightdm
sudo systemctl enable NetworkManager
sudo systemctl enable speech-dispatcher

echo "🎉 Setup complete. Reboot and log into MATE as 'sona'."
