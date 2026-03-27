#!/bin/bash

# Waydroid — Android container for Linux
# https://docs.waydro.id/usage/install-on-desktops
#
# Installs waydroid from the official repo (repo.waydro.id).
# Kernel modules and the waydroid-container service are managed by ansible.yml.
# After running ansible, initialise with:
#   waydroid init -s LINEAGE -r gapps

command_exists() { command -v "$1" >/dev/null 2>&1; }

if command_exists waydroid; then
    echo "Waydroid is already installed."
else
    echo "Installing Waydroid..."

    sudo apt-get install -y ca-certificates curl

    # Add GPG key
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://repo.waydro.id/waydroid.gpg \
        | sudo gpg --dearmor -o /etc/apt/keyrings/waydroid.gpg

    # Detect Ubuntu codename; fall back to noble if the repo doesn't support this release yet
    DISTRO=$(. /etc/os-release && echo "$VERSION_CODENAME")
    if ! curl -sf "https://repo.waydro.id/dists/$DISTRO/Release" >/dev/null 2>&1; then
        echo "Distro '$DISTRO' not in waydroid repo — falling back to noble"
        DISTRO=noble
    fi
    echo "deb [signed-by=/etc/apt/keyrings/waydroid.gpg] https://repo.waydro.id/ $DISTRO main" \
        | sudo tee /etc/apt/sources.list.d/waydroid.list >/dev/null

    # Install waydroid and kernel module extras (provides binder_linux for the running kernel)
    sudo apt-get update
    sudo apt-get install -y waydroid "linux-modules-extra-$(uname -r)"

    echo "Waydroid installed."
    echo "Next: run 'ansible-playbook ansible.yml --ask-become-pass' to enable the service."
    echo "Then: 'waydroid init -s LINEAGE -r gapps' to download images (~1.5 GB)."
fi
