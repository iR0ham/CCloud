#!/bin/bash
# Builds Resources/AppIcon.icns from the original brand mark (Resources/logo.png).
#
#   scripts/make_icon.sh            # render iconset + compile AppIcon.icns
#   scripts/make_icon.sh --preview  # same, and copy a 1024 preview into build/tmp
#
# Renderer: scripts/make_icon.swift (CoreGraphics, drawn at each size, not upscaled).
# Intermediate iconset lives in build/tmp so the repo only keeps the final .icns.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
TMPD="$BUILD/tmp"
ICONSET="$TMPD/AppIcon.iconset"
MASTER="$TMPD/icon-master-1024.png"
MD="$ROOT/Resources/AppIconMaster.png"
OUT="$ROOT/Resources/AppIcon.icns"
PREVIEW=0
[ "${1:-}" = "--preview" ] && PREVIEW=1

mkdir -p "$BUILD/tmp"
export TMPDIR="$TMPD"

if [ ! -f "$ROOT/Resources/logo.png" ]; then
  echo "error: Resources/logo.png missing (brand mark source)" >&2
  exit 1
fi

rm -rf "$ICONSET"
echo "==> Rendering iconset from Resources/logo.png"
# The Swift renderer prints progress to stderr; stdout is one summary line.
swift "$ROOT/scripts/make_icon.swift" "$ROOT/Resources/logo.png" "$ICONSET" "$MASTER"

echo "==> Compiling AppIcon.icns"
iconutil -c icns "$ICONSET" -o "$OUT"

# Keep the 1024 master in Resources too, so future edits (and the README) have a
# high-res source without re-rendering.
cp "$MASTER" "$MD"

echo "==> Verifying"
# Round-trip through iconutil to prove the .icns carries all representations.
CHECK="$TMPD/AppIcon-check.iconset"
rm -rf "$CHECK"
iconutil -c iconset "$OUT" -o "$CHECK"
missing=0
for f in icon_16x16.png icon_16x16@2x.png icon_32x32.png icon_32x32@2x.png \
         icon_128x128.png icon_128x128@2x.png icon_256x256.png icon_256x256@2x.png \
         icon_512x512.png icon_512x512@2x.png; do
  if [ ! -f "$CHECK/$f" ]; then echo "  MISSING $f" >&2; missing=1; fi
done
[ "$missing" -eq 0 ] || { echo "error: .icns is incomplete" >&2; exit 1; }
sips -g pixelWidth -g pixelHeight "$MD" | sed -n '2,3p'
echo "    icns: $(du -h "$OUT" | cut -f1)  $(shasum -a 256 "$OUT" | cut -d' ' -f1 | cut -c1-16)…"
[ "$PREVIEW" = "1" ] && cp "$MASTER" "$TMPD/icon-preview-1024.png"
echo "==> Done: $OUT"
