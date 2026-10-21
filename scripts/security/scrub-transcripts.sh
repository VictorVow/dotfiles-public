#!/usr/bin/env bash
#
# scrub-transcripts.sh — rewrite leaked secrets in agent transcripts to
# [REDACTED:<rule>] in place, and drop leaked conversations from the cass
# archive so the search index stops serving them.
#
# Stores handled:
#   * JSONL/JSON transcript trees (claude, codex, gemini, openclaw, copilot,
#     devin, opencode v2 session_diff files) — spliced on disk via atomic
#     rename.
#   * opencode v1 sqlite (opencode.db: message.data + part.data JSON blobs)
#     — rows dumped to a temp dir, gitleaks-scanned, and patched back with
#     UPDATE ... SET data = replace(data, secret, marker).
#   * cass archive (agent_search.db messages.content) — dumped per
#     conversation and gitleaks-scanned; hit conversations are dropped with
#     `cass forget --source-glob '<exact source_path>'`. Forget is used rather
#     than rewriting because the db is cass-owned (frankensqlite, attestations)
#     and raw-mirror blobs are content-addressed. Covers conversations whose
#     source file is already gone.
#
# Incremental + repeatable: shares the state file written by
# report-exposed-secrets.sh ($XDG_STATE_HOME/transcript-scrub/state.json).
# Files whose mtime/size are unchanged since their last clean scan are skipped;
# files with stored findings are re-scanned so the literal Secret values are
# fresh (state never stores secrets). For sqlite DBs the state key is
# "sqlite://<db>" and carries a high-water mark on the row time_updated — only
# rows newer than the mark (plus rows still marked dirty) are re-scanned.
# The cass archive sits under "cass://<db>" with a hwm on
# conversations.last_message_created_at; "cass://pending" stores exact
# source_path globs awaiting a successful `cass forget` (retried each run).
#
# Safety:
#   * --dry-run prints what would change, touches nothing (files, sqlite, cass).
#   * files/rows touched in the last 5 minutes are skipped (live session?).
#   * findings whose Secret is <8 bytes are skipped (too risky to splice).
#
# Usage:
#   scrub-transcripts.sh --dry-run            # preview
#   scrub-transcripts.sh                      # scrub everything + cass archive
#   scrub-transcripts.sh DIR|DB [DIR|DB...]   # scrub specific dirs/files/.db
#   scrub-transcripts.sh --no-cass            # skip all cass work
#   scrub-transcripts.sh --full               # force rescan of everything
#
set -euo pipefail

DIR="$(dirname "$0")"
CONF="$DIR/gitleaks-scrub.toml"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/transcript-scrub"
STATE_FILE="$STATE_DIR/state.json"
REPORT_DIR="$(mktemp -d)"
trap 'rm -rf "$REPORT_DIR"' EXIT
REPORT="$REPORT_DIR/report.json"
CASS_BIN="${CASS_BIN:-/home/linuxbrew/.linuxbrew/bin/cass}"
CASS_DATA_DIR="${CASS_DATA_DIR:-$HOME/.local/share/coding-agent-search}"

DRY=0 FULL=0 CASS=1
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    --full)    FULL=1; shift ;;
    --no-cass) CASS=0; shift ;;
    --) shift; break ;;
    *) break ;;
  esac
done

# Default file targets (JSONL/JSON stores) + sqlite targets (opencode v1).
# cass raw-mirror blobs are NOT scanned: they're content-addressed, so splicing
# them would corrupt cass's blake3 verification — cass copies are handled via
# `cass forget` on the conversation + the agent_search.db scan below.
FILE_TARGETS=(
  "$HOME/.claude/projects"
  "$HOME/.config/codex/sessions"
  "$HOME/.gemini"
  "$HOME/.openclaw"
  "$HOME/.copilot/session-state"
  "$HOME/.local/share/devin"
  "$HOME/.local/share/opencode/storage"
  "$HOME/.opencode1/data/opencode/storage"
)
DB_TARGETS=(
  "$HOME/.local/share/opencode/opencode.db"
  "$HOME/.opencode1/data/opencode/opencode.db"
)
CASS_DB="$CASS_DATA_DIR/agent_search.db"

