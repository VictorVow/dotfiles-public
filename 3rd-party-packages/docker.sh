#!/bin/bash

# https://docs.docker.com/engine/install/ubuntu/#install-using-the-repository

# Function to check if any of the given commands exist
command_exists() {
    for cmd in "$@"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            return 0
        fi
    done
    return 1
}

# Check if Docker and Docker Compose are installed
if command_exists docker "docker compose"; then
    echo "Docker and Docker Compose are already installed."
else
    echo "Docker or Docker Compose is not installed. Installing..."

    # Install required packages
    sudo apt-get install -y ca-certificates curl

    # Create a directory for the keyring and download Docker's GPG key
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    # Add the Docker repository to Apt sources
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Update package index again with the new repository
    sudo apt-get update

    # Install Docker, Docker CLI, containerd, Docker Buildx plugin, and Docker Compose plugin
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Verify installation
    echo "Docker and Docker Compose have been installed."
    docker --version
    docker-compose --version
    
    # [Executing the Docker Command Without Sudo (Optional)](https://www.digitalocean.com/community/tutorials/how-to-install-and-use-docker-on-ubuntu-20-04)
    sudo usermod -aG docker ${USER}
    echo "use `login ${USER}` to utilise Docker without sudo"
fi
