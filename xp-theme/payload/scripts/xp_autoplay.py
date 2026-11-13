#!/usr/bin/env python3
"""Windows XP style AutoPlay and drive automounting for i3.

The automount rules follow KDE Plasma's device automounter: when a
removable drive, memory card, phone, camera, or disc is attached, mount it
right away, but leave alone drives that were already there at login and
system disks. Messages follow KDE's device notifier and XP's balloons.

Once a device is mounted, its files are checked and an AutoPlay window asks
what to do: play music, play videos, view or copy pictures, open the folder,
or take no action. "Always do the selected action" remembers the choice for
that kind of content, like XP did.

Usage:
  xp_autoplay.py                  run the background service (from i3)
  xp_autoplay.py --safely-remove  choose a device to stop and eject
  xp_autoplay.py --autoplay       show AutoPlay again for a mounted device
  xp_autoplay.py --reset          forget every "Always do this" choice
"""

import fcntl
import json
import mimetypes
import os
import shutil
import subprocess
import sys
import threading
import time
from datetime import date

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gio, GLib, Gtk  # noqa: E402

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from xp_common import notify, play  # noqa: E402

CONFIG_DIR = os.path.expanduser("~/.config/xp-autoplay")
CHOICES_FILE = os.path.join(CONFIG_DIR, "choices.json")
# Dolphin under SonicDE (KDE), Thunar under i3.
FILE_MANAGER = "dolphin" if "KDE" in os.environ.get("XDG_CURRENT_DESKTOP", "") else "thunar"
PICTURES_DIR = os.path.expanduser("~/Pictures")
SCAN_DEPTH = 3
SCAN_FILE_LIMIT = 4000
SCAN_SECONDS = 6

# Extra types Python's mimetypes table may not know
EXTRA_TYPES = {
    ".flac": "audio/flac", ".opus": "audio/ogg", ".ogg": "audio/ogg", ".m4a": "audio/mp4",
    ".aac": "audio/aac", ".wma": "audio/x-ms-wma", ".mka": "audio/x-matroska",
    ".mkv": "video/x-matroska", ".webm": "video/webm", ".m4v": "video/mp4",
    ".wmv": "video/x-ms-wmv", ".flv": "video/x-flv", ".3gp": "video/3gpp",
    ".heic": "image/heic", ".webp": "image/webp", ".nef": "image/x-nikon-nef",
    ".cr2": "image/x-canon-cr2", ".dng": "image/x-adobe-dng", ".arw": "image/x-sony-arw",
}

CONTENT_TEXT = {
    "music": "music files",
    "video": "video files",
    "pictures": "pictures",
    "mixed": "more than one type of content",
    "audio-cd": "an audio CD",
    "video-dvd": "a video DVD",
    "files": "files and folders",
    "blank": "a blank disc",
}

# Volume names the system adds that should never pop up AutoPlay
SKIP_SCHEMES = {"computer", "network", "trash", "recent", "burn"}


def content_kind_of_file(name):
    extension = os.path.splitext(name)[1].lower()
    mime = EXTRA_TYPES.get(extension) or mimetypes.guess_type(name)[0] or ""
    return mime.split("/", 1)[0]


def scan_files(root):
    """Count music, video and picture files near the top of a device."""
    counts = {"audio": 0, "video": 0, "image": 0, "other": 0}
    pictures = []
    started = time.monotonic()
    seen = 0
    root_depth = root.rstrip(os.sep).count(os.sep)
    for folder, folders, files in os.walk(root):
        if folder.count(os.sep) - root_depth >= SCAN_DEPTH:
            folders[:] = []
        folders[:] = [name for name in folders if not name.startswith(".")]
        for name in files:
            kind = content_kind_of_file(name)
            if kind in counts:
                counts[kind] += 1
                if kind == "image":
                    pictures.append(os.path.join(folder, name))
            else:
                counts["other"] += 1
            seen += 1
        if seen >= SCAN_FILE_LIMIT or time.monotonic() - started > SCAN_SECONDS:
            break
    return counts, pictures


def kind_from_counts(counts):
    found = [kind for kind in ("audio", "video", "image") if counts[kind]]
    if len(found) > 1:
        return "mixed"
    if found:
        return {"audio": "music", "video": "video", "image": "pictures"}[found[0]]
    return "files"


def load_choices():
    try:
        with open(CHOICES_FILE) as choices_file:
            return json.load(choices_file)
    except (OSError, ValueError):
        return {}


