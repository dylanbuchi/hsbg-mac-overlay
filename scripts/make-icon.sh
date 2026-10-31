#!/bin/sh
# Rebuilds packaging/AppIcon.icns from packaging/AppIcon-master.png (1024x1024, full-bleed:
# macOS applies the rounded mask itself). The master is the original artwork cropped just
# inside its drawn rim, so the rim is not doubled.
set -eu
DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../packaging" && pwd)
SET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$SET"
for s in 16 32 128 256 512; do
    sips -z $s $s "$DIR/AppIcon-master.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) "$DIR/AppIcon-master.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o "$DIR/AppIcon.icns"
echo "Wrote $DIR/AppIcon.icns"
