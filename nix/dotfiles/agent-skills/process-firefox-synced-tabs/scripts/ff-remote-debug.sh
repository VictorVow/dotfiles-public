#!/usr/bin/env bash
# Toggle remote-debug mode (Marionette + WebDriver BiDi) on a live Firefox profile,
# so an agent can attach with `firefox-devtools-mcp --connect-existing`.
#
# Firefox can only enable the remote agent at startup, so on/off both mean a clean
# quit (SIGTERM — session saved) and a relaunch; tabs come back via session restore.
#
#   on      quit, relaunch with --marionette --remote-debugging-port, wait for ports
#   off     quit, relaunch normally (do this when done: Marionette sets
#           navigator.webdriver=true in every tab, which trips bot detection)
#   status  is it running, and is it in remote-debug mode?
#
# Marionette listens on 127.0.0.1:2828, BiDi on 127.0.0.1:9222 (loopback only).
#
# Usage: ff-remote-debug.sh [-p PROFILE] on|off|status
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"; source ./ff-lib.sh

PROFILE=VERTEX MARIONETTE_PORT=2828 BIDI_PORT=9222
while getopts "p:h" o; do case $o in
  p) PROFILE=$OPTARG;;
  h) grep '^#' "$0" | head -16; exit 0;;
  *) exit 2;;  # getopts already printed "illegal option"
esac; done
shift $((OPTIND - 1))
ACTION="${1:-status}"
ff_profile_dir "$PROFILE" >/dev/null

listening() { ss -ltn "sport = :$1" | grep -q LISTEN; }

# Same args as the "Firefox-Nix VERTEX" .desktop launcher, plus any extras.
launch() {
  setsid firefox -P "$PROFILE" --name "$PROFILE" --class="$PROFILE" "$@" >/dev/null 2>&1 &
}

in_debug_mode() {
  local pid; pid=$(ff_main_pid "$PROFILE")
  [[ -n $pid ]] && tr '\0' ' ' < "/proc/$pid/cmdline" | grep -q -- '--marionette'
}

status() {
  local pid; pid=$(ff_main_pid "$PROFILE")
  if [[ -z $pid ]]; then echo "$PROFILE: not running"; return; fi
  if in_debug_mode; then
    echo "$PROFILE: running (pid $pid) in REMOTE-DEBUG mode"
    listening $MARIONETTE_PORT && echo "  marionette :$MARIONETTE_PORT listening" || echo "  marionette :$MARIONETTE_PORT NOT listening (still starting?)"
    listening $BIDI_PORT       && echo "  bidi       :$BIDI_PORT listening"       || echo "  bidi       :$BIDI_PORT NOT listening (still starting?)"
  else
    echo "$PROFILE: running (pid $pid) normally (no remote debugging)"
  fi
}

case $ACTION in
  status) status ;;
  on)
    if in_debug_mode; then status; exit 0; fi
    if listening $MARIONETTE_PORT || listening $BIDI_PORT; then
      echo "error: port $MARIONETTE_PORT or $BIDI_PORT already taken by another process:" >&2
      ss -ltnp "( sport = :$MARIONETTE_PORT or sport = :$BIDI_PORT )" >&2; exit 1
    fi
    if [[ -n $(ff_main_pid "$PROFILE") ]]; then
      echo "quitting $PROFILE cleanly (session is saved)..."
      ff_quit "$PROFILE"
    fi
    echo "launching $PROFILE with --marionette --remote-debugging-port $BIDI_PORT..."
    launch --marionette --remote-debugging-port "$BIDI_PORT"
    for _ in $(seq 1 60); do
      listening $MARIONETTE_PORT && listening $BIDI_PORT && break
      sleep 2
    done
    status
    in_debug_mode && listening $MARIONETTE_PORT && listening $BIDI_PORT \
      || { echo "error: remote-debug ports did not come up within 120s" >&2; exit 1; }
    ;;
  off)
    if ! in_debug_mode; then status; exit 0; fi
    echo "quitting $PROFILE (remote-debug mode)..."
    ff_quit "$PROFILE"
    echo "relaunching $PROFILE normally..."
    launch
    sleep 5
    status
    ;;
  *) echo "usage: $0 [-p PROFILE] on|off|status" >&2; exit 2 ;;
esac
