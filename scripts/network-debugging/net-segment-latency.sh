#!/usr/bin/env bash
# Per-segment latency/loss from this machine, isolating each hop:
#   1. own radio hop            (ping near node)
#   2. + backhaul               (ping far node; delta vs #1 = backhaul cost)
#   3. + wire, forwarded path   (ping wired host; proves jitter is real forwarding
#                                jitter, not node-CPU ICMP slow-path)
#   4. end-to-end to desktop    (tailscale ping — raw ICMP is firewalled there)
# Optionally the desktop's own hop via SSH (the segment invisible from here).
#
# Usage: net-segment-latency.sh [-c COUNT] [-d]   (-d = include desktop-side ping via SSH)
set -euo pipefail
cd "$(dirname "$0")" && source ./net-lib.sh

COUNT=100 DESKTOP=0
while getopts "c:dh" o; do case $o in
  c) COUNT=$OPTARG;; d) DESKTOP=1;; h) grep '^#' "$0" | head -9; exit 0;;
esac; done

printf "%-38s " "1) radio hop -> near node ($NODE_NEAR):";  net_ping_summary "$NODE_NEAR" "$COUNT"
printf "%-38s " "2) + backhaul -> far node ($NODE_FAR):";   net_ping_summary "$NODE_FAR" "$COUNT"
printf "%-38s " "3) + wire -> wired host ($WIRED_HOST):";   net_ping_summary "$WIRED_HOST" "$COUNT"
printf "%-38s " "4) end-to-end ($DESKTOP_TSNAME):";         net_ts_ping_summary "$DESKTOP_TSNAME"
if (( DESKTOP )); then
  printf "%-38s "  "5) desktop -> its node (via SSH):"
  ssh "$DESKTOP_SSH" "ping -n 30 $NODE_FAR" 2>/dev/null | tail -2 | tr -d '\r' | tr '\n' ' '; echo
fi
echo
echo "Reading: (2)−(1) ≈ backhaul cost (healthy: +2-5 ms). Jitter in (1) that persists"
echo "in (3) is real airtime contention on your radio hop. Contention is BURSTY —"
echo "repeat runs before trusting a clean result."
