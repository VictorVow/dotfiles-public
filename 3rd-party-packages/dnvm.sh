#!/bin/bash

# dotnet version manager
# https://github.com/dn-vm/dnvm/releases

# Check if dnvm is installed
if ! command -v dnvm &> /dev/null
then
    echo "dnvm is not installed. Installing now..."

    # Detect architecture
    ARCH=$(uname -m)
    if [ "$ARCH" = "x86_64" ]; then
        ARCH_SUFFIX="x64"
    elif [ "$ARCH" = "aarch64" ]; then
        ARCH_SUFFIX="arm64"
    else
        echo "Unsupported architecture: $ARCH"
        exit 1
    fi

    # Get the latest release download URL
    DOWNLOAD_URL=$(curl -s https://api.github.com/repos/dn-vm/dnvm/releases/latest \
        | grep "browser_download_url" \
        | grep "linux-${ARCH_SUFFIX}.tar.gz\"" \
        | grep -v ".sig" \
        | cut -d '"' -f 4)

    if [ -z "$DOWNLOAD_URL" ]; then
        echo "Failed to fetch dnvm download URL."
        exit 1
    fi

    # Download and extract to a temp directory
    TMP_DIR=$(mktemp -d)
    curl -fsSL "$DOWNLOAD_URL" | tar -xz -C "$TMP_DIR"

    # Run the self-install command
    "$TMP_DIR/dnvm" selfinstall

    # Clean up
    rm -rf "$TMP_DIR"

    echo "dnvm has been installed."
else
    echo "dnvm is already installed."
fi
