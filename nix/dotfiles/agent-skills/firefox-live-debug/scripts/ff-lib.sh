#!/usr/bin/env bash
# Shared helpers for the firefox-debugging scripts. Source this; don't run it.

FF_BASE="${FF_BASE:-$HOME/.mozilla/firefox}"

# Resolve a profile name (e.g. VERTEX) or a profile path to its directory.
ff_profile_dir() {
  local name="$1" dir
  [[ $name == */* ]] && dir="$name" || dir="$FF_BASE/$name"
  [[ -d $dir ]] || { echo "error: profile dir not found: $dir" >&2; return 1; }
  realpath "$dir"
}

# Find the Firefox main-process pid for a profile: the process holding the
# profile's .parentlock open. Works for any build (Nix, Dev Edition tarball,
# taskbar-tab launches) however it was started; content processes don't hold it.
# (Matching "-P NAME" in argv missed Dev Edition, which starts without -P.)
ff_main_pid() {
  local dir; dir=$(ff_profile_dir "$1" 2>/dev/null) || return 0
  { find /proc/[0-9]*/fd -maxdepth 1 -lname "$dir/.parentlock" 2>/dev/null || true; } \
    | head -1 | cut -d/ -f3
}

# Every running Firefox: one TSV line per main process:
#   pid  profile (name under $FF_BASE, else full path)  type (build + version)  binary
# "Profile + type" is what the skill disambiguates on.
ff_running() {
  local link pid dir exe ini type name
  { find /proc/[0-9]*/fd -maxdepth 1 -lname '*/.parentlock' -printf '%h %l\n' 2>/dev/null || true; } \
    | while read -r link dir; do
      pid=${link#/proc/}; pid=${pid%/fd}; dir=${dir%/.parentlock}
      [[ -f $dir/prefs.js ]] || continue   # Dev Edition also locks its install dir
      exe=$(readlink "/proc/$pid/exe") || continue
      ini="$(dirname "$exe")/application.ini"
      # CodeName exists only on special builds ("Firefox Developer Edition")
      type=$(awk -F= '/^Name=/{n=$2} /^CodeName=/{c=$2} /^Version=/{v=$2} END{print (c?c:n)" "v}' "$ini" 2>/dev/null)
      name=${dir#"$(realpath "$FF_BASE")/"}
      printf '%s\t%s\t%s\t%s\n' "$pid" "$name" "${type:-unknown}" "$exe"
    done | sort -u
}

# Fill the array named $2 with the command line to relaunch profile $1 with,
# minus any remote-debug flags: the running instance's own argv (so Dev Edition
# relaunches as Dev Edition, a taskbar tab keeps its args), else the Nix default
# (same args as the "Firefox-Nix VERTEX" .desktop launcher).
ff_launch_cmd() {
  local profile="$1" pid a skip=0; local -n _out="$2"; _out=()
  pid=$(ff_main_pid "$profile")
  if [[ -z $pid ]]; then _out=(firefox -P "$profile" --name "$profile" --class="$profile"); return; fi
  local argv; mapfile -d '' -t argv < "/proc/$pid/cmdline"
  for a in "${argv[@]}"; do
    (( skip )) && { skip=0; continue; }
    case $a in
      --marionette) ;;
      --remote-debugging-port) skip=1 ;;
      --remote-debugging-port=*) ;;
      *) _out+=("$a") ;;
    esac
  done
}

# Wait until no main process for the profile remains.
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
