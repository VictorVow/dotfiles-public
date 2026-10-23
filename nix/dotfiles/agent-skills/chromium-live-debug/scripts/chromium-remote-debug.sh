#!/usr/bin/env bash
# Toggle Chrome DevTools Protocol (CDP) remote debugging on a Chromium-family
# browser instance, so an agent can attach with `chrome-devtools-mcp --browserUrl`.
#
# Unlike Firefox, Chromium-family browsers can open the debugging port on a running
# instance only when it was started with the flag — there is no toggle at runtime.
# So on/off both mean a clean quit (SIGTERM, session saved) and a relaunch.
#
# Instances are keyed by --user-data-dir (Chromium enforces one process per data
# dir). The default instance is the browser's normal config dir — your real,
# logged-in session. -u DIR targets a fully separate browser instance (own
# profile, own CDP port), so several debuggable instances — and the normal
# undebugged session — can run side by side.
#
#   on      quit the instance, relaunch with --remote-debugging-port, wait for
#           /json/version
#   off     quit, relaunch the instance normally (do this when done: remote
#           debugging disables some security boundaries and bots may detect the
#           CDP fingerprint)
#   stop    quit the instance without relaunching (for throwaway -u instances)
#   status  is this instance running, and is its debugging port up?
#   list    all running $BROWSER instances: pid, user-data-dir, debug port
#
# The default CDP endpoint listens on 127.0.0.1:9223 (loopback only; Firefox
# BiDi uses 9222). Each -u instance needs its own -P port.
#
#   -b chromium|chrome|brave   which browser (default chromium)
#   -p NAME                    profile directory inside the user-data-dir
#                              (default "Default"; ~ is the default profile)
#   -u DIR                     user-data-dir of the instance (default: the
#                              browser's normal config dir = your real session)
#   -P PORT                    CDP port (default 9223; unique per instance)
#
# Usage: chromium-remote-debug.sh [-b BROWSER] [-p PROFILE] [-u DIR] [-P PORT] on|off|stop|status|list
#
# Example — a second, isolated instance for an agent, attached by an MCP server
# registered with --browserUrl http://127.0.0.1:9224:
#   chromium-remote-debug.sh -u ~/.local/state/chrome-agent -P 9224 on
set -euo pipefail

BROWSER=chromium PORT=9223 PROFILE="Default" USER_DATA_DIR=""
while getopts "b:p:u:P:h" o; do case $o in
  b) BROWSER=$OPTARG;;
  p) PROFILE=$OPTARG;;
  u) USER_DATA_DIR=$OPTARG;;
  P) PORT=$OPTARG;;
  h) grep '^#' "$0" | head -37; exit 0;;
  *) exit 2;;
esac; done
shift $((OPTIND - 1))
ACTION="${1:-status}"

case $BROWSER in
  chromium) BIN=chromium     ; CONFIG="$HOME/.config/chromium" ;;
  chrome)   BIN=google-chrome; CONFIG="$HOME/.config/google-chrome" ;;
  brave)    BIN=brave-origin ; CONFIG="$HOME/.config/BraveSoftware/Brave-Browser" ;;
  *) echo "unknown browser: $BROWSER (chromium|chrome|brave)" >&2; exit 2;;
esac

# Regex matching the executable field ($2) of the real browser process —
# wrapper path (bin/<BIN>) or the store libexec/share path it execs into.
# Chromium: ungoogled-chromium wrapper execs .../libexec/chromium/chromium.
# Chrome: google-chrome wrapper is .../bin/google-chrome-stable → .../google/chrome/chrome.
# Brave (brave-origin): wrapper is .../bin/brave-origin → .../bin/brave.
BINRE="/(chromium|chrome|google-chrome-stable|brave)$"

USER_DATA_DIR="${USER_DATA_DIR:-$CONFIG}"

listening() { ss -ltn "sport = :$1" | grep -q LISTEN; }

# Find the main-process pid(s) of the instance using $USER_DATA_DIR. Match the
# executable field ($2) against $BINRE — the real binary under bin/ or libexec/ —
# exclude per-tab --type= helpers and our own command line. A process with no
# --user-data-dir flag uses the Chromium default ($CONFIG), so the default
# instance is found whether or not the flag was passed at launch.
main_pids() {
  ps -eo pid=,rss=,args= \
    | awk -v re="$BINRE" -v want="$USER_DATA_DIR" -v def="$CONFIG" '
        $3 ~ re && $0 !~ /--type=/ {
          udd = ""
          for (i = 4; i <= NF; i++)
            if ($i ~ /^--user-data-dir=/) { x = $i; sub(/^--user-data-dir=/, "", x); udd = x }
          if (udd == "") udd = def
          if (udd == want) print $1, $2
        }'
}

