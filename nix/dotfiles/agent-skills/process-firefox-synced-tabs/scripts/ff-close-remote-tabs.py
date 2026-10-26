#!/usr/bin/env python3
# Queue CloseTab commands in a Firefox profile's synced-tabs.db.
#
#   ff-close-remote-tabs.py --device <guid-prefix> URL [URL ...]
#       queues a real close on the remote device (time_sent NULL — sent on next
#       flush, tab closes on the phone)
#   ff-close-remote-tabs.py --hide ...
#       same but time_sent set — row disappears from about:firefoxview, tab
#       stays open on the remote device
#   ff-close-remote-tabs.py --pending
#       list queued-but-unsent commands
#
# Send mechanics: the INSERT alone sends nothing. CommandQueue must have been
# instantiated this session (any "Send Tab to Device" click does it), then a
# flush trigger — reliable one is a Firefox restart (shutdown blocker sends all
# pending). Commands for devices off the FxA account are dropped unsent.
import os, sqlite3, sys, time

FF_BASE = os.environ.get("FF_BASE", os.path.expanduser("~/.mozilla/firefox"))
CLOSE_TAB = 0  # CommandKind::CloseTab — the only variant

def main():
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--profile", default="VERTEX")
    ap.add_argument("--device", help="guid prefix of the target device")
    ap.add_argument("--hide", action="store_true",
                    help="set time_sent: hide the row, never deliver to device")
    ap.add_argument("--pending", action="store_true",
                    help="list unsent commands and exit")
    ap.add_argument("urls", nargs="*")
    args = ap.parse_args()

    db = os.path.join(FF_BASE, args.profile, "synced-tabs.db")
    if not os.path.exists(db):
        sys.exit(f"error: {db} not found")
    con = sqlite3.connect(db, timeout=10)

    if args.pending:
        rows = con.execute(
            "SELECT device_id, url, time_requested FROM remote_tab_commands "
            "WHERE time_sent IS NULL").fetchall()
        for d, u, t in rows:
            print(f"{d[:8]}  {u}")
        print(f"{len(rows)} pending")
        return

    if not args.device or not args.urls:
        sys.exit("error: need --device <guid-prefix> and at least one URL")

    guids = [r[0] for r in con.execute("SELECT guid FROM tabs")]
    match = [g for g in guids if g.startswith(args.device)]
    if len(match) != 1:
        sys.exit(f"error: --device {args.device} matched {len(match)} "
                 f"records: {[g[:8] for g in match]}")
    guid = match[0]

    now = int(time.time() * 1000)
    sent = None if not args.hide else now
    for u in args.urls:
        con.execute(
            "INSERT OR IGNORE INTO remote_tab_commands "
            "(device_id, command, url, time_requested, time_sent) "
            "VALUES (?,?,?,?,?)", (guid, CLOSE_TAB, u, now, sent))
    con.commit()
    pending = con.execute(
        "SELECT count(*) FROM remote_tab_commands WHERE time_sent IS NULL"
    ).fetchone()[0]
    con.close()
    action = "queued hide" if args.hide else "queued close-on-device"
    print(f"{action} for {len(args.urls)} url(s) on {guid[:8]}; "
          f"{pending} unsent command(s) total")
    if not args.hide:
        print("note: send needs CommandQueue instantiated this session "
              "(any 'Send Tab to Device') + a flush — Firefox restart "
              "is the reliable trigger")

if __name__ == "__main__":
    main()
