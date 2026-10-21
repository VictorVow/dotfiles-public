# shellcheck shell=bash
# shellcheck disable=SC2034  # vars are consumed by the sourcing script
# Shared boilerplate for scrub-transcripts.sh and report-exposed-secrets.sh.
# Source after `set -euo pipefail`, then call the ts_* helpers in order:
#   ts_init -> ts_defaults -> [arg parsing] -> ts_resolve "$@" -> ts_lock ->
#   ts_targets_json -> export ... -> python3
# Sets DIR CONF STATE_DIR STATE_FILE REPORT_DIR FILE_TARGETS DB_TARGETS
# CASS_DB FILE_TARGETS_JSON DB_TARGETS_JSON. Python-side helpers live in
# transcript_common.py (import via sys.path.insert(0, os.environ["DIR"])).

ts_init() {
  DIR="$(dirname "$0")"
  CONF="$DIR/gitleaks-scrub.toml"
  STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/transcript-scrub"
  STATE_FILE="$STATE_DIR/state.json"
  REPORT_DIR="$(mktemp -d)"
  trap 'rm -rf "$REPORT_DIR"' EXIT
}

# Default file targets (JSONL/JSON stores) + sqlite targets (opencode v1).
# cass raw-mirror blobs are NOT scanned: they're content-addressed, so splicing
# them would corrupt cass's blake3 verification — cass copies are handled via
# `cass forget` on the conversation + the agent_search.db scan.
ts_defaults() {
  CASS_DATA_DIR="${CASS_DATA_DIR:-$HOME/.local/share/coding-agent-search}"
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
}

# Positional args replace the default lists: *.db paths go to DB_TARGETS (and
# disable the cass archive scan), everything else to FILE_TARGETS.
ts_resolve() {
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
}

# Serialise runs between the two scripts: concurrent invocations would
# interleave gitleaks calls and overwrite each other's state file. Caller
# exits with its own code when this returns non-zero.
ts_lock() {
  mkdir -p "$STATE_DIR"
  [ -f "$STATE_FILE" ] || echo '{}' > "$STATE_FILE"
  exec 9>"$STATE_DIR/lock"
  flock -n 9 || { echo "another transcript-scrub run is in progress" >&2; return 1; }
}

ts_targets_json() {
  FILE_TARGETS_JSON="$(printf '%s\n' "${FILE_TARGETS[@]+"${FILE_TARGETS[@]}"}" | python3 -c 'import sys,json; print(json.dumps([l.rstrip("\n") for l in sys.stdin if l.strip()]))')"
  DB_TARGETS_JSON="$(printf '%s\n' "${DB_TARGETS[@]+"${DB_TARGETS[@]}"}" | python3 -c 'import sys,json; print(json.dumps([l.rstrip("\n") for l in sys.stdin if l.strip()]))')"
  export FILE_TARGETS_JSON DB_TARGETS_JSON
}
