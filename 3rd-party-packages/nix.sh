 #!/bin/bash

# https://github.com/DeterminateSystems/nix-installer

# Check if nix is installed
if ! command -v nix &> /dev/null
then
    echo "Nix is not installed. Installing now..."

    curl -fsSL https://install.determinate.systems/nix | sh -s -- install

    echo "Nix has been installed."
else
    echo "Nix is already installed."
fi
