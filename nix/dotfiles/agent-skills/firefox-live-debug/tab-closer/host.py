#!/usr/bin/env python3
"""Native-messaging host: relays JSON requests from a Unix socket to the Tab Closer add-on."""
import json, os, socket, struct, sys, threading

SOCK = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "ff-tab-closer.sock")
pending, lock, out_lock = {}, threading.Lock(), threading.Lock()


def send(msg):
    data = json.dumps(msg).encode()
    with out_lock:
        sys.stdout.buffer.write(struct.pack("<I", len(data)) + data)
        sys.stdout.buffer.flush()


def read_ext():
    while hdr := sys.stdin.buffer.read(4):
        msg = json.loads(sys.stdin.buffer.read(struct.unpack("<I", hdr)[0]))
        with lock:
            slot = pending.pop(msg.get("rid"), None)
        if slot:
            slot["reply"] = msg
            slot["ev"].set()
    os._exit(0)  # Firefox closed the pipe


def serve(conn):
    with conn:
        req = json.loads(conn.makefile().readline())
        slot = {"ev": threading.Event()}
        rid = req["rid"] = os.urandom(8).hex()
        with lock:
            pending[rid] = slot
        send(req)
        reply = slot["reply"] if slot["ev"].wait(30) else {"ok": False, "error": "timeout"}
        conn.sendall(json.dumps(reply).encode() + b"\n")


threading.Thread(target=read_ext, daemon=True).start()
if os.path.exists(SOCK):
    os.unlink(SOCK)
srv = socket.socket(socket.AF_UNIX)
old = os.umask(0o177)  # socket 0600: only this user
srv.bind(SOCK)
os.umask(old)
srv.listen()
while True:
    threading.Thread(target=serve, args=(srv.accept()[0],), daemon=True).start()
