#!/bin/bash
set -euo pipefail

# https://tailscale.com/kb/1187/install-ubuntu-2204

# Check if tailscale is installed
if ! command -v tailscale &> /dev/null
then
    echo "Tailscale is not installed. Installing now..."

    # Install curl if it's not already installed
    sudo apt install -y curl

    # Download the Tailscale GPG signing key to the trusted keyrings directory
    sudo curl -fsSLo /usr/share/keyrings/tailscale-archive-keyring.gpg https://pkgs.tailscale.com/stable/ubuntu/noble.noarmor.gpg

    # Add the stable Tailscale repository to apt sources list
    echo "deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/ubuntu $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/tailscale.list

    # Update package lists and install Tailscale
    sudo apt update
    sudo apt install -y tailscale

    # Enable and start the tailscaled daemon (system service)
    sudo systemctl enable --now tailscaled

    echo "Tailscale has been installed. Run 'sudo tailscale up' to authenticate."
else
    echo "Tailscale is already installed."
fi