main_pid() { main_pids | sort -k2 -rn | head -1 | awk '{print $1}'; }

wait_exit() {
  local t=0 timeout="${1:-60}"
  while [[ -n $(main_pid) ]]; do
    (( t >= timeout )) && { echo "error: $BROWSER instance $USER_DATA_DIR still running after ${timeout}s" >&2; return 1; }
    sleep 3; t=$(( t + 3 ))
  done
}

quit() {
  local pid; pid=$(main_pid)
  [[ -z $pid ]] && return 0
  kill -TERM "$pid"
  wait_exit "${1:-60}"
}

in_debug_mode() {
  local pid; pid=$(main_pid)
  [[ -n $pid ]] && tr '\0' ' ' < "/proc/$pid/cmdline" | grep -q -- "--remote-debugging-port=$PORT"
}

launch() {
  setsid "$BIN" --user-data-dir="$USER_DATA_DIR" "$@" >/dev/null 2>&1 &
}

label() {
  if [[ $USER_DATA_DIR == "$CONFIG" ]]; then echo "$BROWSER (default profile dir)"
  else echo "$BROWSER instance $USER_DATA_DIR"; fi
}

status() {
  local pid; pid=$(main_pid)
  if [[ -z $pid ]]; then echo "$(label): not running"; return; fi
  if in_debug_mode; then
    echo "$(label): running (pid $pid) in REMOTE-DEBUG mode"
    listening "$PORT" && echo "  cdp :$PORT listening" || echo "  cdp :$PORT NOT listening (still starting?)"
  else
    echo "$(label): running (pid $pid) normally (no remote debugging)"
  fi
}

list_instances() {
  ps -eo pid=,args= \
    | awk -v re="$BINRE" -v def="$CONFIG" '
        $2 ~ re && $0 !~ /--type=/ {
          udd = ""; port = ""
          for (i = 3; i <= NF; i++) {
            if ($i ~ /^--user-data-dir=/)         { x = $i; sub(/^--user-data-dir=/, "", x);        udd = x }
            if ($i ~ /^--remote-debugging-port=/) { x = $i; sub(/^--remote-debugging-port=/, "", x); port = x }
          }
          if (udd == "") udd = def
          print $1 "\t" udd "\t" (port == "" ? "off" : port)
        }' \
    | while IFS=$'\t' read -r pid udd port; do
        printf "%s\tpid %s\tcdp %s\n" "$udd" "$pid" "$port"
      done
}

case $ACTION in
  status) status ;;
  list)   list_instances ;;
  on)
    if in_debug_mode; then status; exit 0; fi
    if listening "$PORT"; then
      echo "error: port $PORT already taken by another process:" >&2
      ss -ltnp "sport = :$PORT" >&2; exit 1
    fi
    if [[ -n $(main_pid) ]]; then
      echo "quitting $(label) cleanly (session is saved)..."
      quit
    fi
    echo "launching $(label) with --remote-debugging-port $PORT (profile: $PROFILE)..."
    launch --remote-debugging-port="$PORT" --profile-directory="$PROFILE"
    for _ in $(seq 1 40); do
      listening "$PORT" && curl -fsS "http://127.0.0.1:$PORT/json/version" >/dev/null 2>&1 && break
      sleep 3
    done
    status
    in_debug_mode && listening "$PORT" \
      || { echo "error: CDP endpoint did not come up within 120s" >&2; exit 1; }
    ;;
  off)
    if ! in_debug_mode; then status; exit 0; fi
    echo "quitting $(label) (remote-debug mode)..."
    quit
    echo "relaunching $(label) normally (profile: $PROFILE)..."
    launch --profile-directory="$PROFILE"
    sleep 5
    status
    ;;
  stop)
    if [[ -z $(main_pid) ]]; then status; exit 0; fi
    echo "quitting $(label)..."
    quit
    status
    ;;
  *) echo "usage: $0 [-b BROWSER] [-p PROFILE] [-u DIR] [-P PORT] on|off|stop|status|list" >&2; exit 2 ;;
esac
