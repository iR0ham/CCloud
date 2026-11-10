#!/bin/bash
# Player engine verification: generates local test media (ffmpeg lavfi) and runs the headless
# NSApplication harness against the real PlaybackController.
#
#   ./Tests/player/run.sh            # full suite
#   FORCE_MEDIA=1 ./Tests/player/run.sh   # regenerate the sample media
#
# All artefacts stay inside the project: Tests/player/out/**.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/Tests/player/out"
MEDIA="$OUT/media"
TMP="$OUT/tmp"
MODULECACHE="$ROOT/build/modulecache"
HARNESS="$OUT/player-harness"
LOG="$OUT/harness.log"
MISSING_LOG="$OUT/harness-missing-ffmpeg.log"
FARSEEK_LOG="$OUT/harness-farseek.log"
STALL_LOG="$OUT/harness-stall.log"

mkdir -p "$OUT" "$MEDIA" "$TMP" "$MODULECACHE"
export TMPDIR="$TMP"

SDK="$(xcrun --show-sdk-path)"
FFMPEG="${FFMPEG:-$(command -v ffmpeg || true)}"
if [ -z "$FFMPEG" ] && [ -x /opt/homebrew/bin/ffmpeg ]; then FFMPEG=/opt/homebrew/bin/ffmpeg; fi
if [ -z "$FFMPEG" ]; then
  echo "FATAL: ffmpeg not found (needed to generate test media and for the remux pipeline)"
  exit 2
fi

# Stale temp sessions from a previous crashed run must not pollute the evidence.
rm -rf "$TMP/CCloudRemux-"* 2>/dev/null || true

echo "==> ffmpeg: $FFMPEG"
"$FFMPEG" -hide_banner -version 2>/dev/null | head -1

generate_media() {
  local out="$1"
  if [ -f "$out" ] && [ "${FORCE_MEDIA:-0}" != "1" ]; then
    echo "    keeping existing $(basename "$out")"
    return 0
  fi
  echo "    generating $(basename "$out") (H.264/AAC, 40s, 640x360, 2s GOP)"
  "$FFMPEG" -hide_banner -loglevel error -y \
    -f lavfi -i testsrc2=size=640x360:rate=24 \
    -f lavfi -i sine=frequency=440:sample_rate=48000 \
    -t 40 -c:v libx264 -preset ultrafast -g 48 -keyint_min 48 -sc_threshold 0 \
    -pix_fmt yuv420p -c:a aac -b:a 96k "$out"
}

generate_dual() {
  local out="$1"
  if [ -f "$out" ] && [ "${FORCE_MEDIA:-0}" != "1" ]; then
    echo "    keeping existing $(basename "$out")"
    return 0
  fi
  echo "    generating $(basename "$out") (H.264 + 2 audio tracks, Spanish marked default)"
  "$FFMPEG" -hide_banner -loglevel error -y \
    -f lavfi -i testsrc2=size=640x360:rate=24 \
    -f lavfi -i sine=frequency=440:sample_rate=48000 \
    -f lavfi -i sine=frequency=880:sample_rate=48000 \
    -map 0:v:0 -map 1:a:0 -map 2:a:0 \
    -t 40 -c:v libx264 -preset ultrafast -g 48 -keyint_min 48 -sc_threshold 0 \
    -pix_fmt yuv420p -c:a aac -b:a 96k \
    -metadata:s:a:0 language=eng -metadata:s:a:1 language=spa \
    -disposition:a:0 none -disposition:a:1 default "$out"
}

echo "==> Test media"
generate_media "$MEDIA/sample.mp4" || { echo "FATAL: mp4 generation failed"; exit 2; }
generate_media "$MEDIA/sample.mkv" || { echo "FATAL: mkv generation failed"; exit 2; }
generate_dual "$MEDIA/dual.mkv" || { echo "FATAL: dual mkv generation failed"; exit 2; }
generate_dual "$MEDIA/dual.mp4" || { echo "FATAL: dual mp4 generation failed"; exit 2; }
ls -lh "$MEDIA" | sed 's/^/    /'

# ATS: the harness is a bare executable, so embed an Info.plist allowing local/arbitrary HTTP
# (the real app bundle has the same keys in Info.plist).
cat > "$OUT/harness-info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>ir.ccloud.player.harness</string>
  <key>CFBundleName</key><string>CCloudPlayerHarness</string>
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsArbitraryLoads</key><true/>
    <key>NSAllowsLocalNetworking</key><true/>
  </dict>
</dict>
</plist>
PLIST

echo "==> Building harness"
SOURCES=("$ROOT/Sources/Core/Models.swift" "$ROOT/Sources/Core/PersianNumber.swift"
         "$ROOT/Sources/Core/LiveTVModels.swift")
