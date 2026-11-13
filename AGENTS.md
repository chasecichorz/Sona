# AGENTS.md — working on Sona Linux

Read this before changing anything. It is shared by every coding agent on
this project (Codex, Claude Code, and others), so keep it current: when you
finish a piece of work, update **Current state** and **Handoff log** below.

## The project and the person

Sona Linux is an accessible Arch Linux distribution for blind and low-vision
users. The maintainer, Chase, is blind and uses a screen reader. That shapes
everything:

- **Speech must never break.** Orca on the desktop, Speakup (espeakup) on the
  console. A change that can silence speech needs a test that proves it
  does not.
- **Write for a screen reader.** Plain sentences, no tables or ASCII art in
  messages to Chase, no "see the screenshot". Say exact key presses.
- **Explain in plain English** what you did and what is still untested.
  Never claim something works if you have not tested it.
- **Ask before anything destructive or outward-facing:** writing to a disk or
  USB stick, `git push`, merging to `main`, deleting branches, publishing a
  release. Committing locally on the working branch is fine when asked.
- Chase likes changes **batched before an ISO build** (a build takes 20+
  minutes). Make all the agreed changes, run the quick tests, then build once.

## Layout

- `Install` — the only installer (bash, ~2000 lines). It writes
  `setup-chroot.sh` from a quoted heredoc (`cat << 'EOF' > /mnt/root/setup-chroot.sh`)
  and runs it inside the new system. Answers go in via `/root/install.conf`.
- `# BEGIN SONA PACKAGES` / `# END SONA PACKAGES` block at the top of
  `Install` — **the single package list.** `scripts/build-iso.sh` and
  `scripts/quick-test.sh` read it. Add packages there, nowhere else.
- `sona-live/` — the archiso profile. `airootfs/` is the live system's files.
  `packages.x86_64` holds only live-ISO extras; build-iso.sh appends the
  SONA PACKAGES lists.
- `scripts/build-iso.sh` — builds `out/sona-*.iso` (about 4 GB) from a
  throwaway copy of the profile in `work-profile/`. Nothing generated is
  written into the git tree.
