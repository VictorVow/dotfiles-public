#!/bin/bash

# Check if flatpak is installed
if ! command -v flatpak &> /dev/null
then
    echo "Flatpak is not installed. Installing now..."
    sudo apt install flatpak

    # Flathub setup
    # The --user flag is important because it means other commands won't require sudo(?) Flatpaks will be installed for my user only instead of system-wide
    flatpak remote-add --if-not-exists --user flathub https://dl.flathub.org/repo/flathub.flatpakrepo

    echo "Flatpak & Flathub has been installed."
else
    echo "Flatpak & Flathub is already installed."
fi

# Store all Flatpak package names that I've installed (and still have configs for) to an array
cd ~/.var/app || exit 1
launcher_array=($(ls -d */))
# echo "launcher_array1: ${launcher_array[@]}"

# Echo the type of the variable 'launcher_array'
echo "Type of launcher_array: $(declare -p launcher_array | cut -d ' ' -f 2)"

# Echo items 1, 2, and 7 (if they exist)
# echo "Item 1: ${launcher_array[0]}"
# echo "Item 2: ${launcher_array[1]}"
# echo "Item 7: ${launcher_array[6]}"

# Remove the trailing `/` from each item in the array
for i in "${!launcher_array[@]}"; do
    launcher_array[$i]="${launcher_array[$i]%/}"
done

# Loop through the array and replace the unwanted strings:
for ((i=0; i<${#launcher_array[@]}; i++)); do
  if [[ "${launcher_array[i]}" == *"moe.launcher.an-anime-game-launcher"* ]] || 
     [[ "${launcher_array[i]}" == *"moe.launcher.wavey-launcher"* ]]; then
    unset 'launcher_array[i]'
  fi
done

# Join the modified array back into a single string using spaces:
launcher_string="${launcher_array[*]}"
#echo "launcher_string3: $launcher_string"

# Install the filtered Flatpak packages
if [ -n "$launcher_string" ]; then
  flatpak install $launcher_string
else
  echo "No packages to install."
fi