while IFS= read -r -d '' f; do SOURCES+=("$f"); done < <(find "$ROOT/Sources/Player" -name '*.swift' -print0 | sort -z)
swiftc \
  -O -swift-version 5 -module-name CCloud \
  -module-cache-path "$MODULECACHE" \
  -target arm64-apple-macos15.0 -sdk "$SDK" \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$OUT/harness-info.plist" \
  "${SOURCES[@]}" "$ROOT/Tests/player/main.swift" \
  -o "$HARNESS" || { echo "FATAL: harness build failed"; exit 2; }
echo "    $HARNESS"

echo
echo "=================================================================="
echo "==> Running playback harness (local HTTP-served + file:// media)"
echo "=================================================================="
unset CCLOUD_FFMPEG_PATH
"$HARNESS" --media-dir "$MEDIA" --out-dir "$OUT" 2>&1 | tee "$LOG"
FULL_STATUS=${PIPESTATUS[0]}
# Also generate the media-server request count evidence for the report.
echo
echo "==> media-server requests served: $(grep -c '^\[media-server\]' "$LOG" || true)"

if [ "$FULL_STATUS" -eq 0 ]; then
  echo
  echo "=================================================================="
  echo "==> Running ffmpeg-missing error-path harness"
  echo "=================================================================="
  CCLOUD_FFMPEG_PATH="/nonexistent/ffmpeg" "$HARNESS" --missing-ffmpeg \
    --media-dir "$MEDIA" --out-dir "$OUT" 2>&1 | tee "$MISSING_LOG"
  MISSING_STATUS=${PIPESTATUS[0]}
else
  MISSING_STATUS=1
fi

if [ "$FULL_STATUS" -eq 0 ] && [ "$MISSING_STATUS" -eq 0 ]; then
  echo
  echo "=================================================================="
  echo "==> Running far-seek restart phase (throttled remux: -re)"
  echo "=================================================================="
  CCLOUD_REMUX_THROTTLE=1 "$HARNESS" --phase farseek \
    --media-dir "$MEDIA" --out-dir "$OUT" 2>&1 | tee "$FARSEEK_LOG"
  FARSEEK_STATUS=${PIPESTATUS[0]}
else
  FARSEEK_STATUS=1
fi

echo
echo "==> far-seek ffmpeg restarts observed: $(grep -c 'restart ffmpeg args:' "$FARSEEK_LOG" 2>/dev/null || true)"

if [ "$FULL_STATUS" -eq 0 ] && [ "$MISSING_STATUS" -eq 0 ] && [ "$FARSEEK_STATUS" -eq 0 ]; then
  echo
  echo "=================================================================="
  echo "==> Running stall phase (throttled remux + ffmpeg killed mid-play)"
  echo "=================================================================="
  CCLOUD_REMUX_THROTTLE=1 "$HARNESS" --phase stall \
    --media-dir "$MEDIA" --out-dir "$OUT" 2>&1 | tee "$STALL_LOG"
  STALL_STATUS=${PIPESTATUS[0]}
else
  STALL_STATUS=1
fi

echo
echo "==> Post-run evidence: no surviving ffmpeg remux processes"
if /usr/bin/pgrep -fl "ffmpeg .*CCloudRemux-" 2>/dev/null | grep -q .; then
  /usr/bin/pgrep -fl "ffmpeg .*CCloudRemux-" | sed 's/^/    /' 
  echo "    ^^ LEFTOVER PROCESSES (failure)"
else
  echo "    (none)"
fi
echo "==> Post-run evidence: no surviving remux temp directories"
if find "$TMP" -maxdepth 1 -name 'CCloudRemux-*' -print | grep -q .; then
  find "$TMP" -maxdepth 1 -name 'CCloudRemux-*' -print | sed 's/^/    /'
  echo "    ^^ LEFTOVER TEMP DIRS (failure)"
else
  echo "    (none)"
fi

echo
echo "==> Logs: $LOG"
echo "    Missing-ffmpeg log: $MISSING_LOG"
echo "    Far-seek log:       $FARSEEK_LOG"
echo "    Stall log:          $STALL_LOG"
if [ "$FULL_STATUS" -eq 0 ] && [ "$MISSING_STATUS" -eq 0 ] && [ "$FARSEEK_STATUS" -eq 0 ] && [ "$STALL_STATUS" -eq 0 ]; then
  echo "==> PLAYER ENGINE TESTS PASSED"
  exit 0
else
  echo "==> PLAYER ENGINE TESTS FAILED (full=$FULL_STATUS missing-ffmpeg=$MISSING_STATUS farseek=$FARSEEK_STATUS stall=$STALL_STATUS)"
  exit 1
fi
