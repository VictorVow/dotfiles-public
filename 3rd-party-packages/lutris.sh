#!/bin/bash

# Check if Lutris is installed
if dpkg -l | grep -q "^ii  lutris "; then
    echo "Lutris is already installed."
else
    echo "Lutris is not installed. Installing Lutris..."
    
    # Add the Lutris PPA for Ubuntu 
    # COMMENTED OUT - this doesn't seem to keep updating in-time with each new Ubuntu release so the repo stays disabled for long periods. Instead swapped to the Debian install instructions
    # sudo add-apt-repository -y ppa:lutris-team/lutris
    
    # Install repo for Debian
    echo "deb [signed-by=/etc/apt/keyrings/lutris.gpg] https://download.opensuse.org/repositories/home:/strycore/Debian_12/ ./" | sudo tee /etc/apt/sources.list.d/lutris.list > /dev/null
    wget -q -O- https://download.opensuse.org/repositories/home:/strycore/Debian_12/Release.key | gpg --dearmor | sudo tee /etc/apt/keyrings/lutris.gpg > /dev/null
    
    # Update the package list
    sudo apt update
    
    # Install Lutris
    sudo apt install -y lutris
fi
 
