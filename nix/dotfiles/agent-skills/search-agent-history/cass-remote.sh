#!/usr/bin/env bash
# cass-remote.sh <host> <cass args…>
#
# Runs cass on the named host and returns its stdout unchanged. Cass indexes are
# per-host; this is how the search-agent-history skill federates a query.
#
# Hosts (aliases in parens):
#   boss (desktop, local on boss-laptop)     → boss-laptop, /home/linuxbrew/.linuxbrew/bin/cass
#   lord (lord-ubuntu, server, local here)   → lord-ubuntu,  ~/.local/bin/cass
#
# SSH path (tailnet policy): lord-ubuntu can SSH to boss-laptop as `boss`;
# boss-laptop can SSH to lord-ubuntu only as `lord` (not `boss`).
#
# All output is passed through as-is (the caller asked for --json already).
# Exit codes: 0 ok, 2 unknown host, otherwise whatever cass/ssh returned.
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "usage: $0 <host> <cass args…>" >&2
  exit 2
fi

host=$1; shift
this_host=$(hostname)

# Resolve which cass binary to invoke on the local machine.
local_cass() {
  if command -v cass >/dev/null 2>&1; then
    command -v cass
  elif [ -x "$HOME/.local/bin/cass" ]; then
    echo "$HOME/.local/bin/cass"
  elif [ -x /home/linuxbrew/.linuxbrew/bin/cass ]; then
    echo /home/linuxbrew/.linuxbrew/bin/cass
  else
    return 1
  fi
}

case "$host" in
  boss|boss-laptop|desktop)
    if [ "$this_host" = "boss-laptop" ] || [ "$this_host" = "boss" ]; then
      exec timeout 30s "$(local_cass)" "$@"
    else
      exec timeout 45s ssh -o ConnectTimeout=5 -o BatchMode=yes boss@boss-laptop \
        "/home/linuxbrew/.linuxbrew/bin/cass $(printf '%q ' "$@")"
    fi
    ;;
  lord|lord-ubuntu|server)
    if [ "$this_host" = "lord-ubuntu" ]; then
      exec timeout 30s "$(local_cass)" "$@"
    else
      exec timeout 45s ssh -o ConnectTimeout=5 -o BatchMode=yes lord@lord-ubuntu \
        "\$HOME/.local/bin/cass $(printf '%q ' "$@")"
    fi
    ;;
  local)
    exec timeout 30s "$(local_cass)" "$@"
    ;;
  *)
    echo "unknown host: $host (expected: boss|desktop|lord|server|local)" >&2
    exit 2
    ;;
esac
