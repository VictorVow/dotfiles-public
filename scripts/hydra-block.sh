#!/usr/bin/env bash
#
# hydra-block.sh — block Hydra's external-resources host at two layers at once.
#
# Layer 1 (name):   /etc/hosts null-route of assets.hydralauncher.gg. Stops the
#                   DNS lookup. Primary layer; immune to Cloudflare ECH.
# Layer 2 (packet): iptables/ip6tables TLS-SNI string match. Catches any
#                   connection that reached the handshake anyway (raw-IP or
#                   DoH-resolved). Matches the hostname, not the IP, so no
#                   collateral to other Cloudflare-fronted sites.
#
# assets.hydralauncher.gg served the remote bundle.js RCE slot plus benign
# static JSON (game-executables / steam-* catalogue filters). Blocking degrades
# gracefully — see EFFECT notes at the bottom.
#
# Usage:
#   sudo ./hydra-block.sh --enable            # turn on both layers
#   sudo ./hydra-block.sh --enable --persist  # ...and save firewall across reboot
#   sudo ./hydra-block.sh --disable           # turn off both layers
#   sudo ./hydra-block.sh --enable-fw         # firewall layer only (for systemd boot unit)
#   ./hydra-block.sh --status                 # report each layer (hosts needs no root)
#
set -euo pipefail

HOST="assets.hydralauncher.gg"
HOSTS_FILE="${HOSTS_FILE:-/etc/hosts}"
MARKER="# hydra-block"                 # sentinel for our hosts lines
COMMENT="hydra-block"                  # tag for our firewall rules
REJECT=(--reject-with tcp-reset)

usage() { grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }
require_root() { [[ $EUID -eq 0 ]] || { echo "error: --$1 needs root. Re-run with sudo." >&2; exit 1; }; }

# ---- Layer 1: /etc/hosts -------------------------------------------------
hosts_enabled() { grep -qF "$MARKER" "$HOSTS_FILE"; }

hosts_enable() {
  if hosts_enabled; then echo "  [hosts] already blocked"; return; fi
  { printf '0.0.0.0 %s %s\n' "$HOST" "$MARKER"
    printf '::1 %s %s\n'     "$HOST" "$MARKER"; } >> "$HOSTS_FILE"
  echo "  [hosts] block added"
}

hosts_disable() {
  if ! hosts_enabled; then echo "  [hosts] not blocked"; return; fi
  local tmp; tmp="$(mktemp)"
  grep -vF "$MARKER" "$HOSTS_FILE" > "$tmp"
  cat "$tmp" > "$HOSTS_FILE"          # preserve /etc/hosts perms/owner
  rm -f "$tmp"
  echo "  [hosts] block removed"
}

# ---- Layer 2: firewall (SNI string match) --------------------------------
fw_rule=(OUTPUT -p tcp --dport 443
  -m string --algo bm --string "$HOST"
  -m comment --comment "$COMMENT"
  -j REJECT "${REJECT[@]}")

fw_enabled() { iptables -C "${fw_rule[@]}" 2>/dev/null; }

fw_enable() {
  if fw_enabled; then echo "  [fw] already enabled"; return; fi
  iptables  -A "${fw_rule[@]}"
  ip6tables -A "${fw_rule[@]}"
  echo "  [fw] SNI block enabled (IPv4 + IPv6)"
}

fw_disable() {
  local removed=0
  while iptables  -C "${fw_rule[@]}" 2>/dev/null; do iptables  -D "${fw_rule[@]}"; removed=1; done
  while ip6tables -C "${fw_rule[@]}" 2>/dev/null; do ip6tables -D "${fw_rule[@]}"; removed=1; done
  [[ $removed -eq 1 ]] && echo "  [fw] SNI block removed" || echo "  [fw] not enabled"
}

fw_persist() {
  if command -v netfilter-persistent >/dev/null; then
    netfilter-persistent save && echo "  [fw] saved via netfilter-persistent"
  elif [[ -d /etc/iptables ]]; then
    iptables-save  > /etc/iptables/rules.v4
    ip6tables-save > /etc/iptables/rules.v6
    echo "  [fw] saved to /etc/iptables/rules.v{4,6}"
  else
    echo "  [fw] WARN: no persistence tool found; rules will not survive reboot" >&2
  fi
}

# ---- dispatch ------------------------------------------------------------
want_persist=0
for a in "${@:2}"; do [[ "$a" == "--persist" ]] && want_persist=1; done

case "${1:-}" in
  --enable)
    require_root enable
    echo "enabling hydra-block:"
    hosts_enable
    fw_enable
    [[ $want_persist -eq 1 ]] && fw_persist
    echo "done."
    ;;
  --enable-fw)
    require_root enable-fw
    echo "enabling hydra-block firewall layer:"
    fw_enable
    echo "done."
    ;;
  --disable)
    require_root disable
    echo "disabling hydra-block:"
    hosts_disable
    fw_disable
    [[ $want_persist -eq 1 ]] && fw_persist   # persist the *removal* too, if asked
    echo "done."
    ;;
  --status)
    if hosts_enabled; then echo "[hosts] BLOCKED"; else echo "[hosts] allowed"; fi
    if [[ $EUID -eq 0 ]]; then
      if fw_enabled; then echo "[fw]    ENABLED"; else echo "[fw]    disabled"; fi
    else
      echo "[fw]    (run with sudo to read firewall state)"
    fi
    ;;
  -h|--help) usage 0 ;;
  *) echo "error: expected --enable | --disable | --status [--persist]" >&2; usage 1 ;;
esac

# ---------------------------------------------------------------------------
# EFFECT while blocked (all fail gracefully — no crashes):
#   • Catalogue genre/tag/publisher/developer filters won't populate.
#   • Playtime / running-game detection loses its remote executable map
#     (process-watcher.ts catches the failure → empty map, still runs).
# Unaffected: downloads, auth, library/sync, game icons (cdn.losbroxas.org),
# and the main API (hydra-api-*.losbroxas.org) — all on other hosts.
#
# LIMITATIONS:
#   • Layer 2 can't see the SNI if Cloudflare enables Encrypted ClientHello
#     (ECH); Layer 1 (hosts) is unaffected, which is why it's primary.
#   • Layer 2 needs the xt_string kernel module (auto-loaded by iptables).
# ---------------------------------------------------------------------------
