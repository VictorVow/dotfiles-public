#!/bin/bash
# Android Studio — official IDE for Android development.
#
# Primary: androidStudioPackages.stable in nix/modules/packages.nix (uses buildFHSEnv).
# This script is retained as a fallback. It detects the Nix version and skips
# the PPA install if it is already active.

# Skip if already installed via Nix
if command -v android-studio &>/dev/null; then
    echo "Android Studio is already installed via Nix. Skipping PPA install."
    exit 0
fi

# Check if installed: look for the /opt/android-studio directory (PPA installs
# there regardless of version) or a studio.sh binary on PATH.
if [ -d "/opt/android-studio" ] || command -v studio.sh &>/dev/null; then
    echo "Android Studio is already installed."
else
    echo "Android Studio is not installed. Installing Android Studio..."

    # Add the Android Studio PPA for Ubuntu
    sudo add-apt-repository ppa:maarten-fonville/android-studio

    # Update the package list
    sudo apt update

    # Install Android Studio
    sudo apt install -y android-studio
fi
