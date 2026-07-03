#!/usr/bin/env bash
# Deploy this machine's iperf3 to a remote Linux host's /tmp without root:
# copies the binary + its non-libc deps (libiperf, libsctp) and verifies via ldd.
# Remember to remove /tmp/iperf3* there when done.
#
# Usage: net-deploy-iperf3.sh [user@host]   (default: $WIRED_SSH)
set -euo pipefail
cd "$(dirname "$0")" && source ./net-lib.sh
DEST="${1:-$WIRED_SSH}"

scp -q /usr/bin/iperf3 \
    /usr/lib/x86_64-linux-gnu/libiperf.so.0* \
    /usr/lib/x86_64-linux-gnu/libsctp.so.1* \
    "$DEST":/tmp/
ssh "$DEST" 'chmod +x /tmp/iperf3 && export LD_LIBRARY_PATH=/tmp
  missing=$(ldd /tmp/iperf3 | grep -i "not found" || true)
  [ -n "$missing" ] && { echo "missing libs:"; echo "$missing"; exit 1; }
  echo "deployed: $(/tmp/iperf3 --version | head -1)"'
echo "run there with: LD_LIBRARY_PATH=/tmp /tmp/iperf3 ..."
