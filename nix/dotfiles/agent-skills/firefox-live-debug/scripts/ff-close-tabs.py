#!/usr/bin/env python3
"""List or close live Firefox tabs by exact URL — including unloaded (discarded) tabs.

Talks to the 0-Custom - Tab Closer add-on (../tab-closer/) through its native-messaging
host, which listens on $XDG_RUNTIME_DIR/ff-tab-closer.sock while Firefox runs.
No restart or remote-debug mode needed.

Usage: ff-close-tabs.py {list|close} URL...
       ff-close-tabs.py close-at INDEX:URL...
close-at closes only the tab at that tab-strip index with that URL (skipped
if moved, or if two windows match), so duplicates of a URL survive.
Prints JSON: {"ok": true, "tabs": [{id, url, title, discarded, index,
windowId}, ...]} — for close/close-at, the tabs that were closed.
"""
import json
import os
import socket
import sys

if len(sys.argv) < 3 or sys.argv[1] not in ("list", "close", "close-at"):
    sys.exit(__doc__)
if sys.argv[1] == "close-at":
    try:
        targets = [{"index": int(i), "url": u}
                   for i, u in (a.split(":", 1) for a in sys.argv[2:])]
    except ValueError:
        sys.exit(__doc__)
    req = {"cmd": "closeAt", "targets": targets}
else:
    req = {"cmd": sys.argv[1], "urls": sys.argv[2:]}
sock = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "ff-tab-closer.sock")
s = socket.socket(socket.AF_UNIX)
try:
    s.connect(sock)
except OSError as e:
    sys.exit(f"error: can't reach {sock} ({e}) — is Firefox running with the "
             "0-Custom - Tab Closer add-on installed?")
s.sendall(json.dumps(req).encode() + b"\n")
reply = json.loads(s.makefile().readline())
print(json.dumps(reply, indent=1))
sys.exit(0 if reply.get("ok") else 1)
