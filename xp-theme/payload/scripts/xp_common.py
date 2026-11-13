"""Shared helpers for the Windows XP sound and notification scripts.

A sound played through notify() marks itself as recent, so sound.py skips
the generic balloon sound when the notification window then opens. That
way each event plays one sound, like Windows XP and KDE do.
"""

import os
import subprocess
import time

SOUND_DIR = "@HOME@/.local/share/sounds/windows-xp"
RUNTIME_DIR = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
RECENT_SOUND_FILE = os.path.join(RUNTIME_DIR, "xp-sound-recent")
# sound.py treats a notification within this many seconds as already sounded.
RECENT_SOUND_SECONDS = 2.0


def play_command(file_name, volume=1.0):
    return ["play", "-qV0", os.path.join(SOUND_DIR, file_name), "vol", str(volume)]


def mark_recent_sound():
    try:
        with open(RECENT_SOUND_FILE, "w") as marker:
            marker.write(str(time.time()))
    except OSError:
        pass


def sound_was_recent():
    try:
        return time.time() - os.path.getmtime(RECENT_SOUND_FILE) < RECENT_SOUND_SECONDS
    except OSError:
        return False


def play(file_name, volume=1.0):
    mark_recent_sound()
    try:
        subprocess.Popen(
            play_command(file_name, volume),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except OSError:
        pass


def notify(summary, body="", icon="", sound=None, urgency="normal", timeout_ms=None, replace_id=None):
    """Show a desktop notification, with an optional XP sound instead of the balloon."""
    if sound:
        play(sound)
    command = ["notify-send", "-a", "System", "-u", urgency]
    if icon:
        command += ["-i", icon]
    if timeout_ms is not None:
        command += ["-t", str(timeout_ms)]
    if replace_id is not None:
        command += ["-r", str(replace_id)]
    command += [summary]
    if body:
        command.append(body)
    try:
        subprocess.Popen(
            command,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except OSError:
        pass
