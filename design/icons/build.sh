#!/bin/bash
# Render the MacSlowdown icon SVGs to PNG at every size the .appiconset needs,
# and produce a contact sheet for judging the small-size reduction.
#
# Usage: design/icons/build.sh
#
# Chrome is used as the SVG rasteriser (ImageMagick's internal SVG renderer is
# not faithful). Output goes to MacSlowdown/Resources/AppIcon.appiconset/.
set -euo pipefail

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
OUT="$ROOT/MacSlowdown/Resources/Assets.xcassets/AppIcon.appiconset"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$OUT"

# render <svg> <px> <dest>
render() {
  local svg="$1" px="$2" dest="$3"
  cat > "$TMP/w.html" <<HTML
<!doctype html><meta charset=utf-8>
<style>html,body{margin:0;padding:0;background:#000}
img{display:block;width:${px}px;height:${px}px}</style>
<img src="file://$svg">
HTML
  nice "$CHROME" --headless --disable-gpu --hide-scrollbars \
    --force-device-scale-factor=1 --window-size="$px,$px" \
    --default-background-color=00000000 \
    --screenshot="$TMP/r.png" "file://$TMP/w.html" >/dev/null 2>&1
  # Chrome's shot can be off by a pixel on some sizes; normalise and flatten so
  # every edge pixel is alpha 255. macOS 26 reads an edge alpha <= 252 as
  # "legacy icon" and drops the artwork inside a grey squircle instead of
  # clipping it (see the task notes) -- a fully opaque tile gets the correct
  # rounded-rect clip.
  nice magick "$TMP/r.png" -background '#333B4A' -alpha remove -alpha off \
    -resize "${px}x${px}!" -define png:color-type=2 "$dest"
}

# Crossover at 32 px. Almost every display is Retina, so 16 pt is drawn from the
# 32 px asset and 32 pt from the 64 px one: simplified art below 64 px means the
# 16 pt icon is simplified and everything from 32 pt up is the detailed trace.
for px in 1024 512 256 128 64; do render "$HERE/icon-large.svg" "$px" "$OUT/icon_${px}.png"; done
for px in 32 16;              do render "$HERE/icon-small.svg" "$px" "$OUT/icon_${px}.png"; done

# Contact sheet: every size drawn at its true pixel size, left to right.
nice magick "$OUT/icon_128.png" "$OUT/icon_64.png" "$OUT/icon_32.png" "$OUT/icon_16.png" \
  -background '#dcd9d2' -gravity south +append -bordercolor '#dcd9d2' -border 12 \
  "$HERE/contact-sheet.png"
# And the small sizes magnified 8x with no smoothing, to inspect what actually
# survives rasterisation at 16 and 32 px.
nice magick "$OUT/icon_16.png" -filter point -resize 800% "$HERE/zoom-16.png"
nice magick "$OUT/icon_32.png" -filter point -resize 400% "$HERE/zoom-32.png"

echo "wrote $(ls "$OUT"/*.png | wc -l | tr -d ' ') PNGs to $OUT"