if [ "$#" -gt 0 ]; then
  FILE_TARGETS=(); DB_TARGETS=(); CASS_DB=""
  for t in "$@"; do
    [ -e "$t" ] || continue
    if [[ "$t" == *.db ]]; then DB_TARGETS+=("$(readlink -f "$t")")
    else FILE_TARGETS+=("$(readlink -f "$t")"); fi
  done
else
  _f=(); for t in "${FILE_TARGETS[@]}"; do [ -e "$t" ] && _f+=("$(readlink -f "$t")"); done; FILE_TARGETS=("${_f[@]+"${_f[@]}"}")
  _d=(); for t in "${DB_TARGETS[@]}";   do [ -e "$t" ] && _d+=("$(readlink -f "$t")"); done; DB_TARGETS=("${_d[@]+"${_d[@]}"}")
fi
[ "$CASS" -eq 1 ] || CASS_DB=""
[ "${#FILE_TARGETS[@]}" -gt 0 ] || [ "${#DB_TARGETS[@]}" -gt 0 ] || [ -n "$CASS_DB" ] || { echo "no transcript stores exist" >&2; exit 1; }

mkdir -p "$STATE_DIR"
[ -f "$STATE_FILE" ] || echo '{}' > "$STATE_FILE"
# Serialise runs: a timer + a manual run would otherwise interleave gitleaks
# invocations and overwrite each other's state file.
exec 9>"$STATE_DIR/lock"
flock -n 9 || { echo "another transcript-scrub run is in progress" >&2; exit 1; }

FILE_TARGETS_JSON="$(printf '%s\n' "${FILE_TARGETS[@]+"${FILE_TARGETS[@]}"}" | python3 -c 'import sys,json; print(json.dumps([l.rstrip("\n") for l in sys.stdin if l.strip()]))')"
DB_TARGETS_JSON="$(printf '%s\n' "${DB_TARGETS[@]+"${DB_TARGETS[@]}"}" | python3 -c 'import sys,json; print(json.dumps([l.rstrip("\n") for l in sys.stdin if l.strip()]))')"
export STATE_FILE FULL REPORT CONF DRY CASS CASS_BIN CASS_DB FILE_TARGETS_JSON DB_TARGETS_JSON
python3 - "$REPORT_DIR" <<'PYEOF'
import json, os, sys, subprocess, sqlite3

report_dir = sys.argv[1]
file_targets = json.loads(os.environ["FILE_TARGETS_JSON"])
db_targets = json.loads(os.environ["DB_TARGETS_JSON"])
state_file = os.environ["STATE_FILE"]
full = os.environ["FULL"] == "1"
conf = os.environ["CONF"]
dry = os.environ["DRY"] == "1"
cass = os.environ["CASS"] == "1"
cass_bin = os.environ["CASS_BIN"]
cass_db = os.environ["CASS_DB"]

state = json.load(open(state_file))
import time; now = time.time()

scan_errors = []

def scan_path(p):
    """gitleaks-scan one file; return findings list, or None on scan error."""
    frag = os.path.join(report_dir, "frag.json")
    if os.path.exists(frag): os.remove(frag)
    r = subprocess.run(
        ["gitleaks", "dir", "--config", conf, "--no-banner", "--exit-code", "0",
         "--report-format", "json", "--report-path", frag, p],
        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True, check=False)
    if r.returncode != 0:
        scan_errors.append(f"{p}: gitleaks exited {r.returncode}: {r.stderr.strip()[:200]}")
        return None
    try: return json.load(open(frag))
    except Exception as e:
        scan_errors.append(f"{p}: unreadable gitleaks report: {e}")
        return None

skipped_recent = skipped_short = redacted = 0
scrubbed_paths = []

# ---------------- file targets ---------------------------------------------
seen = set()
to_scan = []
for root in file_targets:
    paths = [root] if os.path.isfile(root) else (
        os.path.join(d, f) for d, _ds, fs in os.walk(root) for f in fs)
    for p in paths:
        if not os.path.isfile(p): continue
        try: st = os.stat(p)
        except OSError: continue
        seen.add(p)
        ent = state.get(p)
        if full or not ent or ent["mtime"] != st.st_mtime or ent["size"] != st.st_size \
           or ent.get("findings"):
            to_scan.append(p)

