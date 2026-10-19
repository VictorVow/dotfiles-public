#!/usr/bin/env bash
# Capture a Gecko profile of the parent main thread while a problem is reproducing.
#
# Relaunches the profile with the profiler armed from startup, waits DURATION
# seconds, then dumps mid-flight with SIGUSR2 (no clean shutdown needed) and
# prints the profile path. Analyze it with ff-analyze-profile.py or load it at
# https://profiler.firefox.com. Firefox is left running with the profiler
# stopped.
#
# Notes:
#  - SIGUSR2 only writes a dump if MOZ_UPLOAD_DIR is set — this script sets it.
#  - Do NOT use `kill -34` (about:memory dump) early in startup: before the
#    handler is installed the default action kills the process.
#  - MOZ_PROFILER_SHUTDOWN (write on exit) proved unreliable mid-storm; the
#    SIGUSR2 path is what works.
#
# Usage: ff-profiler-capture.sh [-p PROFILE] [-d DURATION_S] [-o OUTDIR]
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"; source ./ff-lib.sh

PROFILE=VERTEX DURATION=90 OUTDIR="${TMPDIR:-/tmp}/ff-profiles"
while getopts "p:d:o:h" o; do case $o in
  p) PROFILE=$OPTARG;; d) DURATION=$OPTARG;; o) OUTDIR=$OPTARG;;
  h) grep '^#' "$0" | head -18; exit 0;;
  *) exit 2;;  # getopts already printed "illegal option"
esac; done
mkdir -p "$OUTDIR"

if [[ -n $(ff_main_pid "$PROFILE") ]]; then
  echo "quitting running instance of $PROFILE first..."
  ff_quit "$PROFILE"
fi

echo "launching $PROFILE with profiler armed (GeckoMain only)..."
MOZ_PROFILER_STARTUP=1 \
MOZ_PROFILER_STARTUP_FEATURES=js,stackwalk,cpu \
MOZ_PROFILER_STARTUP_FILTERS=GeckoMain \
MOZ_UPLOAD_DIR="$OUTDIR" \
setsid firefox -P "$PROFILE" >/dev/null 2>&1 &

sleep 15
MAIN=$(ff_main_pid "$PROFILE")
[[ -z $MAIN ]] && { echo "error: firefox did not start" >&2; exit 1; }
echo "capturing pid $MAIN for ${DURATION}s..."
sleep "$DURATION"

kill -USR2 "$MAIN"   # stop profiler + write dump to MOZ_UPLOAD_DIR
for _ in $(seq 1 20); do
  out=$(ls -t "$OUTDIR"/profile_*_"$MAIN".json 2>/dev/null | head -1) && [[ -n ${out:-} ]] && break
  sleep 3
done
[[ -z ${out:-} ]] && { echo "error: no dump appeared in $OUTDIR" >&2; exit 1; }
echo "profile written: $out"
