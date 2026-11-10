#!/bin/bash
# Build script for CCloud.app (native macOS port). No Xcode project, no external packages.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="${CCLOUD_OUT:-$ROOT/build}"
APP="$BUILD/CCloud.app"
MACOS_DIR="$APP/Contents/MacOS"
RES_DIR="$APP/Contents/Resources"
CACHE="$BUILD/modulecache"
TMPD="$BUILD/tmp"
BIN="$MACOS_DIR/CCloud"
SDK="$(xcrun --show-sdk-path)"

mkdir -p "$MACOS_DIR" "$RES_DIR" "$CACHE" "$TMPD"
export TMPDIR="$TMPD"
mkdir -p "$TMPDIR"

echo "==> Collecting sources"
SOURCES=()
while IFS= read -r -d '' f; do SOURCES+=("$f"); done < <(find "$ROOT/Sources" -name '*.swift' -print0 | sort -z)
echo "    ${#SOURCES[@]} Swift files"

echo "==> Compiling"
swiftc \
  -O \
  -swift-version 5 \
  -parse-as-library \
  -module-name CCloud \
  -module-cache-path "$CACHE" \
  -target arm64-apple-macos15.0 \
  -sdk "$SDK" \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  "${SOURCES[@]}" \
  -o "$BIN"

echo "==> Assembling bundle"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
# Resources (fonts, icon, logo, optional bundled ffmpeg)
if [ -d "$ROOT/Resources" ]; then
  rsync -a --delete "$ROOT/Resources/" "$RES_DIR/"
fi
# (icon & assets are copied by the rsync above; no self-copy here)
# Version stamp
printf 'CFBundleVersion=%s\n' "$(date +%Y%m%d%H%M)" > /dev/null

echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - --timestamp=none "$APP" >/dev/null 2>&1 || \
  codesign --force --sign - "$APP" >/dev/null

echo "==> Done: $APP"
if [ "${1:-}" = "--run" ]; then
  pkill -f "CCloud.app/Contents/MacOS/CCloud" 2>/dev/null || true
  sleep 0.3
  open "$APP"
  echo "==> Launched"
fi