def save_choice(kind, action_id):
    choices = load_choices()
    choices[kind] = action_id
    os.makedirs(CONFIG_DIR, exist_ok=True)
    with open(CHOICES_FILE, "w") as choices_file:
        json.dump(choices, choices_file, indent=2)


def default_app(mime):
    app = Gio.AppInfo.get_default_for_type(mime, False)
    return app


def app_label(app, fallback):
    return app.get_display_name() if app else fallback


def launch(command):
    try:
        subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)
        return True
    except OSError:
        return False


def launch_app(app, uris):
    try:
        app.launch_uris(uris, None)
        return True
    except GLib.Error:
        return False


def mount_name(mount):
    name = mount.get_name()
    volume = mount.get_volume()
    device = volume.get_identifier("unix-device") if volume else None
    if device:
        return f"{name} ({os.path.basename(device)})"
    return name


def is_removable_mount(mount):
    """Removable devices only, never the system's own disks."""
    if mount.is_shadowed():
        return False
    root = mount.get_root()
    if root.get_uri_scheme() in SKIP_SCHEMES:
        return False
    drive = mount.get_drive()
    if drive is not None:
        return drive.is_removable() or drive.is_media_removable() or drive.can_eject()
    # Phones and cameras from gvfs have no drive but can be unmounted
    return mount.can_unmount() or mount.can_eject()


class AutoPlay:
    """Builds the AutoPlay choices for one mounted device."""

    def __init__(self, mount, content_types):
        self.mount = mount
        self.name = mount_name(mount)
        root = mount.get_root()
        self.path = root.get_path()
        self.uri = root.get_uri()
        volume = mount.get_volume()
        self.device = volume.get_identifier("unix-device") if volume else None
        self.content_types = content_types or []
        self.pictures = []
        self.kind = "files"

    def detect(self):
        types = self.content_types
        if "x-content/audio-cdda" in types:
            self.kind = "audio-cd"
        elif "x-content/video-dvd" in types or "x-content/video-bluray" in types:
            self.kind = "video-dvd"
        elif "x-content/blank-cd" in types or "x-content/blank-dvd" in types:
            self.kind = "blank"
        elif self.path:
            counts, self.pictures = scan_files(self.path)
            self.kind = kind_from_counts(counts)
            if "x-content/image-dcf" in types and counts["image"]:
                self.kind = "pictures"

    def actions(self):
        """List of (action id, label) pairs, best first."""
        actions = []
        audio_app = default_app("audio/mpeg")
        video_app = default_app("video/mp4")
        image_app = default_app("image/jpeg")
        if self.kind == "audio-cd":
            actions.append(("play-cd", f"Play audio CD using {app_label(audio_app, 'VLC')}"))
        if self.kind == "video-dvd":
            actions.append(("play-dvd", f"Play DVD movie using {app_label(video_app, 'VLC')}"))
        if self.kind in ("music", "mixed") and audio_app:
            actions.append(("play-music", f"Play music using {app_label(audio_app, '')}"))
        if self.kind in ("video", "mixed") and video_app:
            actions.append(("play-video", f"Play videos using {app_label(video_app, '')}"))
        if self.kind in ("pictures", "mixed") and self.pictures:
            actions.append(("copy-pictures", "Copy pictures to my Pictures folder"))
            if image_app:
                actions.append(("view-pictures", f"View pictures using {app_label(image_app, '')}"))
        if self.path:
            actions.append(("open-folder", "Open folder to view files using File Manager"))
        actions.append(("nothing", "Take no action"))
        return actions

    def run(self, action_id):
        if action_id == "play-cd":
            app = default_app("audio/mpeg")
            target = f"cdda://{self.device}" if self.device else "cdda://"
            launch(["vlc", target]) if shutil.which("vlc") else launch_app(app, [target])
        elif action_id == "play-dvd":
            target = f"dvd://{self.device}" if self.device else "dvd://"
            launch(["vlc", target]) if shutil.which("vlc") else launch_app(
                default_app("video/mp4"), [target])
        elif action_id == "play-music":
            launch_app(default_app("audio/mpeg"), [self.uri])
        elif action_id == "play-video":
            launch_app(default_app("video/mp4"), [self.uri])
        elif action_id == "view-pictures":
            uris = [Gio.File.new_for_path(path).get_uri() for path in self.pictures[:200]]
            launch_app(default_app("image/jpeg"), uris)
        elif action_id == "copy-pictures":
            threading.Thread(target=self.copy_pictures, daemon=True).start()
        elif action_id == "open-folder":
            if shutil.which(FILE_MANAGER):
                launch([FILE_MANAGER, self.path])
            else:
                launch(["xdg-open", self.path])

    def copy_pictures(self):
        label = self.mount.get_name().replace("/", "-")
        target = os.path.join(PICTURES_DIR, f"{date.today().isoformat()} {label}")
        os.makedirs(target, exist_ok=True)
        notify("Copying Pictures", f"Copying {len(self.pictures)} pictures from {self.name} "
               f"to {target}.", "camera-photo")
        copied = 0
        failed = 0
        for source in self.pictures:
            destination = os.path.join(target, os.path.basename(source))
            base, extension = os.path.splitext(destination)
            number = 1
            while os.path.exists(destination):
                if os.path.getsize(destination) == os.path.getsize(source):
                    break
                destination = f"{base} ({number}){extension}"
                number += 1
            if os.path.exists(destination):
                continue
            try:
                shutil.copy2(source, destination)
                copied += 1
            except OSError:
                failed += 1
        problem = f" {failed} could not be copied." if failed else ""
        notify("Pictures Copied", f"Copied {copied} pictures to {target}.{problem}",
               "folder-pictures", sound="Windows XP Notify.wav")