for p in to_scan:
    if now - os.path.getmtime(p) < 300:
        skipped_recent += 1
        continue
    hits = scan_path(p)
    if hits is None:
        continue  # leave previous state untouched
    st = os.stat(p)
    if not hits:
        state[p] = {"mtime": st.st_mtime, "size": st.st_size, "findings": []}
        continue

    content = orig = open(p, "rb").read()
    applied = 0
    unapplied = []  # hits whose secret wasn't literal text in the file
    for h in hits:
        secret = (h.get("Secret") or "").encode()
        if len(secret) < 8:
            skipped_short += 1
            unapplied.append(h)
            continue
        rep = f"[REDACTED:{h['RuleID']}]".encode()
        # Check the ORIGINAL content: one hit's replace() removes every copy of
        # a repeated secret, so later hits for the same value correctly find
        # nothing left -- they're handled, not unmatched.
        if secret in orig:
            if secret in content:
                content = content.replace(secret, rep)
            applied += 1
        else:
            # gitleaks decodes base64 etc., so the reported Secret may not
            # appear verbatim; rewriting is unsafe -> keep the file dirty.
            unapplied.append(h)
    if applied:
        if dry:
            print(f"dry-run  {applied:3d}  {os.path.relpath(p, os.path.expanduser('~'))}")
        else:
            tmp = p + ".scrub.tmp"
            with open(tmp, "wb") as fh: fh.write(content)
            os.chmod(tmp, os.stat(p).st_mode & 0o777)
            # re-check mtime+size: a live session may have appended between our
            # read and now -- replacing would silently drop the new line(s).
            try: cur = os.stat(p)
            except OSError: cur = None
            if cur and (cur.st_mtime, cur.st_size) == (st.st_mtime, st.st_size):
                os.replace(tmp, p)
                print(f"scrubbed {applied:3d}  {os.path.relpath(p, os.path.expanduser('~'))}")
            else:
                os.remove(tmp)
                print(f"skip     ---  {os.path.relpath(p, os.path.expanduser('~'))} (changed during scrub)", file=sys.stderr)
                continue
        redacted += applied
        scrubbed_paths.append(p)
    for h in unapplied:
        print(f"unmatched {h['RuleID']:<35} {os.path.relpath(p, os.path.expanduser('~'))}:{h['StartLine']}"
              f" (secret not literal in file — manual check needed)", file=sys.stderr)

    st = os.stat(p)
    still_dirty = hits if dry else unapplied
    state[p] = {"mtime": st.st_mtime, "size": st.st_size,
                "findings": [{"rule": h["RuleID"], "line": h["StartLine"]}
                             for h in still_dirty]}

# Prune state only within the roots we walked this run -- a partial run must
# not wipe entries belonging to other targets.
prune_roots = [os.path.realpath(r) for r in file_targets]
for k in [k for k in list(state) if k not in seen and not k.startswith("sqlite://")
          and any(os.path.realpath(k) == r or os.path.realpath(k).startswith(r + os.sep)
                  for r in prune_roots)]:
    del state[k]
# Same for sqlite: drop only keys whose db was targeted this run and is gone.
db_prune = {os.path.realpath(d) for d in db_targets}
for k in [k for k in list(state) if k.startswith("sqlite://")
          and os.path.realpath(k[len("sqlite://"):]) in db_prune
          and not os.path.exists(k[len("sqlite://"):])]:
    del state[k]

