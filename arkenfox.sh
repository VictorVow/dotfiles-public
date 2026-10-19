#!/bin/bash

# Each release, or whenever you modify your user-overrides.js
# https://github.com/arkenfox/user.js/wiki/3.4-Apply-&-Update-&-Maintain
# Run the MAINTAIN steps on ONE profile

# Set variables for file paths and profile names
PROFILE_PATH="/home/boss/.var/app/org.mozilla.firefox/.mozilla/firefox/"
MASTER_PROFILE="09muof4b.MASTER"
VAULT_PATH="/home/boss/Vaults/gocryptfs1/Browsers/1-OTHER/Arkenfox/"

# Run the MAINTAIN steps on the MASTER profile
cd "$PROFILE_PATH$MASTER_PROFILE" || exit 1
./updater.sh
./prefsCleaner.sh
echo "Ran the MAINTAIN steps on the MASTER profile"

# Copy the updated files back to a central location
cp -f prefsCleaner.sh "$VAULT_PATH"
cp -f updater.sh "$VAULT_PATH"
cp -f user.js "$VAULT_PATH"
cp -f user-overrides.js "$VAULT_PATH"
echo "Copied the updated files back to a central location"

# Copy the updated files to each remaining Firefox profile
for profile in 89q24drb.CIKFORUM w4do8yxw.DWEB; do
    cp -f "$VAULT_PATH"* "$PROFILE_PATH$profile/"
    echo "$profile done"
done
# kxnl5iqx.WORK - I don't want any prefs which block functionality
# 6nxpopo7.PLAIN - I don't want any prefs which block functionality
# w4q5aadv.LEISURE - because I've got stuff like different homepage
