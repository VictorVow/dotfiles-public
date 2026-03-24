#!/bin/bash
# Homebrew (Linux) — fills in packages not yet available in nixpkgs.
# https://brew.sh/
#
# Note: shell integration (eval "$(brew shellenv)") is handled by
# Home Manager's shell.nix — this script does NOT append to ~/.bashrc.

if ! command -v brew &>/dev/null; then
    echo "Homebrew is not installed. Installing now..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    echo "Homebrew has been installed."
else
    echo "Homebrew is already installed."
fi

# Save installed package list to file (overwrites if exists)
brew leaves | xargs brew list --versions > brew-packages.txt
echo "Brew packages list saved to brew-packages.txt"