# ---------------- opencode v1 sqlite targets --------------------------------
# State key "sqlite://<db>" -> {"hwm": <max row time_updated, epoch ms>,
#                             "dirty": [{"table":..,"id":..}]}.
# Each run scans rows newer than hwm plus dirty rows; patched rows become clean.
db_stats = {"rows_scanned": 0, "rows_patched": 0}
for db in db_targets:
    if not os.path.exists(db): continue
    # WAL mode: writes land in <db>-wal and the main file's mtime barely moves,
    # so take the newest of db/-wal. -shm is excluded: its mtime moves on plain
    # reads (including our own and cass's indexer), which would skip the db
    # forever. This is a live-session guard, not a cache heuristic -- it must
    # apply under --full too.
    wal = db + "-wal"
    db_mtime = max(
        (os.path.getmtime(f) for f in (db, wal) if os.path.exists(f)),
        default=0)
    # An empty -wal means everything is already checkpointed into the main db;
    # reads alone can bump its mtime, so it shouldn't count as "live".
    if os.path.exists(wal) and os.path.getsize(wal) == 0:
        db_mtime = os.path.getmtime(db)
    if now - db_mtime < 300:
        print(f"skip     ---  {os.path.basename(db)} (modified <5min ago)", file=sys.stderr)
        continue
    key = f"sqlite://{db}"
    ent = state.get(key, {"hwm": 0, "dirty": []})
    hwm = 0 if full else ent.get("hwm", 0)
    dirty_rows = {(d["table"], d["id"]) for d in ent.get("dirty", [])}

    try:
        con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    except sqlite3.Error as e:
        print(f"skip     ---  {db} ({e})", file=sys.stderr); continue

    # extract candidate rows: newer than hwm or marked dirty
    dump = os.path.join(report_dir, "rows")
    os.makedirs(dump, exist_ok=True)
    new_hwm = hwm
    row_keys = {}  # dump-file path -> (table, rowid)
    for table in ("message", "part"):
        try:
            cur = con.execute(
                f"select id, time_updated, data from {table} where time_updated > ?",
                (hwm,))
        except sqlite3.Error:
            continue
        for rid, tupd, data in cur.fetchall():
            ts = tupd or 0
            if ts > new_hwm: new_hwm = ts
            fn = os.path.join(dump, f"{table}--{rid}")
            with open(fn, "w") as fh: fh.write(data or "")
            row_keys[fn] = (table, rid)
    # re-extract dirty rows regardless of age
    for table, rid in dirty_rows:
        try:
            r = con.execute(f"select data from {table} where id = ?", (rid,)).fetchone()
        except sqlite3.Error:
            r = None
        if r:
            fn = os.path.join(dump, f"{table}--{rid}")
            with open(fn, "w") as fh: fh.write(r[0] or "")
            row_keys[fn] = (table, rid)
    con.close()

    if not row_keys:
        state[key] = {"hwm": new_hwm, "dirty": []}
        continue

    # one gitleaks scan over the whole dump dir
    frag = os.path.join(report_dir, "rows-frag.json")
    if os.path.exists(frag): os.remove(frag)
    r = subprocess.run(
        ["gitleaks", "dir", "--config", conf, "--no-banner", "--exit-code", "0",
         "--report-format", "json", "--report-path", frag, dump],
        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True, check=False)
    if r.returncode != 0:
        scan_errors.append(f"{db}: gitleaks exited {r.returncode}: {r.stderr.strip()[:200]}")
        continue
    try: hits = json.load(open(frag))
    except Exception as e:
        scan_errors.append(f"{db}: unreadable gitleaks report: {e}")
        continue
    db_stats["rows_scanned"] += len(row_keys)

    # group hits per row
    per_row = {}
    for h in hits:
        fn = h.get("File")
        if fn in row_keys:
            per_row.setdefault(row_keys[fn], []).append(h)

    still_dirty = []
    if not dry and per_row:
        con = sqlite3.connect(db)
    for (table, rid), rowhits in per_row.items():
        if dry:
            print(f"dry-run  {len(rowhits):3d}  {os.path.basename(db)}:{table}:{rid[:16]}…")
            still_dirty.append({"table": table, "id": rid})
            db_stats["rows_patched"] += len(rowhits)
            continue
        row = con.execute(f"select data from {table} where id = ?", (rid,)).fetchone()
        if not row: continue
        data = row[0] or ""
        applied = 0
        for h in rowhits:
            secret = h.get("Secret") or ""
            if len(secret.encode()) < 8:
                skipped_short += 1; continue
            rep = f"[REDACTED:{h['RuleID']}]"
            if secret in data:
                data = data.replace(secret, rep); applied += 1
        if applied:
            con.execute(f"update {table} set data = ? where id = ?", (data, rid))
            db_stats["rows_patched"] += applied
            print(f"scrubbed {applied:3d}  {os.path.basename(db)}:{table}:{rid[:16]}…")
            # secrets <8 remain -> keep dirty
            if any(len((h.get("Secret") or "").encode()) < 8 for h in rowhits):
                still_dirty.append({"table": table, "id": rid})
        else:
            still_dirty.append({"table": table, "id": rid})
    if not dry and per_row:
        con.commit(); con.close()

    state[key] = {"hwm": new_hwm, "dirty": still_dirty}

