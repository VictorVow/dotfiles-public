#!/usr/bin/env bash
#
# scrub-transcripts.sh — rewrite leaked secrets in agent transcripts to
# [REDACTED:<rule>] in place, and drop leaked conversations from the cass
# archive so the search index stops serving them.
#
# Incremental + repeatable: shares the state file written by
# report-exposed-secrets.sh ($XDG_STATE_HOME/transcript-scrub/state.json).
# Files whose mtime/size are unchanged since their last clean scan are skipped;
# files with stored findings are re-scanned so the literal Secret values are
# fresh for splicing (state deliberately never stores secrets).
#
# What it does per run:
#   1. scans changed/new transcript files with gitleaks
#   2. rewrites each finding's Secret in place via atomic rename
#      (handles read-only/0400 files; JSONL stays valid — only the string
#      content inside the line is replaced)
#   3. calls `cass forget --source-glob <file> --apply` for each scrubbed file
#      so cass drops its archived copy/index entries (file is re-indexed clean
#      on the next cass-incremental run if it still exists on disk)
#   4. scans cass's raw-mirror copies the same way (default target)
#
# Safety:
#   * --dry-run prints what would change, touches nothing (also skips cass).
#   * files modified in the last 5 minutes are skipped (may belong to a live
#     agent session still writing).
#   * findings whose Secret is <8 bytes are skipped (too risky to splice).
#   * opencode sessions live in sqlite (opencode.db) — not file-scrubbed;
#     matching cass rows are still dropped via step 3 when the source path
#     resolves, but the on-disk sqlite keeps its copy.
#
# Usage:
#   scrub-transcripts.sh --dry-run            # preview
#   scrub-transcripts.sh                      # scrub default dirs + cass archive
#   scrub-transcripts.sh DIR [DIR...]         # scrub specific dirs/files
#   scrub-transcripts.sh --no-cass            # skip the cass forget step
#   scrub-transcripts.sh --full               # force rescan of every file
#
set -euo pipefail

DIR="$(dirname "$0")"
CONF="$DIR/gitleaks-scrub.toml"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/transcript-scrub"
STATE_FILE="$STATE_DIR/state.json"
REPORT_DIR="$(mktemp -d)"
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

if [ "$#" -eq 0 ]; then
  set -- \
    "$HOME/.claude/projects" \
    "$HOME/.config/codex/sessions" \
    "$HOME/.gemini" \
    "$HOME/.openclaw" \
    "$HOME/.copilot/session-state" \
    "$HOME/.local/share/devin" \
    "$HOME/.local/share/coding-agent-search/raw-mirror"
fi

targets=()
for t in "$@"; do [ -e "$t" ] && targets+=("$(readlink -f "$t")"); done
[ "${#targets[@]}" -gt 0 ] || { echo "no transcript dirs exist" >&2; exit 1; }

mkdir -p "$STATE_DIR"
[ -f "$STATE_FILE" ] || echo '{}' > "$STATE_FILE"

export STATE_FILE FULL REPORT CONF DRY CASS CASS_BIN CASS_DATA_DIR
python3 - "$REPORT_DIR" "${targets[@]}" <<'PYEOF'
import json, os, sys, subprocess

report_dir, targets = sys.argv[1], sys.argv[2:]
state_file = os.environ["STATE_FILE"]
full = os.environ["FULL"] == "1"
conf = os.environ["CONF"]
dry = os.environ["DRY"] == "1"
cass = os.environ["CASS"] == "1"
cass_bin = os.environ["CASS_BIN"]
cass_mirror = os.path.join(os.environ["CASS_DATA_DIR"], "raw-mirror")

state = json.load(open(state_file))
now = __import__("time").time()

# -- enumerate + decide what to scan ---------------------------------------
to_scan, seen = [], set()
for root in targets:
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
        needs = full or not ent or ent["mtime"] != st.st_mtime or ent["size"] != st.st_size \
            or ent.get("findings")
        if needs:
            to_scan.append(p)

# -- scan + splice ----------------------------------------------------------
skipped_recent = skipped_short = scrubbed_files = 0
scrubbed_paths = []

for p in to_scan:
    if now - os.path.getmtime(p) < 300:
        skipped_recent += 1
        continue
    frag = os.path.join(report_dir, "frag.json")
    subprocess.run(
        ["gitleaks", "dir", "--config", conf, "--no-banner", "--exit-code", "0",
         "--report-format", "json", "--report-path", frag, p],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    try:
        hits = json.load(open(frag))
    except Exception:
        hits = []

    st = os.stat(p)
    if not hits:
        state[p] = {"mtime": st.st_mtime, "size": st.st_size, "findings": []}
        continue

    content = open(p, "rb").read()
    applied = 0
    for h in hits:
        secret = (h.get("Secret") or "").encode()
        if len(secret) < 8:
            skipped_short += 1
            continue
        rep = f"[REDACTED:{h['RuleID']}]".encode()
        if secret in content:
            content = content.replace(secret, rep)
            applied += 1
    if applied:
        if dry:
            print(f"dry-run  {applied:3d}  {os.path.relpath(p, os.path.expanduser('~'))}")
        else:
            tmp = p + ".scrub.tmp"
            with open(tmp, "wb") as fh:
                fh.write(content)
            os.chmod(tmp, os.stat(p).st_mode & 0o777)
            os.replace(tmp, p)
            print(f"scrubbed {applied:3d}  {os.path.relpath(p, os.path.expanduser('~'))}")
        scrubbed_files += applied
        scrubbed_paths.append(p)

    # refresh state — after a real apply, only hits we didn't redact remain
    # dirty (e.g. secrets <8 bytes); on dry-run everything stays dirty so the
    # next real run still sees this file.
    st = os.stat(p)
    if dry:
        still_dirty = hits
    elif applied == 0:
        still_dirty = hits
    else:
        # keep hits whose secrets are too short to splice (still present)
        still_dirty = [h for h in hits
                       if len((h.get("Secret") or "").encode()) < 8]
    state[p] = {"mtime": st.st_mtime, "size": st.st_size,
                "findings": [{"rule": h["RuleID"], "line": h["StartLine"]}
                             for h in still_dirty]}

for k in [k for k in state if k not in seen]:
    del state[k]

with open(state_file + ".tmp", "w") as fh:
    json.dump(state, fh)
os.replace(state_file + ".tmp", state_file)

# -- cass archive: forget conversations whose sources we scrubbed -----------
forgotten = 0
if cass and not dry and scrubbed_paths and os.path.exists(cass_bin):
    for p in scrubbed_paths:
        # mirror copies and live source files both appear as source_path in
        # cass; glob-match on the basename catches index entries either way.
        db = os.path.join(os.environ["CASS_DATA_DIR"], "agent_search.db")
        r = subprocess.run(
            [cass_bin, "forget", "--source-glob", f"**/{os.path.basename(p)}",
             "--apply", "--db", db, "--json"],
            capture_output=True, text=True)
        if r.returncode == 0:
            forgotten += 1
        else:
            print(f"cass forget failed for {p}: {r.stderr.strip()[:200]}", file=sys.stderr)

print(f"\n{scrubbed_files} secrets {'would be ' if dry else ''}redacted "
      f"across {len(to_scan)} files scanned ({skipped_recent} skipped: live/recent, "
      f"{skipped_short} skipped: <8 bytes)")
if forgotten:
    print(f"cass: forgot {forgotten} conversations (re-indexed clean on next incremental)")
if dry:
    print("(dry-run: no files changed, cass untouched)")
PYEOF
