#!/bin/bash

# https://signal.org/download/linux/

# Check if signal-desktop is installed
if ! command -v signal-desktop &> /dev/null
then
    echo "Signal Desktop is not installed. Installing now..."

    # Step 1: Install the official public software signing key
    wget -O- https://updates.signal.org/desktop/apt/keys.asc | gpg --dearmor > signal-desktop-keyring.gpg
    cat signal-desktop-keyring.gpg | sudo tee /usr/share/keyrings/signal-desktop-keyring.gpg > /dev/null

    # Step 2: Add the Signal repository to the list of repositories
    echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/signal-desktop-keyring.gpg] https://updates.signal.org/desktop/apt xenial main' | sudo tee /etc/apt/sources.list.d/signal-xenial.list

    # Step 3: Update the package database and install Signal Desktop
    sudo apt update && sudo apt install -y signal-desktop

    # Clean up the temporary GPG keyring file
    rm -f signal-desktop-keyring.gpg

    echo "Signal Desktop has been installed."
else
    echo "Signal Desktop is already installed."
fi
