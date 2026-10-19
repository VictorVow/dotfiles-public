#!/usr/bin/env bash
# TCP throughput matrix isolating each wireless segment, using the wired host as
# the vantage point (run net-deploy-iperf3.sh first). All tests are driven from
# this machine; remote ends run via SSH.
#
#   A/B  laptop <-> wired host   = own radio + BACKHAUL          (raw TCP)
#   C/D  desktop <-> wired host  = desktop radio only            (via tailnet¹)
#   E/F  desktop <-> laptop      = both radios + backhaul        (raw TCP)
#
# ¹ the desktop's WiFi is on the Windows *Public* firewall profile, which drops
#   inbound iperf3 even with an allow rule; its Tailscale interface is Private
#   and lord's ufw allows tailscale0 — so C/D ride the tailnet (direct LAN path,
#   WireGuard overhead ~30-40%: treat C/D as lower bounds).
#
# Usage: net-throughput.sh [-t SECONDS]
set -euo pipefail
cd "$(dirname "$0")" && source ./net-lib.sh
T=10
while getopts "t:h" o; do case $o in
  t) T=$OPTARG;; h) grep '^#' "$0" | head -16; exit 0;;
  *) exit 2;;  # getopts already printed "illegal option"
esac; done

MY_IP=$(ip -4 addr show "$NET_IF" | awk '/inet /{sub(/\/.*/,"",$2); print $2; exit}')
summary() { grep -E 'sender|receiver' | sed 's/^\[ *[0-9]*\] *//'; }

echo "== A) wired host -> here (wire + backhaul + own radio) =="
iperf3 -s -1 -D; sleep 1
ssh "$WIRED_SSH" "export LD_LIBRARY_PATH=/tmp; /tmp/iperf3 -c $MY_IP -t $T" 2>/dev/null | summary
echo "== B) here -> wired host (-R) =="
iperf3 -s -1 -D; sleep 1
ssh "$WIRED_SSH" "export LD_LIBRARY_PATH=/tmp; /tmp/iperf3 -c $MY_IP -t $T -R" 2>/dev/null | summary

echo "== C) desktop -> wired host via tailnet (desktop radio, NO backhaul) =="
ssh "$WIRED_SSH" 'export LD_LIBRARY_PATH=/tmp; nohup /tmp/iperf3 -s -1 -D >/dev/null 2>&1' 2>/dev/null; sleep 1
ssh "$DESKTOP_SSH" "iperf3 -c $WIRED_TS_IP -t $T" 2>/dev/null | summary
echo "== D) wired host -> desktop (-R) =="
ssh "$WIRED_SSH" 'export LD_LIBRARY_PATH=/tmp; nohup /tmp/iperf3 -s -1 -D >/dev/null 2>&1' 2>/dev/null; sleep 1
ssh "$DESKTOP_SSH" "iperf3 -c $WIRED_TS_IP -t $T -R" 2>/dev/null | summary

echo "== E) desktop -> here, raw TCP (both radios + backhaul; the streaming direction) =="
iperf3 -s -1 -D; sleep 1
ssh "$DESKTOP_SSH" "iperf3 -c $MY_IP -t $T" 2>/dev/null | summary
echo "== F) here -> desktop (-R) =="
iperf3 -s -1 -D; sleep 1
ssh "$DESKTOP_SSH" "iperf3 -c $MY_IP -t $T -R" 2>/dev/null | summary

echo
echo "Reading: backhaul capacity >= max(A,B). If E ≈ min(C..D), the desktop hop is"
echo "the end-to-end cap. Healthy baseline 2026-07-03: A=156 B=232 C=99 D=130 E=93 F=40 Mbps."
