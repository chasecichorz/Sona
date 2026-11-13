#!/usr/bin/env python3
"""Windows XP sounds for SonicDE that Plasma can't play by itself.

SonicDE plays most XP sounds through the WindowsXP sound theme
(~/.local/share/sounds/WindowsXP). This helper adds the rest:
- The XP startup sound for the first desktop after a boot, and the XP logon
  sound for later logins in the same boot (like XP). The logoff sound is
  played by ~/.bash_profile when X exits; the shutdown sound by
  xp-shutdown-sound.service.
- Window sounds: the xpsounds KWin script calls Play() over D-Bus
  (service local.xpsounds), because KWin scripts can't run programs.
- The XP balloon sound for notifications from non-KDE programs (browsers,
  notify-send). KDE's own notifications already have their own sounds.
- Turns off the Plasma device pop-up once, so it doesn't fight the XP
  AutoPlay window (xp_autoplay.py) for focus.

Started from ~/.config/autostart/xp-sonicde.desktop (SonicDE only).
"""

import fcntl
import os
import subprocess
import sys

import dbus
import dbus.bus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from xp_common import SOUND_DIR, play, sound_was_recent  # noqa: E402

SERVICE = "local.xpsounds"
PATH = "/local/xpsounds"
WINDOW_VOLUME = 0.5  # same as the i3 window sounds
BALLOON_VOLUME = 0.5
APPLETS_RC = os.path.expanduser("~/.config/plasma-org.kde.plasma.desktop-appletsrc")
POPUP_FIX_MARKER = os.path.expanduser("~/.config/xp-sonicde-popup-fixed")
LAST_BOOT_FILE = os.path.expanduser("~/.cache/xp-theme/last-boot-id")


def login_sound():
    """Startup for the first login of this boot, Logon for later ones."""
    try:
        with open("/proc/sys/kernel/random/boot_id") as f:
            boot_id = f.read().strip()
    except OSError:
        return "Windows XP Startup.wav"
    try:
        with open(LAST_BOOT_FILE) as f:
            seen = f.read().strip() == boot_id
    except OSError:
        seen = False
    try:
        os.makedirs(os.path.dirname(LAST_BOOT_FILE), exist_ok=True)
        with open(LAST_BOOT_FILE, "w") as f:
            f.write(boot_id + "\n")
    except OSError:
        pass
    return "Windows XP Logon Sound.wav" if seen else "Windows XP Startup.wav"


class XPSounds(dbus.service.Object):
    @dbus.service.method(SERVICE, in_signature="s", out_signature="")
    def Play(self, file_name):
        name = os.path.basename(file_name)
        if os.path.isfile(os.path.join(SOUND_DIR, name)):
            play(name, WINDOW_VOLUME)


def on_message(_bus, message):
    """Play the balloon for a new notification that has no sound of its own."""
    try:
        if message.get_member() != "Notify" or message.get_interface() != "org.freedesktop.Notifications":
            return
        args = message.get_args_list()
        replaces_id, hints = int(args[1]), args[6]
    except Exception:
        return
    if replaces_id:
        return  # An update to a notification already shown.
    keys = [str(key) for key in hints.keys()]
    if any(key.startswith("x-kde") for key in keys):
        return  # A KDE notification; Plasma plays its sound.
    if any(key in ("sound-name", "sound-file", "suppress-sound") for key in keys):
        return
    if sound_was_recent():
        return  # Our scripts already played an XP sound for this.
    play("Windows XP Balloon.wav", BALLOON_VOLUME)


def start_notification_watch():
    try:
        monitor = dbus.bus.BusConnection(dbus.bus.BUS_SESSION)
        monitor.add_message_filter(on_message)
        monitor.call_blocking(
            "org.freedesktop.DBus", "/org/freedesktop/DBus",
            "org.freedesktop.DBus.Monitoring", "BecomeMonitor", "asu",
            (["type='method_call',interface='org.freedesktop.Notifications',member='Notify'"],
             dbus.UInt32(0)),
        )
        return monitor
    except dbus.DBusException as error:
        print(f"xp_sonicde: no balloon sounds: {error}", file=sys.stderr)
        return None


def device_notifier_groups():
    """Config groups of every Disks & Devices applet in the Plasma layout."""
    groups = []
    current = None
    try:
        with open(APPLETS_RC) as rc:
            for line in rc:
                line = line.strip()
                if line.startswith("["):
                    current = line
                elif line == "plugin=org.kde.plasma.devicenotifier" and current:
                    groups.append([part for part in current.strip("[]").split("][")])
    except OSError:
        pass
    return groups


def fix_device_popup():
    """Stop Plasma's device list popping open; XP AutoPlay handles new drives."""
    if os.path.exists(POPUP_FIX_MARKER):
        return False
    groups = device_notifier_groups()
    if not groups:
        return True  # Plasma hasn't written its layout yet; try again.
    for group in groups:
        command = ["kwriteconfig6", "--file", APPLETS_RC]
        for part in group + ["Configuration", "General"]:
            command += ["--group", part]
        command += ["--key", "popupOnNewDevice", "false"]
        subprocess.run(command, check=False)
    with open(POPUP_FIX_MARKER, "w") as marker:
        marker.write("popupOnNewDevice turned off\n")
    # Restart the panel once so the setting takes effect now.
    subprocess.Popen(["systemctl", "--user", "restart", "plasma-plasmashell.service"],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return False


def main():
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
    lock_file = open(os.path.join(runtime_dir, "xp_sonicde.lock"), "w")
    try:
        fcntl.flock(lock_file, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        return  # Already running.

    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    name = dbus.service.BusName(SERVICE, bus)  # noqa: F841 (keep the name)
    XPSounds(bus, PATH)

    if "--no-startup-sound" not in sys.argv:
        play(login_sound(), 1)
    monitor = start_notification_watch()  # noqa: F841 (keep the connection)
    # Wait 20 seconds so Plasma has written its panel layout first.
    GLib.timeout_add_seconds(20, fix_device_popup)
    GLib.MainLoop().run()


if __name__ == "__main__":
    main()
