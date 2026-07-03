#!/usr/bin/env bash
# Shared config + helpers for the network-debugging scripts. Source this; don't run it.
#
# Topology these defaults describe (see docs/system/home-networking.md):
#   chief-win11-desktop ~~WiFi~~> primary Velop ==backhaul==> secondary Velop <~~WiFi~~ boss-laptop
#   lord-ubuntu ──wire──> primary Velop (the wired vantage point)
# IPs are DHCP leases — verify against the MACs in the doc if anything looks off.

NET_IF="${NET_IF:-wlp1s0}"                   # this machine's WiFi interface
NODE_NEAR="${NODE_NEAR:-192.168.x.x}"      # mesh node this machine associates to
NODE_FAR="${NODE_FAR:-192.168.x.x}"          # the other node (also the gateway)
WIRED_HOST="${WIRED_HOST:-192.168.x.x}"    # host wired to NODE_FAR (lord-ubuntu)
WIRED_SSH="${WIRED_SSH:-lord@lord-ubuntu}"   # Tailscale SSH — username MUST be lord
WIRED_TS_IP="${WIRED_TS_IP:-100.x.x.x}"     # lord's tailnet IP (ufw allows tailscale0)
DESKTOP_LAN="${DESKTOP_LAN:-192.168.x.x}"  # chief-win11-desktop LAN IP (ICMP firewalled!)
DESKTOP_SSH="${DESKTOP_SSH:-chief-win11}"    # ~/.ssh/config entry; remote shell is cmd.exe -> use &&
DESKTOP_TSNAME="${DESKTOP_TSNAME:-chief-win11-desktop}"

# One-line ping summary: "loss  min/avg/max/mdev". RF contention is bursty here —
# a single clean 20 s window proves nothing; repeat runs before concluding.
net_ping_summary() {
  local target="$1" count="${2:-100}" interval="${3:-0.2}" size="${4:-56}"
  ping -c "$count" -i "$interval" -s "$size" -q "$target" 2>&1 \
    | awk -F', ' '/packet loss/ {loss=$3} /^rtt/ {split($0,a," = "); rtt=a[2]} END {printf "%-8s %s\n", loss, rtt}'
}

# Median/p90/max from repeated `tailscale ping` (WireGuard path, works despite
# the desktop's ICMP firewall). Prints nothing per-sample; just the summary.
net_ts_ping_summary() {
  local target="$1" n="${2:-20}" out
  out=$(for _ in $(seq 1 "$n"); do
    timeout 5 tailscale ping --c 1 "$target" 2>/dev/null | grep -o 'in [0-9]*ms' || true
  done)
  echo "$out" | awk '{print $2+0}' | sort -n \
    | awk -v want="$n" 'NF {a[++c]=$1} END {if (!c) {print "no pongs (target offline or relay down)"; exit}
        m=int((c+1)/2); p=int(c*0.9); if (p<1) p=1
        printf "n=%d/%d min=%dms median=%dms p90=%dms max=%dms\n", c, want, a[1], a[m], a[p], a[c]}'
}

# Current association: BSSID, signal, PHY rates, retries. The associated BSSID's
# base MAC (last octet −1 or −2) identifies which node we're on.
net_link_summary() {
  iw dev "$NET_IF" link | grep -E 'Connected|SSID|freq|signal|bitrate'
  iw dev "$NET_IF" station dump | grep -E 'tx retries|tx failed'
}
