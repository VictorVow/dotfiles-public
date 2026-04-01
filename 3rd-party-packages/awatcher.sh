#!/bin/bash

# https://github.com/2e3s/awatcher
# Bundled ActivityWatch-compatible window/idle watcher + aw-server-rust.
# Exposes the ActivityWatch HTTP API on port 5600.

if command -v awatcher >/dev/null 2>&1; then
    echo "awatcher already installed ($(awatcher --version 2>&1 | head -1))."
    exit 0
fi

echo "Installing awatcher..."

ASSET_URL=$(curl -fsSL https://api.github.com/repos/2e3s/awatcher/releases/latest \
    | grep '"browser_download_url"' \
    | grep 'awatcher_.*_amd64\.deb' \
    | grep -v 'aw-awatcher' \
    | head -1 \
    | sed 's/.*"\(https[^"]*\)".*/\1/')

if [ -z "$ASSET_URL" ]; then
    echo "ERROR: Could not find awatcher .deb asset in latest release." >&2
    exit 1
fi

TMP=$(mktemp -d)
DEB="$TMP/awatcher.deb"

curl -fsSL "$ASSET_URL" -o "$DEB"
sudo dpkg -i "$DEB"
rm -rf "$TMP"

echo "awatcher installed: $(awatcher --version 2>&1 | head -1)"
