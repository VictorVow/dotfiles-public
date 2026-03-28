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
# Defaults to GAPPS (Google services included). Pass "VANILLA" as first arg
# for a no-GApps build.
#
# Usage: sudo bash scripts/waydroid-init.sh [SYS_TYPE]
#        sudo bash scripts/waydroid-init.sh          # GAPPS (default)
#        sudo bash scripts/waydroid-init.sh VANILLA
#
# WARNING: always passes -f (force) — existing images and app data are wiped.

set -euo pipefail

ARCH="waydroid_x86_64"
ROM_TYPE="lineage"
SYS_TYPE="${1:-GAPPS}"   # GAPPS, VANILLA, or FOSS
PORT=18080

# ── Probe ota.waydro.id ────────────────────────────────────────────────────
OTA_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    "https://ota.waydro.id/system/${ROM_TYPE}/${ARCH}/${SYS_TYPE}.json")

if [ "$OTA_STATUS" = "200" ]; then
    echo "ota.waydro.id is accessible — using standard init"
    waydroid init -f -r "$ROM_TYPE" -s "$SYS_TYPE"
    exit 0
fi

echo "ota.waydro.id returned HTTP $OTA_STATUS — falling back to SourceForge"
echo "(This is a server-side issue, not a local network problem)"
echo ""

# ── Find latest image URLs on SourceForge ─────────────────────────────────
#
# SourceForge RSS paths (discovered empirically):
#   system: /images/system/lineage/waydroid_x86_64/
#   vendor: /images/vendor/waydroid_x86_64/         (no 'lineage' subdirectory)
#
# Note: sed -n '1p' instead of head -1 to avoid SIGPIPE under set -o pipefail.

get_zip_url() {
    local rss_path="$1"
    local variant_filter="${2:-}"  # optional substring to filter filename (e.g. GAPPS, VANILLA)
    local rss_content
    # Capture full RSS before grepping to avoid SIGPIPE from head -1 in pipefail mode
    rss_content=$(curl -sf "https://sourceforge.net/projects/waydroid/rss?path=${rss_path}") || {
        echo ""
        return 0
    }
    local pattern="https://sourceforge\.net/projects/waydroid/files[^\s<>\"]+\.zip"
    if [ -n "$variant_filter" ]; then
        pattern="https://sourceforge\.net/projects/waydroid/files[^\s<>\"]+${variant_filter}[^\s<>\"]+\.zip"
    fi
    # grep -oP exits 1 on no match; || true prevents set -e from aborting
    printf '%s\n' "$rss_content" | grep -oP "$pattern" | sed -n '1p' || true
}

echo "Querying SourceForge for latest image URLs..."

# System image: try requested SYS_TYPE first, fall back to VANILLA
SYS_SF=$(get_zip_url "/images/system/lineage/${ARCH}" "$SYS_TYPE")
if [ -z "$SYS_SF" ] && [ "$SYS_TYPE" != "VANILLA" ]; then
    echo "  $SYS_TYPE system image not found, trying VANILLA..."
    SYS_SF=$(get_zip_url "/images/system/lineage/${ARCH}" "VANILLA")
    SYS_TYPE="VANILLA"
fi

# Vendor image (single variant — no GAPPS/VANILLA split)
VEN_SF=$(get_zip_url "/images/vendor/${ARCH}" "")

if [ -z "$SYS_SF" ] || [ -z "$VEN_SF" ]; then
    echo "ERROR: Could not locate waydroid images on SourceForge." >&2
    echo "Browse manually: https://sourceforge.net/projects/waydroid/files/images/" >&2
    exit 1
fi

SYS_FILE=$(basename "$SYS_SF")
VEN_FILE=$(basename "$VEN_SF")
echo "  System ($SYS_TYPE): $SYS_FILE"
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

# ── Create OTA JSON files in the paths waydroid constructs from the channel ─
# waydroid builds: {channel}/{rom_type}/{arch}/{sys_type}.json  (system)
#                  {channel}/{arch}/MAINLINE.json               (vendor)
mkdir -p "$WORKDIR/system/${ROM_TYPE}/${ARCH}"
mkdir -p "$WORKDIR/vendor/${ARCH}"

cat > "$WORKDIR/system/${ROM_TYPE}/${ARCH}/${SYS_TYPE}.json" <<EOF
{"response":[{"datetime":$(date +%s),"filename":"$SYS_FILE","id":"1","romtype":"unofficial","size":$SYS_SIZE,"url":"http://127.0.0.1:$PORT/$SYS_FILE","version":"20.0"}]}
EOF
cat > "$WORKDIR/vendor/${ARCH}/MAINLINE.json" <<EOF
{"response":[{"datetime":$(date +%s),"filename":"$VEN_FILE","id":"1","romtype":"unofficial","size":$VEN_SIZE,"url":"http://127.0.0.1:$PORT/$VEN_FILE","version":"20.0"}]}
EOF

# ── Serve via local HTTP and run init ──────────────────────────────────────
echo "Starting local HTTP server on 127.0.0.1:$PORT..."
python3 -m http.server $PORT --directory "$WORKDIR" --bind 127.0.0.1 >/dev/null 2>&1 &
HTTP_PID=$!
sleep 1

echo "Running waydroid init..."
waydroid init -f -r "$ROM_TYPE" -s "$SYS_TYPE" \
    -c "http://127.0.0.1:$PORT/system" \
    -v "http://127.0.0.1:$PORT/vendor"

echo ""
echo "Done. Run: waydroid session start && waydroid show-full-ui"