if not dry:
    with open(state_file + ".tmp", "w") as fh:
        json.dump(state, fh)
    os.replace(state_file + ".tmp", state_file)

# ---------------- cass archive (agent_search.db) ----------------------------
# Dump messages.content per conversation, gitleaks-scan once, and forget every
# conversation with a hit. State key "cass://<db>" -> {"hwm": <max conv
# last_message_created_at>, "dirty": [<source_path>]} — dirty convs are
# re-scanned until they no longer exist in the archive.
cass_stats = {"convs_scanned": 0, "convs_forgotten": 0}
if cass and cass_db and os.path.exists(cass_db):
    ckey = f"cass://{cass_db}"
    cent = state.get(ckey, {"hwm": 0, "dirty": []})
    chwm = 0 if full else cent.get("hwm", 0)
    cdirty = set(cent.get("dirty", []))

    con = sqlite3.connect(f"file:{cass_db}?mode=ro", uri=True)
    convs = {}   # source_path -> newest last_message_created_at
    new_chwm = chwm
    for cid, spath, lmc in con.execute(
            "select id, source_path, last_message_created_at from conversations"):
        ts = lmc or 0
        if ts <= chwm and spath not in cdirty:
            continue
        if ts > new_chwm: new_chwm = ts
        convs[spath] = ts
    cdump = os.path.join(report_dir, "cass-convs")
    os.makedirs(cdump, exist_ok=True)
    conv_files = {}  # dump-file path -> source_path
    for cid, spath in con.execute(
            "select id, source_path from conversations"):
        if spath not in convs: continue
        rows = [r[0] for r in con.execute(
            "select content from messages where conversation_id = ? order by idx",
            (cid,))]
        fn = os.path.join(cdump, f"conv--{cid}")
        with open(fn, "w") as fh: fh.write("\n".join(x or "" for x in rows))
        conv_files[fn] = spath
    con.close()

    hits_by_conv = {}
    if conv_files:
        frag = os.path.join(report_dir, "cass-frag.json")
        if os.path.exists(frag): os.remove(frag)
        r = subprocess.run(
            ["gitleaks", "dir", "--config", conf, "--no-banner", "--exit-code", "0",
             "--report-format", "json", "--report-path", frag, cdump],
            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True, check=False)
        if r.returncode != 0:
            scan_errors.append(f"{cass_db}: gitleaks exited {r.returncode}: {r.stderr.strip()[:200]}")
            hits_by_conv = None
        else:
            try: chits = json.load(open(frag))
            except Exception as e:
                scan_errors.append(f"{cass_db}: unreadable gitleaks report: {e}")
                chits = None
            if chits is not None:
                for h in chits:
                    fn = h.get("File")
                    if fn in conv_files:
                        hits_by_conv.setdefault(conv_files[fn], []).append(h)
    cass_stats["convs_scanned"] = len(conv_files)

    if hits_by_conv is not None:
        still_cdirty = []
        new_forgets = []
        for spath, convhits in hits_by_conv.items():
            # A conversation whose source file is gone has its archive copy as
            # the last remaining record -- forgetting deletes it for good, and
            # noisy rules (generic-api-key) can false-positive. List it for
            # manual review instead of auto-deleting on an unattended run.
            # opencode.db/<session> pseudo-paths exist iff their db does.
            source_gone = not os.path.exists(spath) and not any(
                spath.startswith(d + os.sep) for d in db_targets)
            if source_gone:
                print(f"cass review ---  {spath} (source gone; {len(convhits)} hits -- "
                      f"run `cass forget --source-glob '{spath}' --apply` manually if real)",
                      file=sys.stderr)
            elif dry:
                print(f"dry-run  {len(convhits):3d}  cass:{spath}")
                new_forgets.append(spath)
            else:
                new_forgets.append(spath)
            still_cdirty.append(spath)
        if not dry:
            pending = state.get("cass://pending", [])
            pending.extend(new_forgets)
            state[ckey] = {"hwm": new_chwm, "dirty": sorted(set(still_cdirty))}
            if pending:
                state["cass://pending"] = sorted(set(pending))