class AutoPlayDialog(Gtk.Dialog):
    def __init__(self, autoplay, allow_always=True):
        super().__init__(title=f"{autoplay.name} - AutoPlay")
        self.autoplay = autoplay
        self.set_default_size(460, -1)
        self.set_keep_above(True)
        self.set_position(Gtk.WindowPosition.CENTER)
        box = self.get_content_area()
        box.set_spacing(8)
        box.set_border_width(12)

        kind_text = CONTENT_TEXT.get(autoplay.kind, "files")
        intro = Gtk.Label(label=f"This disk or device contains {kind_text}.\n"
                                "What do you want to do?")
        intro.set_xalign(0)
        intro.set_line_wrap(True)
        box.pack_start(intro, False, False, 0)

        self.buttons = []
        group = None
        for action_id, label in autoplay.actions():
            button = Gtk.RadioButton.new_with_label_from_widget(group, label)
            group = group or button
            button.action_id = action_id
            box.pack_start(button, False, False, 0)
            self.buttons.append(button)
        self.buttons[0].set_active(True)

        self.always = Gtk.CheckButton(label="Always do the selected action")
        if allow_always and autoplay.kind not in ("blank",):
            box.pack_start(self.always, False, False, 4)

        self.add_button("_Cancel", Gtk.ResponseType.CANCEL)
        ok_button = self.add_button("_OK", Gtk.ResponseType.OK)
        ok_button.set_can_default(True)
        self.set_default_response(Gtk.ResponseType.OK)
        self.connect("key-press-event", self.on_key)
        self.connect("response", self.on_response)
        self.show_all()
        self.buttons[0].grab_focus()
        self.present_with_time(GLib.get_monotonic_time() // 1000)

    def on_key(self, _widget, event):
        from gi.repository import Gdk
        if event.keyval in (Gdk.KEY_Return, Gdk.KEY_KP_Enter):
            self.response(Gtk.ResponseType.OK)
            return True
        return False

    def selected_action(self):
        for button in self.buttons:
            if button.get_active():
                return button.action_id
        return "nothing"

    def on_response(self, _dialog, response):
        if response == Gtk.ResponseType.OK:
            action_id = self.selected_action()
            if self.always.get_active():
                save_choice(self.autoplay.kind, action_id)
            self.autoplay.run(action_id)
        self.destroy()


def show_autoplay(mount, content_types, use_saved_choice=True, on_done=None):
    """Scan a mount in the background, then run the saved choice or ask."""
    autoplay = AutoPlay(mount, content_types)

    def scanned():
        if autoplay.kind == "blank":
            notify("Blank Disc", f"{autoplay.name} is a blank disc.", "media-optical")
            if on_done:
                on_done()
            return False
        saved = load_choices().get(autoplay.kind) if use_saved_choice else None
        valid = {action_id for action_id, _label in autoplay.actions()}
        if saved in valid:
            autoplay.run(saved)
            if on_done:
                on_done()
            return False
        dialog = AutoPlayDialog(autoplay)
        if on_done:
            dialog.connect("destroy", lambda _widget: on_done())
        return False

    def scan():
        autoplay.detect()
        GLib.idle_add(scanned)

    threading.Thread(target=scan, daemon=True).start()


class ChooseDeviceDialog(Gtk.Dialog):
    """A plain list of devices, used for Safely Remove and AutoPlay."""

    def __init__(self, title, text, mounts, button_label, on_chosen):
        super().__init__(title=title)
        self.on_chosen = on_chosen
        self.set_default_size(420, -1)
        self.set_keep_above(True)
        self.set_position(Gtk.WindowPosition.CENTER)
        box = self.get_content_area()
        box.set_spacing(8)
        box.set_border_width(12)
        label = Gtk.Label(label=text)
        label.set_xalign(0)
        label.set_line_wrap(True)
        box.pack_start(label, False, False, 0)
        self.buttons = []
        group = None
        for mount in mounts:
            button = Gtk.RadioButton.new_with_label_from_widget(group, mount_name(mount))
            group = group or button
            button.mount = mount
            box.pack_start(button, False, False, 0)
            self.buttons.append(button)
        self.buttons[0].set_active(True)
        self.add_button("_Close", Gtk.ResponseType.CANCEL)
        self.add_button(button_label, Gtk.ResponseType.OK)
        self.set_default_response(Gtk.ResponseType.OK)
        self.connect("key-press-event", self.on_key)
        self.connect("response", self.on_response)
        self.show_all()
        self.buttons[0].grab_focus()
        self.present_with_time(GLib.get_monotonic_time() // 1000)

    def on_key(self, _widget, event):
        from gi.repository import Gdk
        if event.keyval in (Gdk.KEY_Return, Gdk.KEY_KP_Enter):
            self.response(Gtk.ResponseType.OK)
            return True
        return False

    def on_response(self, _dialog, response):
        chosen = None
        if response == Gtk.ResponseType.OK:
            chosen = next(button.mount for button in self.buttons if button.get_active())
        self.destroy()
        self.on_chosen(chosen)


def safely_remove(mount, on_done):
    name = mount_name(mount)
    operation = Gio.MountOperation()

    def finished(source, result, eject):
        try:
            if eject:
                source.eject_with_operation_finish(result)
            else:
                source.unmount_with_operation_finish(result)
            notify("Safe To Remove Hardware",
                   f"The '{name}' device can now be safely removed from the system.",
                   "drive-removable-media")
        except GLib.Error as error:
            busy = "busy" in error.message.lower()
            reason = ("Close any programs or windows that might be using it, then try again."
                      if busy else error.message)
            notify("Problem Ejecting Device", f"The device '{name}' cannot be stopped right now. "
                   f"{reason}", "dialog-error", sound="Windows XP Error.wav")
        on_done()

    SafeRemoval.expected.add(mount_key(mount))
    if mount.can_eject():
        mount.eject_with_operation(Gio.MountUnmountFlags.NONE, operation, None,
                                   finished, True)
    else:
        mount.unmount_with_operation(Gio.MountUnmountFlags.NONE, operation, None,
                                     finished, False)


def mount_key(mount):
    return mount.get_root().get_uri()


class SafeRemoval:
    # Mounts the user asked to remove, so their removal is not "unsafe".
    # Shared through a file because --safely-remove runs as its own process.
    expected = set()
    marker = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "xp-autoplay-removing")

    @classmethod
    def remember(cls, key):
        try:
            with open(cls.marker, "a") as marker:
                marker.write(f"{time.time()} {key}\n")
        except OSError:
            pass

    @classmethod
    def was_expected(cls, key):
        if key in cls.expected:
            return True
        try:
            with open(cls.marker) as marker:
                for line in marker:
                    stamp, _, uri = line.rstrip("\n").partition(" ")
                    if uri == key and time.time() - float(stamp) < 120:
                        return True
        except (OSError, ValueError):
            pass
        return False


def removable_mounts(monitor):
    return [mount for mount in monitor.get_mounts() if is_removable_mount(mount)]


class AutomountService:
    def __init__(self):
        self.monitor = Gio.VolumeMonitor.get()
        # Like KDE, leave alone anything that was already attached at login.
        self.known_volumes = {self.volume_key(volume) for volume in self.monitor.get_volumes()}
        self.mounting = set()
        self.autoplay_mounts = set()
        self.mounted_uris = {mount_key(m) for m in self.monitor.get_mounts()}
        self.monitor.connect("volume-added", self.on_volume_added)
        self.monitor.connect("mount-added", self.on_mount_added)
        self.monitor.connect("mount-removed", self.on_mount_removed)
        self.monitor.connect("drive-disconnected", self.on_drive_disconnected)
        self.monitor.connect("volume-removed", self.on_volume_removed)
        self.removed_drives = {}

    @staticmethod
    def volume_key(volume):
        return (volume.get_identifier("unix-device") or volume.get_identifier("uuid")
                or volume.get_name())

    def on_volume_added(self, _monitor, volume):
        key = self.volume_key(volume)
        if key in self.known_volumes:
            return
        self.known_volumes.add(key)
        if volume.get_mount() is not None:
            return
        if not (volume.should_automount() and volume.can_mount()):
            notify("New Device", f"{volume.get_name()} was connected.",
                   "drive-removable-media")
            return
        self.mounting.add(key)
        volume.mount(Gio.MountMountFlags.NONE, Gio.MountOperation(), None,
                     self.on_mounted, key)

    def on_mounted(self, volume, result, key):
        self.mounting.discard(key)
        try:
            volume.mount_finish(result)
        except GLib.Error as error:
            if error.matches(Gio.io_error_quark(), Gio.IOErrorEnum.FAILED_HANDLED):
                return
            notify("Could Not Open Device",
                   f"{volume.get_name()} could not be mounted: {error.message}",
                   "dialog-error", sound="Windows XP Hardware Fail.wav")

    def on_mount_added(self, _monitor, mount):
        key = mount_key(mount)
        if key in self.mounted_uris:
            return
        self.mounted_uris.add(key)
        if not is_removable_mount(mount):
            return
        notify("Device Ready", f"{mount_name(mount)} is ready to use.",
               "drive-removable-media", timeout_ms=5000)
        mount.guess_content_type(False, None, self.on_content_guessed, None)

    def on_content_guessed(self, mount, result, _data):
        try:
            content_types = mount.guess_content_type_finish(result)
        except GLib.Error:
            content_types = []
        show_autoplay(mount, content_types)

    def on_mount_removed(self, _monitor, mount):
        key = mount_key(mount)
        self.mounted_uris.discard(key)
        drive = mount.get_drive()
        if drive is not None:
            self.removed_drives[drive.get_name()] = (key, mount_name(mount), time.monotonic())

    def on_drive_disconnected(self, _monitor, drive):
        # Pulled out while still mounted, without Safely Remove first
        record = self.removed_drives.pop(drive.get_name(), None)
        if record is None:
            return
        key, name, removed_at = record
        if time.monotonic() - removed_at > 3 or SafeRemoval.was_expected(key):
            return
        notify("Unsafe Removal of Device",
               f"{name} was removed without stopping it first. Next time, use Safely "
               "Remove Hardware before unplugging it, or some files may not be saved.",
               "dialog-warning")

    def on_volume_removed(self, _monitor, volume):
        self.known_volumes.discard(self.volume_key(volume))


def run_safely_remove():
    monitor = Gio.VolumeMonitor.get()
    mounts = removable_mounts(monitor)
    if not mounts:
        notify("Safely Remove Hardware", "There are no removable devices to stop.",
               "drive-removable-media")
        return

    def chosen(mount):
        if mount is None:
            Gtk.main_quit()
            return
        SafeRemoval.remember(mount_key(mount))
        safely_remove(mount, Gtk.main_quit)

    ChooseDeviceDialog("Safely Remove Hardware",
                       "Select the device you want to unplug or eject, then choose Stop. "
                       "You will be told when it is safe to remove it.",
                       mounts, "_Stop", chosen)
    Gtk.main()


def run_autoplay_again():
    monitor = Gio.VolumeMonitor.get()
    mounts = removable_mounts(monitor)
    if not mounts:
        notify("AutoPlay", "No removable devices are mounted.", "drive-removable-media")
        return

    def start(mount):
        if mount is None:
            Gtk.main_quit()
            return

        def guessed(source, result, _data):
            try:
                content_types = source.guess_content_type_finish(result)
            except GLib.Error:
                content_types = []
            show_autoplay(source, content_types, use_saved_choice=False,
                          on_done=Gtk.main_quit)

        mount.guess_content_type(False, None, guessed, None)

    if len(mounts) == 1:
        start(mounts[0])
    else:
        ChooseDeviceDialog("AutoPlay", "Choose the device to run AutoPlay for.",
                           mounts, "_OK", start)
    Gtk.main()


def main():
    arguments = sys.argv[1:]
    if "--reset" in arguments:
        try:
            os.remove(CHOICES_FILE)
        except OSError:
            pass
        notify("AutoPlay", "AutoPlay will ask again for every kind of device.")
        return
    if "--safely-remove" in arguments:
        run_safely_remove()
        return
    if "--autoplay" in arguments:
        run_autoplay_again()
        return

    runtime_dir = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
    lock_file = open(os.path.join(runtime_dir, "xp_autoplay.lock"), "w")
    try:
        fcntl.flock(lock_file, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        return  # Already running.
    service = AutomountService()  # noqa: F841 - kept alive by the main loop
    Gtk.main()


if __name__ == "__main__":
    main()
