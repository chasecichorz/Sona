#!/usr/bin/env bash
# shellcheck disable=SC2034

iso_name="sona"
iso_label="SONA_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="Sona Linux <https://github.com/chasecichorz/sona>"
iso_application="Sona Linux accessible live and install media"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="arch"
bootmodes=('bios.syslinux'
           'uefi.systemd-boot')
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
# zstd, not xz: mksquashfs 4.7.3 stopped with "xz uncompress failed with
# error code 9" on the SonicDE image (2026-11-13), while zstd builds and
# reads back identical. zstd also unpacks faster when the live system boots.
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '15' '-b' '1M')
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/etc/gshadow"]="0:0:400"
  ["/etc/sudoers.d"]="0:0:750"
  ["/etc/sudoers.d/10-sona-live"]="0:0:440"
  ["/root"]="0:0:750"
  ["/root/.automated_script.sh"]="0:0:755"
  ["/root/.gnupg"]="0:0:700"
  ["/usr/local/bin/choose-mirror"]="0:0:755"
  ["/usr/local/bin/Installation_guide"]="0:0:755"
  ["/usr/local/bin/livecd-sound"]="0:0:755"
  ["/usr/local/bin/sona-install"]="0:0:755"
  ["/usr/local/bin/sona-session-audio"]="0:0:755"
  ["/usr/local/bin/sona-pick-sound"]="0:0:755"
  ["/usr/local/bin/sona-orca-extensions"]="0:0:755"
  ["/usr/local/bin/sona-kokoro-setup"]="0:0:755"
  ["/usr/local/bin/sona-live-setup"]="0:0:755"
  ["/usr/local/bin/sona-live-welcome"]="0:0:755"
  ["/usr/local/bin/sona-xp-firstrun"]="0:0:755"
  ["/usr/local/bin/sona-live-trust-keys"]="0:0:755"
  ["/home/sona/Desktop/install-sona.desktop"]="0:0:755"
)