# -- cass forget: scrubbed sources + cass-scan hits, batched ------------------
# Forget uses each conversation's full source_path as an exact-match glob
# (meta chars escaped): basename globs would forget unrelated sessions that
# share a filename (e.g. copilot's events.jsonl). Pending globs live in the
# state file so a failed/missing cass retries on the next run. Exact paths are
# collapsed into ONE brace glob so cass rebuilds its index once per run
# instead of once per path; non-exact patterns run individually.
forgotten = 0
# pending maps glob -> exact (True = escape all meta chars / match one path)
pending = {g: True for g in state.get("cass://pending", [])}
if not dry:
    for p in scrubbed_paths:
        # scrubbed source: forget the archived copy; it re-indexes clean
        pending[p] = True
    if db_stats["rows_patched"]:
        for db in db_targets:
            pending[db + "/*"] = False  # '…/opencode.db/<session>' pseudo-paths
    if pending:
        state["cass://pending"] = sorted(pending)
    else:
        state.pop("cass://pending", None)

def glob_escape(s):
    return "".join(f"[{c}]" if c in "*?[" else c for c in s)

if cass and pending:
    if not os.path.exists(cass_bin):
        print(f"cass: {len(pending)} forgets pending; binary not found at {cass_bin}",
              file=sys.stderr)
    elif not cass_db:
        print(f"cass: {len(pending)} forgets pending; agent_search.db not a target",
              file=sys.stderr)
    elif not dry:
        exacts = sorted(g for g, e in pending.items() if e)
        patterns = sorted(g for g, e in pending.items() if not e)
        jobs = [("{" + ",".join(glob_escape(g) for g in exacts) + "}", exacts)] \
            if exacts else []
        jobs += [(g, [g]) for g in patterns]
        for pat, globs in jobs:
            r = subprocess.run(
                [cass_bin, "forget", "--source-glob", pat,
                 "--apply", "--db", cass_db, "--json"],
                capture_output=True, text=True)
            if r.returncode == 0:
                forgotten += len(globs)
                for g in globs:
                    del pending[g]
            else:
                print(f"cass forget failed for {pat}: {r.stderr.strip()[:200]}",
                      file=sys.stderr)

if dry:
    queued = sorted(set(state.get("cass://pending", []))
                    | set(scrubbed_paths))
    if cass and cass_db and db_targets:
        queued += [db + "/*" for db in db_targets]
    for g in queued:
        print(f"dry-run  ---  cass forget {g}")
    print(f"(dry-run: {len(queued)} cass forgets queued)")
elif pending:
    state["cass://pending"] = sorted(pending)
else:
    state.pop("cass://pending", None)

# re-write state now that cass://pending may have changed
if not dry:
    with open(state_file + ".tmp", "w") as fh:
        json.dump(state, fh)
    os.replace(state_file + ".tmp", state_file)

for e in scan_errors:
    print(f"scan error: {e}", file=sys.stderr)

print(f"\n{redacted} file secrets {'would be ' if dry else ''}redacted "
      f"({skipped_recent} live/recent skipped, {skipped_short} <8-byte skipped); "
      f"sqlite: {db_stats['rows_scanned']} rows scanned, "
      f"{db_stats['rows_patched']} secrets {'would be ' if dry else ''}patched; "
      f"cass: {cass_stats['convs_scanned']} conversations scanned")
if forgotten:
    print(f"cass: forgot {forgotten} conversations")
if pending and not dry:
    print(f"cass: {len(pending)} forgets still pending")
if dry:
    print("(dry-run: nothing changed)")
PYEOF
