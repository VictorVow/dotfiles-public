 #!/bin/bash

# https://code.visualstudio.com/docs/setup/linux 
 
# Check if code (Visual Studio Code) is installed
if ! command -v code &> /dev/null
then
    echo "Visual Studio Code is not installed. Installing now..."

    # Install wget and gpg if not already installed
    sudo apt-get install -y wget gpg

    # Download Microsoft's GPG key and convert it to a format compatible with apt
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg

    # Move the GPG key to the keyrings directory with appropriate permissions
    sudo install -D -o root -g root -m 644 packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg

    # Add the VS Code repository to the sources list
    echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null

    # Remove the downloaded GPG file
    rm -f packages.microsoft.gpg

    # Install the apt-transport-https package if not already installed
    sudo apt install -y apt-transport-https

    # Update the package list
    sudo apt update

    # Install Visual Studio Code
    sudo apt install -y code

    echo "Visual Studio Code has been installed."
else
    echo "Visual Studio Code is already installed."
fi
