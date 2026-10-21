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
# conversations.last_message_created_at; "cass://pending" is a dict of
# {path_or_glob: "exact"|"glob"} awaiting a successful `cass forget` (retried
# each run, capped per run since cass rebuilds its index per call).
#
# Safety:
#   * --dry-run prints what would change; it still writes the state file so
#     repeat dry-runs and the next real run stay incremental (clean-scan cache),
#     but it never edits transcripts, sqlite rows, or the cass archive and
#     never executes pending cass forgets.
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

source "$(dirname "$0")/transcript-common.sh"
ts_init
ts_defaults
REPORT="$REPORT_DIR/report.json"
CASS_BIN="${CASS_BIN:-/home/linuxbrew/.linuxbrew/bin/cass}"

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

ts_resolve "$@"
[ "$CASS" -eq 1 ] || CASS_DB=""
[ "${#FILE_TARGETS[@]}" -gt 0 ] || [ "${#DB_TARGETS[@]}" -gt 0 ] || [ -n "$CASS_DB" ] || { echo "no transcript stores exist" >&2; exit 1; }

ts_lock || exit 1
ts_targets_json
export STATE_FILE FULL REPORT CONF DRY CASS CASS_BIN CASS_DB DIR
python3 - "$REPORT_DIR" <<'PYEOF'
import json, os, sys, subprocess, sqlite3
sys.path.insert(0, os.environ["DIR"])
from transcript_common import (gitleaks_scan, collect_targets, prune_state,
                               db_recently_modified, dump_sqlite_rows,
                               dump_cass_convs, save_state, LIVE_WINDOW_S)

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

skipped_recent = skipped_short = redacted = 0
scrubbed_paths = []

# ---------------- file targets ---------------------------------------------
to_scan, seen = collect_targets(file_targets, state, full)

for p in to_scan:
    if now - os.path.getmtime(p) < LIVE_WINDOW_S:
        skipped_recent += 1
        continue
    hits = gitleaks_scan(conf, p, os.path.join(report_dir, "frag.json"),
                         scan_errors)
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

prune_state(state, file_targets, db_targets, seen)

# ---------------- opencode v1 sqlite targets --------------------------------
# State key "sqlite://<db>" -> {"hwm": <max row time_updated, epoch ms>,
#                             "dirty": [{"table":..,"id":..}]}.
# Each run scans rows newer than hwm plus dirty rows; patched rows become clean.
db_stats = {"rows_scanned": 0, "rows_patched": 0}
for db in db_targets:
    if not os.path.exists(db): continue
    if db_recently_modified(db, now):
        print(f"skip     ---  {os.path.basename(db)} (modified <5min ago)", file=sys.stderr)
        continue
    key = f"sqlite://{db}"
    ent = state.get(key, {"hwm": 0, "dirty": []})
    hwm = 0 if full else ent.get("hwm", 0)
    dirty_rows = {(d["table"], d["id"]) for d in ent.get("dirty", [])}

    try:
        row_keys, new_hwm = dump_sqlite_rows(
            db, os.path.join(report_dir, "rows"), hwm, dirty_rows)
    except sqlite3.Error as e:
        print(f"skip     ---  {db} ({e})", file=sys.stderr); continue

    if not row_keys:
        state[key] = {"hwm": new_hwm, "dirty": []}
        continue

    # one gitleaks scan over the whole dump dir
    hits = gitleaks_scan(conf, os.path.join(report_dir, "rows"),
                         os.path.join(report_dir, "rows-frag.json"),
                         scan_errors)
    if hits is None:
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

def pending_map(state):
    pend = state.get("cass://pending", {})
    if isinstance(pend, list):  # migrate the old bare-list format
        pend = {g: "exact" for g in pend}
    return dict(pend)

def glob_escape(s):
    return "".join(f"[{c}]" if c in "*?[" else c for c in s)

# cass accepts ONE --source-glob per call and does not expand {a,b} braces, so
# batching means capping attempts per run -- each forget rewrites the index --
# and carrying the rest in cass://pending for the next run.
MAX_FORGET_ATTEMPTS = 100

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

    conv_files, new_chwm = dump_cass_convs(
        cass_db, os.path.join(report_dir, "cass-convs"), chwm, cdirty)
    cass_stats["convs_scanned"] = len(conv_files)

    chits = []
    if conv_files:
        chits = gitleaks_scan(conf, os.path.join(report_dir, "cass-convs"),
                              os.path.join(report_dir, "cass-frag.json"),
                              scan_errors)

    hits_by_conv = {}
    new_forgets = []
    if chits is not None:
        for h in chits:
            fn = h.get("File")
            if fn in conv_files:
                hits_by_conv.setdefault(conv_files[fn], []).append(h)
        still_cdirty = []
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
            else:
                if dry:
                    print(f"dry-run  {len(convhits):3d}  cass:{spath}")
                new_forgets.append(spath)
            still_cdirty.append(spath)
        state[ckey] = {"hwm": new_chwm, "dirty": sorted(set(still_cdirty))}
        if new_forgets:
            pend = pending_map(state)
            pend.update({p: "exact" for p in new_forgets})
            state["cass://pending"] = pend

# -- cass forget: scrubbed sources + cass-scan hits ---------------------------
# Forget uses each conversation's full source_path as an exact-match glob
# (meta chars escaped): basename globs would forget unrelated sessions that
# share a filename (e.g. copilot's events.jsonl). Pending is a dict
# {path_or_glob: "exact"|"glob"} so pre-escaped vs pattern entries survive
# state round-trips; a failed/missing cass retries on the next run.
forgotten = attempts = 0
pending = pending_map(state)
if not dry:
    for p in scrubbed_paths:
        # scrubbed source: forget the archived copy; it re-indexes clean
        pending[p] = "exact"
    if db_stats["rows_patched"]:
        for db in db_targets:
            pending[db + "/*"] = "glob"  # '…/opencode.db/<session>' pseudo-paths
if pending:
    state["cass://pending"] = pending
else:
    state.pop("cass://pending", None)

if cass and pending:
    if not os.path.exists(cass_bin):
        print(f"cass: {len(pending)} forgets pending; binary not found at {cass_bin}",
              file=sys.stderr)
    elif not cass_db:
        print(f"cass: {len(pending)} forgets pending; agent_search.db not a target",
              file=sys.stderr)
    elif not dry:
        for g in sorted(pending):
            if attempts >= MAX_FORGET_ATTEMPTS:
                break
            attempts += 1
            pat = glob_escape(g) if pending[g] == "exact" else g
            r = subprocess.run(
                [cass_bin, "forget", "--source-glob", pat,
                 "--apply", "--db", cass_db, "--json"],
                capture_output=True, text=True)
            if r.returncode == 0:
                forgotten += 1
                del pending[g]
            else:
                print(f"cass forget failed for {pat}: {r.stderr.strip()[:200]}",
                      file=sys.stderr)

if dry:
    queued = sorted(set(pending) | set(scrubbed_paths))
    if cass and cass_db and db_stats["rows_patched"]:
        queued += [db + "/*" for db in db_targets]
    for g in queued:
        print(f"dry-run  ---  cass forget {g}")
    print(f"(dry-run: {len(queued)} cass forgets queued)")
elif pending:
    state["cass://pending"] = pending
else:
    state.pop("cass://pending", None)

# dry-run saves state too: clean files/rows stay cached (dirty entries carry
# findings, so they're always re-scanned), which keeps repeat dry-runs and the
# next real run incremental instead of re-scanning everything.
save_state(state_file, state)

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
