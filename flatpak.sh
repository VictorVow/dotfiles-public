#!/bin/bash
# Flatpak setup — Flathub remote + reinstall previously installed apps.
#
# flatpak itself is installed via ansible.yml (system-level apt package).
# Run this script AFTER ansible has completed.
#
# Home Manager activation also ensures the Flathub user remote is present
# on every `hms`, but this script is useful for initial setup and for
# reinstalling apps after a system migration.

if ! command -v flatpak &>/dev/null; then
    echo "flatpak is not installed. Run ansible first:"
    echo "  ansible-playbook ansible.yml --ask-become-pass"
    exit 1
fi

# Ensure the Flathub user remote is configured.
# --user: installs for this user only (no sudo required).
flatpak remote-add --if-not-exists --user flathub https://dl.flathub.org/repo/flathub.flatpakrepo
echo "Flathub user remote is configured."

# ── Reinstall previously installed apps from ~/.var/app ───────────────────────
# Scans ~/.var/app for app IDs (leftover config dirs from previous installs)
# and reinstalls them. Useful when migrating to a new system or after a reinstall.
# Excludes anime game launchers.

if [ ! -d "$HOME/.var/app" ]; then
    echo "No ~/.var/app directory found — skipping app reinstall."
    exit 0
fi

cd ~/.var/app || exit 1
launcher_array=($(ls -d */))

# Remove trailing `/` from each entry
for i in "${!launcher_array[@]}"; do
    launcher_array[$i]="${launcher_array[$i]%/}"
done

# Filter out entries that should not be reinstalled
for ((i=0; i<${#launcher_array[@]}; i++)); do
  if [[ "${launcher_array[i]}" == *"moe.launcher.an-anime-game-launcher"* ]] ||
     [[ "${launcher_array[i]}" == *"moe.launcher.wavey-launcher"* ]]; then
    unset 'launcher_array[i]'
  fi
done

launcher_string="${launcher_array[*]}"

if [ -n "$launcher_string" ]; then
    echo "Reinstalling Flatpak apps: $launcher_string"
    flatpak install --user $launcher_string
else
    echo "No packages to reinstall."
fi