- `scripts/quick-test.sh` — fast installer test (see Testing).
- `scripts/ci-install-test.sh` — full VM install test (QEMU, UEFI or BIOS).
- `orca-bridge/` — Orca Bridge, Chase's fork of Orca Remote (NVDA Remote
  compatible). Built archive `remote.orca-ext` plus `sona-orca-extensions`,
  which installs and approves it (and wine-access's Orca extension).
  Refresh with `scripts/update-orca-bridge.sh ~/src/orca-remote`.
- `kokoro/` — Kokoro neural voices (Apache-2.0), Speech Dispatcher module
  `kokoro-generic`. The model ships on the ISO.
- `packages/openevv-git/` — PKGBUILD and updater for OpenEVV (IBM
  ViaVoice/Eloquence), the default voice. Built from source on each machine.
- `xp-theme/` — the Windows XP sound theme kit for SonicDE (on by default).
- `.github/workflows/build-and-release.yml` — lint, ISO build, VM install
  test, weekly releases.

## How the system works

- **Desktop:** SonicDE (X11 fork of KDE Plasma) on XLibre. Orca starts from
  `/etc/xdg/autostart/sona-orca.desktop`.
- **Login on installed systems:** no display manager. getty on tty1 (optional
  autologin, the drop-in needs `-o '-p -f -- \\u'`), then `~/.bash_profile`
  stops espeakup, runs `startx`, and restarts espeakup when X exits.
  `/etc/sudoers.d/20-sona-espeakup` allows that without a password.
- **Live ISO:** LightDM autologin as user `sona` (session `sonicde`). The
  "console with speech" boot entry passes `systemd.unit=multi-user.target`,
  because lightdm.service conflicts with getty@tty1.
- **Two install methods** (`INSTALL_METHOD`):
  - `copy` — from the Sona ISO. unsquashfs the live image to the disk, put
    back `/boot` from `/usr/share/sona/boot`, delete every file listed in
    `/usr/share/sona/live-files.txt`, remove the live user, make a new
    machine-id and pacman keyring, then run the normal setup. Works with no
    internet (`ONLINE=n`): updates, AUR apps and OpenEVV come later.
  - `download` — from a stock Arch ISO. pacstrap everything.
- **Repositories:** official Arch + `[xlibre-stable]`, `[sonicde-stable]`,
  `[stormux]` (signed) and `[jenux]` (unsigned). Keys are trusted only by
  exact fingerprint, and copies ship in `/usr/share/sona/keys`:
  SonicDE `A85BB166B49A4C58C39125073B87898C73F11DF5`,
  XLibre `0C92313001CFCA27627B9098B97F7C613F359424`,
  Stormux `52ADA49000F1FF0456F8AEEFB4CDE1CD56EF8E82`.
- **Orca extension approval:** Orca stores approvals in the *user's* dconf
  (`/org/gnome/orca/default/extensions/approved-user-extensions`, name →
  SHA-256 of the extension folder). A system dconf default does NOT work
  (Orca uses `get_user_value`). `sona-orca-extensions` writes it, and
  re-approves at login when files change.

## Licensing rules (do not break these)

- **Never put Windows XP sounds in the repo or a public ISO** (Microsoft's).
  They download from archive.org at first login. Private builds only:
  `SONA_BUNDLE_XP_SOUNDS=... scripts/build-iso.sh`.
- **Never ship OpenEVV prebuilt** (its language data is IBM's). It is built
  from source on each machine by `sona-openevv-update`.
- Google Chrome cannot be redistributed; it comes from the AUR when online,
  Firefox otherwise.

## Testing

Always run the quick tests after changing `Install` or the live profile.

    sudo scripts/quick-test.sh                    # download install, ~5 min
    sudo scripts/quick-test.sh --copy             # copy install, newest ISO in out/
    sudo scripts/quick-test.sh --copy --offline   # copy install with no network

They run the real `setup-chroot.sh` in an overlay container and print
PASS/FAIL checks. They skip partitioning and GRUB. For those, after building
an ISO:

    scripts/ci-install-test.sh out/sona-*.iso uefi
    scripts/ci-install-test.sh out/sona-*.iso bios

Also: `bash -n` and `shellcheck -S error` on every script you touch (the CI
lint step runs these). Pull the chroot script out with:
`sed -n "/^cat << 'EOF' > \/mnt\/root\/setup-chroot.sh$/,/^EOF$/p" Install | sed '1d;$d'`.

Gotchas we already hit:
- squashfs-tools 4.7.3 fails with xz ("xz uncompress failed ... code 9");
  the profile uses zstd.
- `/tmp` on Chase's laptop is a small RAM disk; keep VM disks and big files
  in `out/`.
- Inside a copy install, `/etc/resolv.conf` must exist as a file before
  arch-chroot, or DNS fails.
- Keys for repos already in the copied pacman.conf must be added before the
  first `pacman -Sy`.
- Do not `pkill -f` from a shell whose own command line matches the pattern.

## Git

- Work on the `sonicde` branch (not `main`). Do not push or merge without
  Chase saying so.
- Commit messages end with the attribution line your tool requires.
- `out/`, `work/` and `work-profile/` are build output and ignored.

## Current state (update this)

As of 2026-11-13:

- Branch `sonicde`: all of today's work, committed and pushed to
  github.com/chasecichorz/sona (branch `sonicde`). Not merged into `main`.
- Newest ISO: `out/sona-2026.11.13-x86_64.iso` (4.0 GB, built 13:49). Has
  everything below. **Not yet tested**: not booted, no VM install test.
- The USB stick (SanDisk) still has an older build whose installer has known
  bugs (no DNS in the copy install, keys added too late). Rewrite it with
  the new ISO before Chase installs on real hardware (ASUS TUF F16, NVIDIA).
- Quick tests before that build: download 53/53; copy online and offline
  passed except one check that only failed against the older ISO.

## Open tasks

1. Boot-test the new ISO in QEMU (`scripts/boot-sona-qemu.sh`, sound goes to
   Chase's speakers so he can listen), then run both VM install tests.
2. Investigate a build-log message: `error: stormux: key ... is unknown` /
   `keyring is not writable` (around line 3015 of the build log). The build
   finished and wine-access installed; find out where it comes from and
   whether the live system's pacman can sync Stormux.
3. Write the tested ISO to the USB stick (ask Chase first; confirm the device
   with `lsblk` — last time it was `/dev/sda`, SanDisk 3.2Gen1, 57 GB).
4. Chase asked: find some nice startup sounds to try, play them for him to
   choose from (never test with volume 0), and decide how they fit with the
   XP theme (which already plays XP Startup and Logon).
5. When Chase has pushed Orca Bridge to github.com/chasecichorz/orca-bridge,
   refresh `orca-bridge/` and point docs at it.
6. Merge `sonicde` into `main` or open a pull request, only when Chase says.
   Pushing to `main` starts the GitHub ISO build and VM install test.

## Handoff log (newest first; add a line when you stop)

- 2026-11-13, Claude Code: MATE → SonicDE, copy/offline install, Stormux +
  Jenux, OpenEVV default, Kokoro, Orca Bridge, wine-access, NVIDIA on ISO,
  quick-test.sh, AGENTS.md. Stopped after the 13:49 ISO build (untested).
