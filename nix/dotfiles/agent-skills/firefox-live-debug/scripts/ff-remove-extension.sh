#!/usr/bin/env bash
# Durably remove an extension from a Firefox profile (the fix of last resort).
#
# Use when disabling via about:addons doesn't stick — a wedged browser can fail
# to persist the disable to addonStartup.json.lz4, so the extension keeps
# loading on every restart. Editing extensions.json by hand does NOT work
# either; Firefox ignores/overwrites it.
#
# What it does (Firefox must be closed; the script quits it if running):
#  1. moves the extension's XPI out of <profile>/extensions/ into a backup dir
#  2. deletes addonStartup.json.lz4 (Firefox regenerates it on next start)
# Reinstall later from the backed-up XPI or from AMO.
#
# Find the extension id with:  ff-list-extensions.sh, or the analyze script's output.
#
# Usage: ff-remove-extension.sh -x 'EXTENSION_ID' [-p PROFILE]
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"; source ./ff-lib.sh

PROFILE=VERTEX EXT_ID=""
while getopts "p:x:h" o; do case $o in
  p) PROFILE=$OPTARG;; x) EXT_ID=$OPTARG;;
  h) grep '^#' "$0" | head -16; exit 0;;
  *) exit 2;;  # getopts already printed "illegal option"
esac; done
[[ -z $EXT_ID ]] && { echo "usage: $0 -x 'EXTENSION_ID' [-p PROFILE]" >&2; exit 1; }

DIR=$(ff_profile_dir "$PROFILE")
XPI="$DIR/extensions/$EXT_ID.xpi"
[[ -f $XPI ]] || { echo "error: $XPI not found (check the id, including any {braces})" >&2; exit 1; }

BACKUP="$DIR-removed-extensions"
mkdir -p "$BACKUP"

if [[ -n $(ff_main_pid "$PROFILE") ]]; then
  echo "quitting firefox ($PROFILE)..."
  ff_quit "$PROFILE"
fi

mv -v "$XPI" "$BACKUP/"
[[ -f $DIR/addonStartup.json.lz4 ]] && mv -v "$DIR/addonStartup.json.lz4" "$BACKUP/addonStartup.json.lz4.$(date +%s)"
echo "done — start firefox normally; the extension will be gone. XPI kept in $BACKUP"
