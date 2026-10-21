"""Shared helpers for scrub-transcripts.sh and report-exposed-secrets.sh.

Both scripts embed their python via heredoc and import this module with
`sys.path.insert(0, os.environ["DIR"])` so the copy baked into the nix store
works the same as the repo checkout.
"""

import json
import os
import sqlite3
import subprocess

LIVE_WINDOW_S = 300  # files/DBs touched in the last 5 min are skipped


def gitleaks_scan(conf, target, frag, scan_errors, redact=False):
    """Run `gitleaks dir` over target (a file or a dir of dumped blobs) and
    return the findings list, or None on scan error (recorded in scan_errors;
    the caller must leave state for that target untouched)."""
    if os.path.exists(frag):
        os.remove(frag)
    cmd = [
        "gitleaks", "dir", "--config", conf, "--no-banner",
        "--exit-code", "0", "--report-format", "json",
        "--report-path", frag,
    ]
    if redact:
        cmd.append("--redact")
    cmd.append(target)
    r = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                       text=True, check=False)
    if r.returncode != 0:
        scan_errors.append(
            f"{target}: gitleaks exited {r.returncode}: {r.stderr.strip()[:200]}")
        return None
    try:
        return json.load(open(frag))
    except Exception as e:
        scan_errors.append(f"{target}: unreadable gitleaks report: {e}")
        return None


def collect_targets(file_targets, state, full):
    """Walk file_targets and return (to_scan, seen): files needing a gitleaks
    pass (uncached, changed mtime/size, still carrying findings, or --full)
    plus every file seen under the roots for state pruning."""
    seen, to_scan = set(), []
    for root in file_targets:
        paths = [root] if os.path.isfile(root) else (
            os.path.join(d, f) for d, _ds, fs in os.walk(root) for f in fs)
        for p in paths:
            if not os.path.isfile(p):
                continue
            try:
                st = os.stat(p)
            except OSError:
                continue
            seen.add(p)
            ent = state.get(p)
            if full or not ent or ent["mtime"] != st.st_mtime \
               or ent["size"] != st.st_size or ent.get("findings"):
                to_scan.append(p)
    return to_scan, seen


def prune_state(state, file_targets, db_targets, seen):
    """Drop state entries for files/DBs that no longer exist — but only inside
    the roots and DBs targeted this run, so a partial run must not wipe entries
    belonging to other stores."""
    prune_roots = [os.path.realpath(r) for r in file_targets]
    for k in [k for k in list(state)
              if k not in seen and not k.startswith("sqlite://")
              and any(os.path.realpath(k) == r
                      or os.path.realpath(k).startswith(r + os.sep)
                      for r in prune_roots)]:
        del state[k]
    db_prune = {os.path.realpath(d) for d in db_targets}
    for k in [k for k in list(state)
              if k.startswith("sqlite://")
              and os.path.realpath(k[len("sqlite://"):]) in db_prune
              and not os.path.exists(k[len("sqlite://"):])]:
        del state[k]


def db_recently_modified(db, now):
    """Live-session guard for WAL sqlite DBs (used under --full too).
    Writes land in <db>-wal, so check the newest of db/-wal. -shm is excluded:
    its mtime moves on plain reads (including our own and cass's indexer), which
    would skip the db forever. An empty -wal means everything is already
    checkpointed into the main db, so it doesn't count as live either."""
    wal = db + "-wal"
    db_mtime = max(
        (os.path.getmtime(f) for f in (db, wal) if os.path.exists(f)),
        default=0)
    if os.path.exists(wal) and os.path.getsize(wal) == 0:
        db_mtime = os.path.getmtime(db)
    return now - db_mtime < LIVE_WINDOW_S


def dump_sqlite_rows(db, dump_dir, hwm, dirty_rows):
    """Dump candidate opencode v1 rows to dump_dir as '<table>--<id>' files:
    message/part rows with time_updated newer than hwm, plus rows still marked
    dirty. Returns (row_keys {dump_file: (table, id)}, new_hwm).
    Raises sqlite3.Error on connect failure."""
    con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    try:
        os.makedirs(dump_dir, exist_ok=True)
        new_hwm = hwm
        row_keys = {}
        for table in ("message", "part"):
            try:
                cur = con.execute(
                    f"select id, time_updated, data from {table} "
                    f"where time_updated > ?", (hwm,))
            except sqlite3.Error:
                continue
            for rid, tupd, data in cur.fetchall():
                ts = tupd or 0
                if ts > new_hwm:
                    new_hwm = ts
                fn = os.path.join(dump_dir, f"{table}--{rid}")
                with open(fn, "w") as fh:
                    fh.write(data or "")
                row_keys[fn] = (table, rid)
        for table, rid in dirty_rows:
            try:
                r = con.execute(f"select data from {table} where id = ?",
                                (rid,)).fetchone()
            except sqlite3.Error:
                r = None
            if r:
                fn = os.path.join(dump_dir, f"{table}--{rid}")
                with open(fn, "w") as fh:
                    fh.write(r[0] or "")
                row_keys[fn] = (table, rid)
    finally:
        con.close()
    return row_keys, new_hwm


def dump_cass_convs(cass_db, dump_dir, chwm, cdirty):
    """Dump messages.content per conversation in the cass archive to
    dump_dir as 'conv--<id>' files: conversations newer than chwm (on
    conversations.last_message_created_at) or marked dirty. Conversations are
    grouped by source_path — several convs can share one path (e.g. copilot's
    events.jsonl), and if it's flagged all of its convs are re-scanned.
    Returns (conv_files {dump_file: source_path}, new_chwm).
    Raises sqlite3.Error on connect failure."""
    con = sqlite3.connect(f"file:{cass_db}?mode=ro", uri=True)
    try:
        convs = {}  # source_path -> newest last_message_created_at
        new_chwm = chwm
        for cid, spath, lmc in con.execute(
                "select id, source_path, last_message_created_at "
                "from conversations"):
            ts = lmc or 0
            if ts <= chwm and spath not in cdirty:
                continue
            if ts > new_chwm:
                new_chwm = ts
            convs[spath] = ts
        os.makedirs(dump_dir, exist_ok=True)
        conv_files = {}
        for cid, spath in con.execute(
                "select id, source_path from conversations"):
            if spath not in convs:
                continue
            rows = [r[0] for r in con.execute(
                "select content from messages where conversation_id = ? "
                "order by idx", (cid,))]
            fn = os.path.join(dump_dir, f"conv--{cid}")
            with open(fn, "w") as fh:
                fh.write("\n".join(x or "" for x in rows))
            conv_files[fn] = spath
    finally:
        con.close()
    return conv_files, new_chwm


def save_state(state_file, state):
    """Atomically replace the state file."""
    with open(state_file + ".tmp", "w") as fh:
        json.dump(state, fh)
    os.replace(state_file + ".tmp", state_file)
