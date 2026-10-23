#!/usr/bin/env bash
# Shared helpers for the firefox-debugging scripts. Source this; don't run it.

FF_BASE="${FF_BASE:-$HOME/.mozilla/firefox}"

# Resolve a profile name (e.g. VERTEX) to its directory.
ff_profile_dir() {
  local name="$1"
  local dir="$FF_BASE/$name"
  [[ -d $dir ]] || { echo "error: profile dir not found: $dir" >&2; return 1; }
  echo "$dir"
}

# Find the real Firefox main-process pid for a profile.
#
# Gotchas this handles (learned the hard way):
#  - The Nix `firefox` is a wrapper; naive `pgrep -f` can match the launching
#    bash or even the caller's own command line (self-match deadlock).
#  - Content processes also match "firefox"; the parent is the one whose args
#    are "bin/firefox -P <profile>" without -contentproc.
ff_main_pid() {
  local profile="$1"
  ps -eo pid=,rss=,args= \
    | awk -v p="-P $profile" '$0 ~ "bin/firefox" && $0 ~ p && $0 !~ /-contentproc/ && $0 !~ /awk|bash -c/' \
    | sort -k2 -rn | head -1 | awk '{print $1}'
}

# Wait until no main process for the profile remains. Uses ff_main_pid, not
# pgrep, to avoid matching ourselves.
ff_wait_exit() {
  local profile="$1" timeout="${2:-180}" t=0
  while [[ -n $(ff_main_pid "$profile") ]]; do
    (( t >= timeout )) && { echo "error: firefox ($profile) still running after ${timeout}s" >&2; return 1; }
    sleep 3; t=$(( t + 3 ))
  done
}

# Politely quit the profile's Firefox (SIGTERM = clean shutdown, session saved).
ff_quit() {
  local profile="$1"
  local pid; pid=$(ff_main_pid "$profile")
  [[ -z $pid ]] && return 0
  kill -TERM "$pid"
  ff_wait_exit "$profile" "${2:-180}"
}
