"""Shared helpers for scrub-transcripts.sh and report-exposed-secrets.sh.

Both scripts embed their python via heredoc and import this module with
`sys.path.insert(0, os.environ["DIR"])` so the copy baked into the nix store
works the same as the repo checkout.
"""

import datetime
import json
import os
import sqlite3
import subprocess

LIVE_WINDOW_S = 300  # files/DBs touched in the last 5 min are skipped

# Per-store dump/patch specs for sqlite targets, keyed by basename. Each spec
# is a list of (table, [value columns], ts_column, key_column, zstd) where
# ts_column drives the incremental high-water mark ("" = scan every row),
# key_column identifies rows when patching ("rowid" = sqlite rowid), and
# zstd=True means the first value column is a zstd-compressed blob that must be
# decompressed before scanning and recompressed after patching (zed threads).
# Columns not listed aren't scanned — keep this to columns that can carry
# transcript text.
SQLITE_SPECS = {
    # opencode v1: message/part rows, epoch-ms time_updated, id key
    "opencode.db": [
        ("message", ["data"], "time_updated", "id", False),
        ("part", ["data"], "time_updated", "id", False)],
    # codex app-server thread history: one JSON blob per item
    "thread_history_1.sqlite": [
        ("thread_items", ["item_json"], "created_at_ms", "rowid", False),
        ("thread_realtime_items", ["item_json"], "created_at_ms", "rowid",
         False)],
    # codex threads index: titles/previews mirror user prompts
    "state_5.sqlite": [
        ("threads", ["title", "first_user_message", "preview"],
         "updated_at_ms", "id", False)],
    # codex logs: feedback bodies can embed submitted text
    "logs_2.sqlite": [
        ("logs", ["feedback_log_body"], "ts", "id", False)],
    # zed threads: whole thread is one zstd blob; updated_at is RFC3339 text
    "threads.db": [("threads", ["data"], "updated_at", "id", True)],
}


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


def _ts_value(raw, is_text):
    """Normalise a timestamp column value to a sortable high-water mark.
    RFC3339 text (zed) -> epoch ms; numeric columns pass through as-is."""
    if is_text:
        if not raw:
            return 0
        try:
            return int(datetime.datetime.fromisoformat(
                raw.replace("Z", "+00:00")).timestamp() * 1000)
        except ValueError:
            return 0
    return raw or 0


def _zstd_decompress(data):
    r = subprocess.run(["zstd", "-d", "-c"], input=data,
                       capture_output=True, check=False)
    if r.returncode != 0:
        raise ValueError(f"zstd decompress failed: {r.stderr[:120]!r}")
    return r.stdout


def zstd_compress(data):
    r = subprocess.run(["zstd", "-q", "-c"], input=data,
                       capture_output=True, check=False)
    if r.returncode != 0:
        raise ValueError(f"zstd compress failed: {r.stderr[:120]!r}")
    return r.stdout


def dump_sqlite_rows(db, dump_dir, hwm, dirty_rows):
    """Dump candidate cells of a sqlite store to dump_dir as
    '<table>--<key>--<col>' files (key = the spec's key_column value; "rowid"
    means the sqlite rowid). For zstd spec tables the value is decompressed
    first. Rows are selected by their ts_column > hwm plus rows still dirty.
    Returns (cell_keys {dump_file: (table, key, col)}, new_hwm).
    Raises sqlite3.Error on connect failure; unknown basenames scan nothing."""
    specs = SQLITE_SPECS.get(os.path.basename(db), [])
    con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    try:
        os.makedirs(dump_dir, exist_ok=True)
        new_hwm = hwm
        cell_keys = {}
        for spec in specs:
            table, cols, ts_col, key_col, zstd = spec
            is_text_ts = ts_col and \
                _col_affinity(con, table, ts_col) == "TEXT"
            key_expr = "rowid" if key_col == "rowid" else key_col
            sel = [key_expr] + ([ts_col] if ts_col else []) + cols
            # Numeric ts columns filter in SQL; text (RFC3339) timestamps are
            # compared in Python so precision/format mismatches can't skip rows.
            where, params = "", []
            if ts_col and not is_text_ts:
                where = f"where {ts_col} > ?"
                params = [hwm]
            try:
                rows = con.execute(
                    f"select {', '.join(sel)} from {table} {where}",
                    params).fetchall()
            except sqlite3.Error:
                continue
            n_meta = 1 + (1 if ts_col else 0)
            for row in rows:
                key = row[0]
                ts = _ts_value(row[1], is_text_ts) if ts_col else 0
                if ts > new_hwm:
                    new_hwm = ts
                if ts_col and ts <= hwm:
                    continue
                for ci, val in enumerate(row[n_meta:]):
                    text = _cell_text(val, zstd)
                    if text is None:
                        continue
                    fn = os.path.join(
                        dump_dir, f"{table}--{key}--{cols[ci]}")
                    with open(fn, "w") as fh:
                        fh.write(text)
                    cell_keys[fn] = (table, key, cols[ci])
        for table, key, col in dirty_rows:
            spec = next((s for s in specs if s[0] == table), None)
            if not spec or col not in spec[1]:
                continue
            _, cols, _ts, key_col, zstd = spec
            key_expr = "rowid" if key_col == "rowid" else key_col
            try:
                r = con.execute(
                    f"select {col} from {table} where {key_expr} = ?",
                    (key,)).fetchone()
            except sqlite3.Error:
                r = None
            if r:
                text = _cell_text(r[0], zstd)
                if text is not None:
                    fn = os.path.join(dump_dir, f"{table}--{key}--{col}")
                    with open(fn, "w") as fh:
                        fh.write(text)
                    cell_keys[fn] = (table, key, col)
    finally:
        con.close()
    return cell_keys, new_hwm


def _cell_text(val, zstd):
    """Normalise a column value to scannable text, or None to skip it."""
    if val is None:
        return None
    if zstd:
        try:
            return _zstd_decompress(val).decode("utf-8", "replace")
        except (ValueError, TypeError):
            return None
    if isinstance(val, bytes):
        return val.decode("utf-8", "replace")
    return str(val)


def sqlite_spec(db, table):
    """Look up the spec for (db basename, table), or None."""
    return next((s for s in SQLITE_SPECS.get(os.path.basename(db), [])
                 if s[0] == table), None)


def patch_sqlite_cell(con, spec, key, col, text):
    """Write a patched cell back; zstd spec columns are recompressed."""
    _table, _cols, _ts, key_col, zstd = spec
    val = zstd_compress(text.encode()) if zstd else text
    key_expr = "rowid" if key_col == "rowid" else key_col
    con.execute(f"update {spec[0]} set {col} = ? where {key_expr} = ?",
                (val, key))


def _col_affinity(con, table, col):
    try:
        for r in con.execute(f"pragma table_info({table})"):
            if r[1] == col:
                return r[2].upper()
    except sqlite3.Error:
        pass
    return ""


def _ms_to_rfc3339(ms):
    return datetime.datetime.fromtimestamp(
        ms / 1000, datetime.timezone.utc).isoformat()


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
