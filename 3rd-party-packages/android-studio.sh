#!/bin/bash

# Check if Android Studio is installed
if [ -x "/opt/android-studio-2025.2.3/android-studio/bin/studio.sh" ]; then
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
 
