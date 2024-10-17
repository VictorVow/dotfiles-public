#!/bin/bash

# https://mullvad.net/en/help/install-mullvad-app-linux#ubuntu-debian 

# Check if mullvad-vpn is installed
if ! command -v mullvad &> /dev/null
then
    echo "Mullvad VPN is not installed. Installing now..."

    # Install curl if it's not already installed
    sudo apt install -y curl

    # Download the Mullvad PGP public key and store it in the trusted keyrings directory
    sudo curl -fsSLo /usr/share/keyrings/mullvad-keyring.asc https://repository.mullvad.net/deb/mullvad-keyring.asc

    # Add the stable Mullvad repository to apt sources list
    echo "deb [signed-by=/usr/share/keyrings/mullvad-keyring.asc arch=$( dpkg --print-architecture )] https://repository.mullvad.net/deb/stable $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/mullvad.list

    # Update package lists and install Mullvad VPN
    sudo apt update
    sudo apt install -y mullvad-vpn

    echo "Mullvad VPN has been installed."
else
    echo "Mullvad VPN is already installed."
fi
