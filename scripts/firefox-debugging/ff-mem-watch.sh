#!/usr/bin/env bash
# Watch a Firefox profile's process tree: total RSS, main-process RSS/CPU, biggest child.
# A healthy large session settles in the low GB with near-idle CPU. A pegged main
# process (~100% of one core) plus RSS growing hundreds of MB/min means a runaway
# loop — capture a profile with ff-profiler-capture.sh next.
#
# Usage: ff-mem-watch.sh [-p PROFILE] [-i INTERVAL_S] [-n COUNT]
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"; source ./ff-lib.sh

PROFILE=VERTEX INTERVAL=10 COUNT=0
while getopts "p:i:n:h" o; do case $o in
  p) PROFILE=$OPTARG;; i) INTERVAL=$OPTARG;; n) COUNT=$OPTARG;;
  h) grep '^#' "$0" | head -8; exit 0;;
  *) exit 2;;  # getopts already printed "illegal option"
esac; done

MAIN=$(ff_main_pid "$PROFILE")
[[ -z $MAIN ]] && { echo "no running firefox for profile $PROFILE" >&2; exit 1; }
echo "watching main pid $MAIN (profile $PROFILE); Ctrl-C to stop"

i=0
while :; do
  main_stat=$(ps -o rss=,%cpu= -p "$MAIN" 2>/dev/null) || { echo "main process exited"; exit 0; }
  total=$(ps -eo rss=,args= | awk '/firefox/ && !/awk/ {s+=$1} END {print int(s/1024)}')
  big=$(ps -eo rss=,pid=,args= | awk '/-contentproc/ && !/awk/' | sort -rn | head -1 \
        | awk '{printf "%dMB(pid %s)", $1/1024, $2}')
  printf 't=%(%H:%M:%S)T main=%dMB cpu=%s%% total=%dMB biggest_child=%s\n' -1 \
    "$(( $(awk '{print $1}' <<<"$main_stat") / 1024 ))" \
    "$(awk '{print $2}' <<<"$main_stat")" "$total" "${big:-none}"
  i=$(( i + 1 )); [[ $COUNT -gt 0 && $i -ge $COUNT ]] && break
  sleep "$INTERVAL"
done
