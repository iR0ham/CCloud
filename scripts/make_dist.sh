#!/bin/bash
# Packages build/CCloud.app into dist/CCloud-macOS-<version>-<build>.zip + SHA-256,
# then verifies the archive by extracting it to a clean directory and checking the
# extracted app.
#
#   scripts/make_dist.sh
#
# Output:
#   dist/CCloud-macOS-<version>-<build>.zip
#   dist/SHA256SUMS.txt
#   dist/CCloud-macOS-<version>-<build>.sha256   (single-line checksum)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/CCloud.app"
DIST="$ROOT/dist"
VERIFY="$ROOT/build/tmp/dist-verify"
BUILD="$ROOT/build"
export TMPDIR="$BUILD/tmp"
mkdir -p "$DIST" "$BUILD/tmp"

assert_legal_files() {
  local resources="$1"
  local canonical
  for canonical in NOTICE THIRD_PARTY_NOTICES.md SOURCES.md; do
    cmp "$ROOT/$canonical" "$resources/$canonical"
  done
  cmp "$ROOT/Legal/DISTRIBUTION_STATUS.md" "$resources/Legal/DISTRIBUTION_STATUS.md"
  for canonical in "$ROOT"/Legal/licenses/*.txt; do
    cmp "$canonical" "$resources/Legal/licenses/$(basename "$canonical")"
  done
  test "$(find "$resources/Legal/licenses" -maxdepth 1 -type f -name '*.txt' | wc -l | tr -d ' ')" = "10"
}

if [ ! -x "$APP/Contents/MacOS/CCloud" ]; then
  echo "error: $APP is missing or incomplete — build first (./build.sh)" >&2
  exit 1
fi

VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$APP/Contents/Info.plist" 2>/dev/null || true)"
BUILD_NUM="$(plutil -extract CFBundleVersion raw -o - "$APP/Contents/Info.plist" 2>/dev/null || true)"
if [ -z "$VERSION" ] || [ -z "$BUILD_NUM" ]; then
  echo "error: the built app has no CFBundleShortVersionString/CFBundleVersion" >&2
  exit 1
fi
ZIP="$DIST/CCloud-macOS-$VERSION-$BUILD_NUM.zip"
assert_legal_files "$APP/Contents/Resources"
echo "==> Packaging CCloud.app (version $VERSION build $BUILD_NUM)"

# Fresh archive; --keepParent keeps the CCloud.app wrapper so drag-to-Applications works.
rm -f "$ZIP"
ditto -c -k --keepParent --sequesterRsrc "$APP" "$ZIP"
ls -lh "$ZIP" | awk '{print "    "$5"  "$9}'

echo "==> Checksums"
(cd "$DIST" && shasum -a 256 "$(basename "$ZIP")" > SHA256SUMS.txt)
shasum -a 256 "$ZIP" | cut -d' ' -f1 > "$DIST/CCloud-macOS-$VERSION-$BUILD_NUM.sha256"
cat "$DIST/SHA256SUMS.txt" | sed 's/^/    /'

echo "==> Verifying the archive round-trips"
rm -rf "$VERIFY"
mkdir -p "$VERIFY"
ditto -x -k "$ZIP" "$VERIFY"
EXTRACTED="$VERIFY/CCloud.app"
[ -x "$EXTRACTED/Contents/MacOS/CCloud" ] || { echo "error: extracted app executable missing" >&2; exit 1; }
[ -f "$EXTRACTED/Contents/Resources/AppIcon.icns" ] || { echo "error: extracted AppIcon.icns missing" >&2; exit 1; }
[ -x "$EXTRACTED/Contents/Resources/ffmpeg-bin/ffmpeg" ] || { echo "error: extracted bundled ffmpeg missing" >&2; exit 1; }
assert_legal_files "$EXTRACTED/Contents/Resources"
if codesign --verify --deep --strict "$EXTRACTED" >/dev/null 2>&1; then
  echo "    extracted signature: valid"
else
  echo "    warning: extracted signature invalid (re-run ./build.sh before shipping)" >&2
fi
env -i "$EXTRACTED/Contents/Resources/ffmpeg-bin/ffmpeg" -hide_banner -version >/dev/null \
  && echo "    extracted bundled ffmpeg: runs with empty environment" \
  || { echo "error: extracted bundled ffmpeg does not run" >&2; exit 1; }
du -sh "$ZIP" | awk '{print "    final archive size: "$1}'
echo "==> Done: $ZIP"
