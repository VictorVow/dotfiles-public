#!/usr/bin/env bash
# ts-html-thumbs.sh — fill TagSpaces' .ts/*.jpg thumbnails for HTML files by
# reusing the Dolphin html-thumbnailer (scripts/html-thumbnailer.sh) for the
# render, then scaling to TagSpaces' 500px JPEG sidecars with ffmpeg.
#
# Usage: ts-html-thumbs.sh DIR [DIR...]
#   Renders DIR/*.html into DIR/.ts/<name>.html.jpg. Skips thumbs that already
#   exist and are newer than the source file (same staleness rule TagSpaces
#   uses). The thumbnailer's own cache makes repeat runs cheap.
#
# Depends on: html-thumbnailer (located via PATH, then via
# ~/.local/share/thumbnailers/html-thumbnailer.thumbnailer), ffmpeg, GNU
# coreutils for `realpath`. Everything else (Chromium, caching, SingleFile
# polyglots, network isolation) is the thumbnailer's problem.

set -u

# Locate the thumbnailer: PATH first, else parse the freedesktop entry that
# nix/modules/desktop.nix keeps regenerated with the current store path.
thumb=$(command -v html-thumbnailer || true)
if [ -z "$thumb" ]; then
  desk=${XDG_DATA_HOME:-$HOME/.local/share}/thumbnailers/html-thumbnailer.thumbnailer
  [ -f "$desk" ] || { echo "no html-thumbnailer found" >&2; exit 1; }
  thumb=$(sed -n 's/^Exec=\([^ ]*\).*/\1/p' "$desk")
fi
[ -x "$thumb" ] || { echo "thumbnailer not executable: $thumb" >&2; exit 1; }

render_one() {
  f=$1
  meta="$(dirname "$f")/.ts"
  out="$meta/$(basename "$f").jpg"
  [ "$out" -nt "$f" ] 2>/dev/null && { echo "skip  $(basename "$f")"; return; }
  mkdir -p "$meta"
  tmp=$(mktemp --suffix=.png)
  # Thumbnailer stashes a cache key on stat(input), so give it the real
  # path, not a file:// URI. Chromium accepts a bare absolute path.
  if "$thumb" 500 "$(realpath -m "$f")" "$tmp" && [ -s "$tmp" ]; then
    if ffmpeg -nostdin -loglevel error -y -i "$tmp" \
        -vf "scale=500:500:force_original_aspect_ratio=decrease" \
        -q:v 3 "$out"; then
      echo "ok    $(basename "$f")"
    else
      rm -f "$out"
      echo "fail  $(basename "$f") (jpeg convert)" >&2
    fi
  else
    echo "fail  $(basename "$f") (render)" >&2
  fi
  rm -f "$tmp"
}

jobs=()
for dir in "$@"; do
  for f in "$dir"/*.html "$dir"/*.htm; do
    [ -e "$f" ] || continue
    jobs+=("$f")
  done
done

[ "${#jobs[@]}" -eq 0 ] && { echo "no html files in: $*"; exit 0; }

export -f render_one
export thumb
printf '%s\0' "${jobs[@]}" | xargs -0 -n1 -P2 bash -c 'render_one "$1"' _
echo "done: ${#jobs[@]} file(s)"
