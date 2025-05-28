# SONA Linux ISO Script Bundle

This bundle contains all the scripts needed to build, validate, clean, and boot your custom SONA Linux ISO.

## Included Scripts

- `run-full-maintenance.sh` — Master automation script to run all other cleanup and validation steps
- `clean-packages.sh` — Removes invalid packages from packages.x86_64
- `clean-installer.sh` — Comments out unsupported package installs in the SONA installer script
- `check-main-repo-packages.sh` — Validates that all listed packages exist in Arch's official repos
- `debug.sh` — Safely rebuilds the ISO with proper working directories
- `boot-sona-qemu.sh` — Launches your built ISO in QEMU with audio/speech support

## How to Use

1. Extract this zip into your Arch build environment.
2. Place your ISO (if testing) as `sona-linux--x86_64.iso` in the same directory.
3. Run scripts in this order:

```bash
./run-full-maintenance.sh
./debug.sh
./boot-sona-qemu.sh
```

Happy hacking with SONA Linux 🎧🐧
