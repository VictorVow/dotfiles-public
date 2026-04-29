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

# Install packages declared in brew-packages.txt
BREW_LIST="$(dirname "$0")/../brew-packages.txt"
if [[ -f "$BREW_LIST" ]]; then
  echo "Installing packages from brew-packages.txt..."
  while IFS= read -r line; do
    pkg="${line%%#*}"   # strip inline comments
    pkg="${pkg// /}"    # trim whitespace
    [[ -z "$pkg" ]] && continue
    if brew list --formula "$pkg" &>/dev/null 2>&1; then
      echo "  already installed: $pkg"
    else
      echo "  installing: $pkg"
      brew install "$pkg"
    fi
  done < "$BREW_LIST"
fi
