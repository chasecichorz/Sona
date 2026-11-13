// Windows XP window sounds for SonicDE (KWin X11 script).
// KWin scripts can't run programs, so this asks the xp_sonicde.py helper
// over D-Bus to play the sound. Same sounds as the i3 setup (sound.py):
// a window opening or being restored plays Restore, closing or
// minimizing plays Minimize.
const SERVICE = "local.xpsounds";
const PATH = "/local/xpsounds";

function play(file) {
    callDBus(SERVICE, PATH, SERVICE, "Play", file);
}

function wanted(w) {
    return w && (w.normalWindow || w.dialog) && !w.popupWindow && !w.notification;
}

function watch(w) {
    if (!wanted(w)) return;
    w.minimizedChanged.connect(function () {
        play(w.minimized ? "Windows XP Minimize.wav" : "Windows XP Restore.wav");
    });
}

workspace.windowList().forEach(watch);

workspace.windowAdded.connect(function (w) {
    if (!wanted(w)) return;
    play("Windows XP Restore.wav");
    watch(w);
});

workspace.windowRemoved.connect(function (w) {
    if (wanted(w)) play("Windows XP Minimize.wav");
});
