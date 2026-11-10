#!/bin/bash
# Runs inside the live ISO during the automated install test. The live
# system downloads it from the test host because the kernel was started
# with script=http://10.0.2.2:8000/startup.sh (a built-in archiso feature).
# Everything is written to the serial port, which the test host records.

exec >/dev/ttyS0 2>&1
echo "SONA-CI: live system is up"
systemctl is-system-running --wait >/dev/null 2>&1 || true

if ! curl -fsS --retry 10 --retry-connrefused -o /tmp/answers.conf http://10.0.2.2:8000/answers.conf; then
    echo "SONA-CI: INSTALL FAILED (could not download answers)"
    poweroff
fi

if sona-install --unattended /tmp/answers.conf; then
    echo "SONA-CI: INSTALL OK"
else
    echo "SONA-CI: INSTALL FAILED (exit code $?)"
fi
sync
poweroff
