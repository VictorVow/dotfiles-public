#!/usr/bin/env bash
# html-thumbnailer — freedesktop thumbnailer that renders HTML pages for
# Dolphin/KIO previews via headless Chromium.
#
# Usage: html-thumbnailer.sh SIZE INPUT OUTPUT_PNG   (KIO passes a local path)
#
# Deployed by nix/modules/desktop.nix, which wraps this file with PATH pinned
# to Nix store tools and registers it as a .thumbnailer. Run standalone it uses
# whatever chromium/unzip/flock/setpriv are on PATH.
#
# Always outputs a 1024x1024 screenshot of the page at a desktop viewport;
# KIO scales it down to the size it asked for, so SIZE is unused.
#
# SingleFile "self-extracting" saves (<html data-sfz>) are a zip polyglot
# whose JS unpacks the page on load — screenshotting them directly only
# captures "Please wait..." (or times out on big pages). They're valid zips,
# so they're unzipped and the static index.html inside is rendered instead.
#
# KIO quirks this works around (KF 6.24 filepreviewjob.cpp):
#   - KIO caches per size tier (normal/large/x-large/xx-large), so the main
#     view and the larger Information panel preview are separate requests,
#     each of which would re-render. The full-size screenshot is therefore
#     kept in ~/.cache/html-thumbnailer (keyed on path+mtime+size), making
#     every request after the first a file copy. Per-file flock means
#     concurrent requests for one file wait and reuse that render.
#   - KIO launches one job per file *and* per size, all at once, so renders
#     take one of 2 flock slots and run at nice 19 — otherwise opening a
#     folder of HTML files spawns dozens of Chromiums at full CPU.
#   - KIO kills a preview after 2s and SIGKILLs the job if Dolphin cancels
#     it; setpriv --pdeathsig (on both timeout and Chromium, since it isn't
#     inherited across fork) kills Chromium too, rather than leaving it
#     orphaned and still rendering. A render that was killed is simply
#     retried next time the file is shown.
#
# All DNS is mapped to NOTFOUND so previewing a file never fetches remote
# resources (tracking pixels, CDNs) — only local/relative assets render.
# Don't add --blink-settings=scriptEnabled=false: with it headless Chromium
# silently writes no screenshot at all.

input=$2 out=$3
cache=${XDG_CACHE_HOME:-$HOME/.cache}/html-thumbnailer
key=$(stat -c '%n|%Y|%s' -- "$input" | md5sum | cut -d' ' -f1)
cached=$cache/$key.png
if [ -s "$cached" ]; then cp "$cached" "$out"; exit; fi

lockdir=${XDG_RUNTIME_DIR:-/tmp}/html-thumbnailer
mkdir -p "$cache" "$lockdir"
exec 7>"$lockdir/$key.lock"
flock 7
if [ -s "$cached" ]; then cp "$cached" "$out"; exit; fi
exec 8>"$lockdir/slot0" 9>"$lockdir/slot1"
until flock -n 8 || flock -n 9; do sleep 0.1; done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
if head -c 4096 "$input" | grep -q 'data-sfz'; then
  unzip -qq -o "$input" -d "$work/sfz" 2>/dev/null
  [ -f "$work/sfz/index.html" ] && input=$work/sfz/index.html
fi

setpriv --pdeathsig KILL -- timeout 30 \
  setpriv --pdeathsig KILL -- nice -n 19 chromium \
  --headless --disable-gpu --hide-scrollbars --mute-audio --no-first-run \
  --user-data-dir="$work/profile" \
  --host-resolver-rules="MAP * ~NOTFOUND" \
  --virtual-time-budget=2000 \
  --window-size=1024,1024 \
  --screenshot="$work/shot.png" "$input" >/dev/null 2>&1
[ -s "$work/shot.png" ] || exit 1
mv "$work/shot.png" "$cached.tmp" && mv "$cached.tmp" "$cached"
cp "$cached" "$out"
# Prune renders of files not previewed (or since changed) in 90 days.
find "$cache" -name '*.png' -atime +90 -delete
