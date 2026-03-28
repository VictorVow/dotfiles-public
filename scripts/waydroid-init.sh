#!/bin/bash
# scripts/waydroid-init.sh
#
# Initialises waydroid images with automatic SourceForge fallback.
#
# ota.waydro.id (waydroid's OTA server) returns 404 for all channels due to
# a known infrastructure issue. The OTA server is just a pointer to zip files
# hosted on SourceForge, so this script queries SourceForge RSS directly,
# downloads the images, and serves them via a local HTTP server so waydroid
# can complete its normal init process.
#
# Usage: sudo bash scripts/waydroid-init.sh [SYSTEM_TYPE] [ROOT_TYPE]
# Defaults: LINEAGE vanilla
#
# WARNING: -f (force) is always passed — existing images and app data are wiped.

set -euo pipefail

ARCH="waydroid_x86_64"
SYSTEM_TYPE="${1:-LINEAGE}"
ROOT_TYPE="${2:-vanilla}"
PORT=18080

# ── Probe ota.waydro.id ────────────────────────────────────────────────────
OTA_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    "https://ota.waydro.id/system/${ROOT_TYPE}/${ARCH}/${SYSTEM_TYPE}.json")

if [ "$OTA_STATUS" = "200" ]; then
    echo "ota.waydro.id is accessible — using standard init"
    waydroid init -f -s "$SYSTEM_TYPE" -r "$ROOT_TYPE"
    exit 0
fi

echo "ota.waydro.id returned HTTP $OTA_STATUS — falling back to SourceForge"
echo "(This is a server-side issue, not a local network problem)"
echo ""

# ── Find latest image URLs on SourceForge ─────────────────────────────────
get_zip_url() {
    # Parse SourceForge RSS for the latest .zip file URL for a given image category
    local category="$1"
    local rss="https://sourceforge.net/projects/waydroid/rss?path=/images/${category}/lineage/${ARCH}"
    curl -sf "$rss" \
        | grep -oP 'https://sourceforge\.net/projects/waydroid/files[^\s<>\]"]+\.zip' \
        | head -1
}

echo "Querying SourceForge for latest image URLs..."
SYS_SF=$(get_zip_url "system")
VEN_SF=$(get_zip_url "vendor")

if [ -z "$SYS_SF" ] || [ -z "$VEN_SF" ]; then
    echo "ERROR: Could not locate waydroid images on SourceForge." >&2
    echo "Browse manually: https://sourceforge.net/projects/waydroid/files/images/" >&2
    exit 1
fi

SYS_FILE=$(basename "$SYS_SF")
VEN_FILE=$(basename "$VEN_SF")
echo "  System: $SYS_FILE"
echo "  Vendor: $VEN_FILE"
echo ""

# ── Download images ────────────────────────────────────────────────────────
WORKDIR=$(mktemp -d)
HTTP_PID=""
cleanup() {
    [ -n "$HTTP_PID" ] && kill "$HTTP_PID" 2>/dev/null || true
    rm -rf "$WORKDIR"
}
trap cleanup EXIT

echo "Downloading system image..."
curl -L --progress-bar -o "$WORKDIR/$SYS_FILE" "${SYS_SF}/download"
echo "Downloading vendor image..."
curl -L --progress-bar -o "$WORKDIR/$VEN_FILE" "${VEN_SF}/download"

SYS_SIZE=$(stat -c%s "$WORKDIR/$SYS_FILE")
VEN_SIZE=$(stat -c%s "$WORKDIR/$VEN_FILE")

# ── Create OTA JSON files pointing at local HTTP server ───────────────────
cat > "$WORKDIR/system.json" <<EOF
{"response":[{"datetime":$(date +%s),"filename":"$SYS_FILE","id":"1","romtype":"UNOFFICIAL","size":$SYS_SIZE,"url":"http://127.0.0.1:$PORT/$SYS_FILE","version":"18.1"}]}
EOF
cat > "$WORKDIR/vendor.json" <<EOF
{"response":[{"datetime":$(date +%s),"filename":"$VEN_FILE","id":"1","romtype":"UNOFFICIAL","size":$VEN_SIZE,"url":"http://127.0.0.1:$PORT/$VEN_FILE","version":"18.1"}]}
EOF

# ── Serve via local HTTP and run init ──────────────────────────────────────
echo "Starting local HTTP server on port $PORT..."
python3 -m http.server $PORT --directory "$WORKDIR" --bind 127.0.0.1 >/dev/null 2>&1 &
HTTP_PID=$!
sleep 1

echo "Running waydroid init..."
waydroid init -f \
    -m "http://127.0.0.1:$PORT/system.json" \
    -v "http://127.0.0.1:$PORT/vendor.json"

echo ""
echo "Done. Run: waydroid session start && waydroid show-full-ui"
