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
- `xp-theme/` — the Windows XP sound theme kit for SonicDE. **On by default**
  (Chase wants it as the default); the installer asks and Yes is selected,
  and the live ISO has it on too.
- `.github/workflows/build-and-release.yml` — lint, ISO build, VM install
  test, weekly releases.

## How the system works

- **Desktop:** SonicDE (X11 fork of KDE Plasma) on XLibre. Orca starts from
  `/etc/xdg/autostart/sona-orca.desktop`.
- **Login on installed systems:** no display manager. getty on tty1 (optional
  autologin, the drop-in needs `-o '-p -f -- \\u'`), then `~/.bash_profile`
  stops espeakup, runs `startx`, and restarts espeakup when X exits.
  `/etc/sudoers.d/20-sona-espeakup` allows that without a password.
- **Live ISO:** logs in like an installed system, no LightDM: getty@tty1 runs
  `/usr/local/bin/sona-live-getty`, which autologins `sona` (whose
  `~/.bash_profile` runs startx) or, with `sona.console` (the "console with
  speech" entry and the CI install test), root with the archiso automated
  script. archiso copies the image to RAM by itself when it fits
  (`copytoram=auto`); boot entries also offer `copytoram=y` and `copytoram=n`.
  Then the image is `/run/archiso/copytoram/airootfs.sfs` and the USB is
  unmounted; the installer handles both.
- **Installer UI:** plain text, inspired by the Stormux installer
  (`install-stormux` in git.stormux.org/storm/stormux): numbered menus
  (`ui_menu`), yes/no (`ui_yesno`, `ui_yesno_default_no`), typed YES for
  erasing (`ui_confirm_yes`), Ctrl+C quits. Prompts go to stderr because
  answers come back through `$(...)`; each `$(ask ...)` needs `|| exit 130`
  (command substitutions do not inherit errexit). All choices are made
  first, then a summary, then YES, then the disks change. Noisy output goes
  to `/var/log/sona-install.log`; the screen gets "Step N of 5" lines.
- **Installer features:** disk layouts `erase`, `erase_home`, `home_disk`,
  `existing`, `mounted`; extra users (`EXTRA_USERS` etc., created last from
  /etc/skel) with admin choice and `AUTOLOGIN_USER`; extras `GAME_MANAGER`,
  `AUDIOGAME_MANAGER` (git clones in /opt, group games, like Stormux),
  `STEAM`, `SSH`; the live user's Orca dconf settings are saved to
  `orca-settings.ini` and compiled into every new account (via
  `SONA_DCONF_EXTRA` in `sona-orca-extensions`); a sox chord at the end.
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
- Never `chown -R` (or `rm -rf`) over `out/` while a quick test or VM test may
  be running: `out/quick/run/root` has the host's `/dev`, `/sys`, pacman cache
  and `/etc/resolv.conf` mounted inside it. (This happened once on
  2026-11-13 and changed the owner of host device files.) Do not run a
  build and a quick test at the same time.
- SonicDE only registers `X-KDE-Shortcuts=` from menu files that are linked
  into `/usr/share/kglobalaccel/`. A shortcut in `/usr/share/applications`
  alone does nothing.
- The live ISO's installer is reachable three ways: Windows+Alt+I, the Start
  menu entry "Install Sona Linux" (`/usr/share/applications/sona-install.desktop`),
  and the desktop icon; it is also announced out loud after login. Keep all
  of them working. If the terminal-based installer ever stops being good
  enough, Chase is open to Calamares later, but not yet.

## Git

- Work on the `sonicde` branch (not `main`). Do not push or merge without
  Chase saying so.
- Commit messages end with the attribution line your tool requires.
- `out/`, `work/` and `work-profile/` are build output and ignored.

## Current state (update this)

Validation update, 2026-11-15:

- Existing November 13 ISO passed copy-online (82 checks), copy-offline
  (78), live USB (13), live RAM (16), interactive install (16), and full
  UEFI and BIOS install/desktop boot. BIOS rerun passed after reboot.
- Stormux key trust and repository sync passed in both live boot modes.
- Working directory contains uncommitted installer wording/clone timeout
  changes and the new interactive/live VM tests with parser regressions.
  No rebuilt ISO includes these working-directory edits yet.

Earlier build and release state, 2026-11-13:

- Merged into `main` and pushed once (commit 8d52184). **Chase asked to stop
  pushing to GitHub for now:** commit locally on `sonicde` only, no `git push`,
  until he says otherwise.
- Newest ISO: `out/sona-2026.11.13-x86_64.iso` (4.0 GB, built 15:12 from
  commit 8d799bd: XP on by default, quiet installer with "Step N of 5" status
  box, installer shortcut/Start menu entry). Written to the SanDisk USB stick
  and verified byte for byte. Not yet run: the full VM install tests.
- Chase is deciding which Stormux-installer ideas to adopt (plain numbered
  prompts, type YES to erase, several users, more disk layouts, game
  managers/Steam/SSH, carry over the live speech engine, summary + sound at
  the end) and wants the live ISO to log in like his laptop (tty1 autologin
  + startx, no LightDM) plus a "load into RAM" boot option.
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
6. Merge `sonicde` into `main` only when Chase says. Pushing to `main`
   starts the GitHub ISO build and VM install test (about two hours).

## Handoff log (newest first; add a line when you stop)

- 2026-11-16, Claude Code: Chase asked to push everything to main. Committed
  the installer wording/clone-timeout edits and the interactive/live VM tests
  (lint and the three regression tests pass), fast-forwarded main to sonicde
  and pushed both. A new local ISO build (out/sona-2026.11.16-x86_64.iso,
  includes these edits) was running at the time of the push; host needed
  python-pip installed for build-iso.sh.

- 2026-11-15, Codex: reran the approved BIOS validation command successfully.
  Although ordinary session inspection cannot see /dev/kvm, the approved
  execution path ran the VM successfully. Installation completed and the
  installed system reached both login and SonicDE; validation-bios.log
  records PASS. All pending existing-ISO validation is now complete. Updated
  Current state; no new ISO build, commit, push, or USB write performed.

- 2026-11-15, Codex, after reboot: recovered validation logs. Copy online
  passed 82/82, offline 78/78; live USB 13/13, RAM 16/16; interactive
  install 16/16; UEFI full install reached login and SonicDE and passed.
  Live checks include Orca running, extension approval, installer shortcut,
  Stormux key trust and syncing all repositories. BIOS validation was
  interrupted during initial mirror selection; no final result. No QEMU
  process remains. This agent session still has no /dev/kvm. Re-ran three
  Python regression checks, bash -n and shellcheck -S error successfully.
  Next: rerun BIOS validation from the host terminal. These results apply
  to the existing November 13 ISO; no new build, USB write or push performed.

- 2026-11-15, Codex: resumed on desktop. Postroom comparison: current
  ~/email/postroom is clean at 663cccd, three commits ahead of clean laptop
  copy at 1c7eec4; no laptop-only commits or uncommitted changes. Fixed
  interactive /home fstab check to parse whitespace-delimited fields (the
  old literal spaces reject genfstab tabs; installer bug is not established).
  Fixed live test: explicit Bash shell, anchored completion markers to avoid
  matching command echo, newline-delimited named results, exact expected
  count (13 USB/16 RAM), explicit copytoram=n for USB, mode validation.
  Serial driver now clears failed socket connections. Three local regression
  checks in tests/test_vm_checks.py pass; bash -n and shellcheck -S error
  pass for Install and both test scripts. Existing Install edits preserved.
  VM/quick tests NOT rerun: agent environment has no /dev/kvm and sudo is
  blocked by no-new-privileges (also reports sudo.conf owned by 65534).
  Run privileged validation from the host terminal. No ISO build, commit,
  push, host configuration change, or USB write performed.

- 2026-11-14, Claude Code: **work moved to Chase's desktop** (192.168.4.30,
  Core Ultra 7 265F, 32 GB; the laptop is being wiped). Project in `~/src/sona`
  there, rest of the laptop home in `~/laptop-home`, laptop system files
  (/etc, /opt, /root, /boot, /usr/local) in `~/laptop-system`, package and
  service lists in `~/laptop-home/laptop-info`. Desktop has passwordless sudo,
  qemu, archiso and the test tools. Results of the 22:32 ISO tests (not yet
  in Current state): copy-online quick test 83/83; copy-offline did not run
  (umount busy); interactive VM install 15/16, FAIL "/home is mounted from
  its own partition at boot" (likely missing from fstab: fix next); live
  boot tests usb/ram print "CHECK FAIL" with empty names (test-script result
  parsing bug); full UEFI VM test was interrupted. Uncommitted: Install
  (Wi-Fi prompt wording, timeout on game-manager git clone) and new
  scripts interactive-install-test.sh, live-boot-test.sh, vm-serial.py.

- 2026-11-13, Claude Code: quiet installer status box, XP default on again,
  15:12 ISO written to USB; studied the Stormux installer.
- 2026-11-13, Claude Code: XP sounds made optional (default No), merged to
  main, kglobalaccel links for Sona shortcuts, ISO rebuilt for the USB.
- 2026-11-13, Claude Code: MATE → SonicDE, copy/offline install, Stormux +
  Jenux, OpenEVV default, Kokoro, Orca Bridge, wine-access, NVIDIA on ISO,
  quick-test.sh, AGENTS.md. Stopped after the 13:49 ISO build (untested).
