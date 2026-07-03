#!/usr/bin/env bash
# Snapshot this machine's WiFi hop: which node it's on, signal, PHY rate, retries.
# Judge with: signal better than -60 dBm = good RF; high "tx retries" with
# 0 "tx failed" = airtime contention (jitter), not weak signal.
#
# Usage: net-wifi-link.sh
set -euo pipefail
cd "$(dirname "$0")" && source ./net-lib.sh

net_link_summary
echo
echo "power_save: $(iw dev "$NET_IF" get power_save | awk '{print $3}')  (proven irrelevant to the jitter here, but note it)"
echo
echo "Node MACs on the LAN (associated BSSID base MAC identifies your node):"
ip neigh show dev "$NET_IF" | grep -E "^($NODE_NEAR|$NODE_FAR) " || echo "  (nodes not in neighbor table — ping them first)"
