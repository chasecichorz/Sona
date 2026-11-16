#!/usr/bin/env python3
"""Drive a QEMU virtual machine over its serial port (a unix socket).

Used by scripts/live-boot-test.sh and scripts/interactive-install-test.sh.

    vm-serial.py SOCKET SCRIPT LOG

SCRIPT is a text file of steps, one per line:

    expect SECONDS REGEX        wait for REGEX in new serial output
    send TEXT                   type TEXT and Enter (\\n escapes allowed)
    sendraw TEXT                type TEXT without Enter
    sleep SECONDS
    # comment

Everything the VM prints is written to LOG. Exits 0 when every step
worked, 1 (and says which step) when an expect timed out.
"""
import re
import socket
import sys
import time


def main():
    sock_path, script_path, log_path = sys.argv[1:4]
    log = open(log_path, "ab", buffering=0)
    sock = None
    for _ in range(120):
        try:
            sock = socket.socket(socket.AF_UNIX)
            sock.connect(sock_path)
            break
        except OSError:
            sock.close()
            sock = None
            time.sleep(1)
    if sock is None:
        print("could not connect to", sock_path)
        return 1
    sock.settimeout(0.5)
    pending = b""

    def read_for(seconds):
        nonlocal pending
        end = time.time() + seconds
        while time.time() < end:
            try:
                data = sock.recv(65536)
            except socket.timeout:
                continue
            except OSError:
                return False
            if not data:
                return False
            log.write(data)
            pending += data
        return True

    def clean(data):
        text = data.decode("utf-8", "replace").replace("\r", "")
        return re.sub(r"\x1b\[[0-9;?]*[A-Za-z]|\x1b\][^\x07\x1b]*(\x07|\x1b\\)", "", text)

    for lineno, raw in enumerate(open(script_path), 1):
        line = raw.rstrip("\n")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        cmd, _, rest = line.partition(" ")
        if cmd == "expect":
            secs, _, pattern = rest.partition(" ")
            rx = re.compile(pattern)
            end = time.time() + float(secs)
            found = False
            while time.time() < end:
                m = rx.search(clean(pending))
                if m:
                    # Keep only what came after the match.
                    text = clean(pending)
                    pending = text[m.end():].encode()
                    found = True
                    break
                if not read_for(1):
                    break
            if not found:
                print(f"TIMEOUT at step {lineno}: expect {pattern!r}")
                return 1
            print(f"ok {lineno}: {pattern}")
        elif cmd in ("send", "sendraw"):
            text = rest.encode().decode("unicode_escape")
            if cmd == "send":
                text += "\n"
            sock.sendall(text.encode())
            read_for(0.3)
        elif cmd == "sleep":
            read_for(float(rest))
        else:
            print(f"bad step {lineno}: {line}")
            return 1
    read_for(2)
    return 0


if __name__ == "__main__":
    sys.exit(main())
