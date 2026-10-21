#!/usr/bin/env bash
# Toggle Chrome DevTools Protocol (CDP) remote debugging on a live Chromium-family
# browser, so an agent can attach with `chrome-devtools-mcp --browserUrl`.
#
# Unlike Firefox, Chromium-family browsers can open the debugging port on a running
# instance only when it was started with the flag — there is no toggle at runtime.
# So on/off both mean a clean quit (SIGTERM, session saved) and a relaunch.
#
#   on      quit, relaunch with --remote-debugging-port, wait for /json/version
#   off     quit, relaunch normally (do this when done: remote debugging disables
#           some security boundaries and bots may detect the CDP fingerprint)
#   status  is it running, and is the debugging port up?
#
# The CDP endpoint listens on 127.0.0.1:9223 (loopback only; Firefox uses 9222).
#
#   -b chromium|chrome|brave   which browser (default chromium)
#   -p NAME                    profile directory under the browser's config dir
#                              (default "Default"; ~ is the default profile)
#
# Usage: chromium-remote-debug.sh [-b BROWSER] [-p PROFILE] on|off|status
set -euo pipefail

BROWSER=chromium PORT=9223 PROFILE="Default"
while getopts "b:p:h" o; do case $o in
  b) BROWSER=$OPTARG;;
  p) PROFILE=$OPTARG;;
  h) grep '^#' "$0" | head -22; exit 0;;
  *) exit 2;;
esac; done
shift $((OPTIND - 1))
ACTION="${1:-status}"

case $BROWSER in
  chromium) BIN=chromium      ; CONFIG="$HOME/.config/chromium"      ;;
  chrome)   BIN=google-chrome ; CONFIG="$HOME/.config/google-chrome" ;;
  brave)    BIN=brave         ; CONFIG="$HOME/.config/BraveSoftware/Brave-Browser" ;;
  *) echo "unknown browser: $BROWSER (chromium|chrome|brave)" >&2; exit 2;;
esac

listening() { ss -ltn "sport = :$PORT" | grep -q LISTEN; }

# Find the browser main-process pid. Same Nix-wrapper gotcha as Firefox: match the
# real binary path under bin/, exclude the per-tab --type= helper processes, and
# never match our own command line.
main_pid() {
  ps -eo pid=,rss=,args= \
    | awk -v b="bin/$BIN" '$0 ~ b && $0 !~ /--type=/ && $0 !~ /awk|bash -c/' \
    | sort -k2 -rn | head -1 | awk '{print $1}'
}

wait_exit() {
  local t=0 timeout="${1:-60}"
  while [[ -n $(main_pid) ]]; do
    (( t >= timeout )) && { echo "error: $BROWSER still running after ${timeout}s" >&2; return 1; }
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
  setsid "$BIN" --user-data-dir="$CONFIG" "$@" >/dev/null 2>&1 &
}

status() {
  local pid; pid=$(main_pid)
  if [[ -z $pid ]]; then echo "$BROWSER: not running"; return; fi
  if in_debug_mode; then
    echo "$BROWSER: running (pid $pid) in REMOTE-DEBUG mode"
    listening "$PORT" && echo "  cdp :$PORT listening" || echo "  cdp :$PORT NOT listening (still starting?)"
  else
    echo "$BROWSER: running (pid $pid) normally (no remote debugging)"
  fi
}

case $ACTION in
  status) status ;;
  on)
    if in_debug_mode; then status; exit 0; fi
    if listening "$PORT"; then
      echo "error: port $PORT already taken by another process:" >&2
      ss -ltnp "sport = :$PORT" >&2; exit 1
    fi
    if [[ -n $(main_pid) ]]; then
      echo "quitting $BROWSER cleanly (session is saved)..."
      quit
    fi
    echo "launching $BROWSER with --remote-debugging-port $PORT (profile: $PROFILE)..."
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
    echo "quitting $BROWSER (remote-debug mode)..."
    quit
    echo "relaunching $BROWSER normally (profile: $PROFILE)..."
    launch --profile-directory="$PROFILE"
    sleep 5
    status
    ;;
  *) echo "usage: $0 [-b BROWSER] [-p PROFILE] on|off|status" >&2; exit 2 ;;
esac
