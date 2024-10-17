#!/bin/bash

# https://brew.sh/

# Check if brew is installed
if ! command -v brew &> /dev/null
then
    echo "Homebrew is not installed. Installing now..."

    # Install Homebrew
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Add Homebrew to the PATH
    echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> ~/.bashrc
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

    echo "Homebrew has been installed and added to your PATH."
else
    echo "Homebrew is already installed."
fi
