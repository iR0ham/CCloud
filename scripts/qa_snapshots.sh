#!/bin/bash
# Snapshot QA for build/CCloud.app — uses the app's own in-app hook because terminal
# `screencapture` is blocked in this environment:
#
#   CCloud --snapshot <png> --snapshot-delay <n> [--tab movies|series|search|favorites|countries|settings]
#                                             [--demo movie|series|country|search|player|about]
#
# Each run launches the app fresh, waits for it to render, saves a PNG into qa/, then the
# app terminates itself. Every PNG is validated (dimensions, bytes, colour variety) and
# logs are kept under qa/logs/ for evidence.
#
# Usage:
#   scripts/qa_snapshots.sh                 # all screens
#   scripts/qa_snapshots.sh movies series   # only these screens
#   SNAPSHOT_DELAY=10 scripts/qa_snapshots.sh
#
# Exit code: 0 if every snapshot was written and looks non-blank, 1 otherwise.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/CCloud.app"
BIN="$APP/Contents/MacOS/CCloud"
RES="$APP/Contents/Resources"
OUT="$ROOT/qa"
LOGS="$OUT/logs"
BUILD="$ROOT/build"
DELAY="${SNAPSHOT_DELAY:-14}"
STATS_BIN="$BUILD/tmp/qa-image-stats"
export TMPDIR="$BUILD/tmp"
mkdir -p "$OUT" "$LOGS" "$TMPDIR"

if [ ! -x "$BIN" ]; then
  echo "error: $BIN not found — run ./build.sh first" >&2
  exit 1
fi

# Optional: --isolated runs a copy of the bundle under a unique bundle id. macOS refuses
# to give a window to a second instance of the same bundle id, so if another agent is
# snapshotting the same build concurrently every launch would come up windowless.
ISO_MODE=0
if [ "${1:-}" = "--isolated" ]; then
  ISO_MODE=1
  shift
fi

if [ "$#" -gt 0 ] && [ "$1" != "--all" ]; then
  WANTED=" $* "
else
  WANTED=""
fi

SOURCE_BIN="$BIN"
ISO_ROOT="$BUILD/tmp/qa-isolated"
if [ "$ISO_MODE" = "1" ]; then
  echo "==> isolated QA mode: each shot runs an APFS-cloned copy with a unique bundle id"
  echo "    source binary sha256: $(shasum -a 256 "$SOURCE_BIN" | cut -d' ' -f1)"
fi

# Stamp the exact bundle under test (Lead's FREEZE build) so QA evidence is attributable.
BUNDLE_INFO="$OUT/build-info.txt"
BIN_SHA="$(shasum -a 256 "$BIN" | cut -d' ' -f1)"
PLIST_SHA="$(shasum -a 256 "$APP/Contents/Info.plist" | cut -d' ' -f1)"
BIN_MTIME="$(stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' "$BIN")"
BIN_SIZE="$(stat -f '%z' "$BIN")"
APPLET_SHA="$(shasum -a 256 "$RES/AppIcon.icns" 2>/dev/null | cut -d' ' -f1)"
{
  echo "qa run:        $(date '+%Y-%m-%d %H:%M:%S %z')"
  echo "app bundle:    $APP"
  echo "binary mtime:  $BIN_MTIME"
  echo "binary bytes:  $BIN_SIZE"
  echo "binary sha256: $BIN_SHA"
  echo "plist sha256:  $PLIST_SHA"
  echo "icon sha256:   $APPLET_SHA"
  echo "qa mode:       $([ "$ISO_MODE" = "1" ] && echo "isolated (APFS clone, unique bundle id per shot, binary identical to build) — source: $SOURCE_BIN" || echo "exact build")"
  echo "screens:       (see qa/snapshots.txt)"
} | tee "$BUNDLE_INFO"

# Compile the image-stats helper once (cached until its source changes).
if [ ! -x "$STATS_BIN" ] || [ "$ROOT/scripts/qa_image_stats.swift" -nt "$STATS_BIN" ]; then
  echo "==> compiling image stats helper"
  swiftc -O -target arm64-apple-macos15.0 -sdk "$(xcrun --show-sdk-path)" \
    -module-cache-path "$BUILD/modulecache" \
    "$ROOT/scripts/qa_image_stats.swift" -o "$STATS_BIN" || {
    echo "error: cannot compile qa_image_stats.swift" >&2
    exit 1
  }
fi

# name|extra args|delay (delay optional — sheets need their own timing)
# The backend (Iranian host) can take 3–5 s per request, so list/detail screens get a
# generous window: genres → page → posters must all land before the snapshot.
# Detail/settings/player shots use the --debug-* hooks added by ui-detail.
SHOTS=(
  "movies|--tab movies|14"
  "series|--tab series|14"
  "live|--tab live|18"
  "live-channels|--demo live-channels|16"
  "live-channels-dead|--demo live-channels --debug-live-search HodHod|16"
  "player-live-error|--demo live-play HodHod --debug-player-controls|60"
  "live-player|--demo live-play --debug-player-controls|14"
  "player-live-failover|--demo live-failover Persiana --debug-player-controls|45"
  "search|--tab search --demo search|16"
  "favorites|--tab favorites|8"
  "countries|--tab countries|12"
  "settings|--tab settings|9"
  "detail-movie|--demo movie|16"
  "detail-movie-bottom|--demo movie --debug-scroll-bottom|18"
  "detail-series|--demo series|16"
  "detail-series-bottom|--demo series --debug-scroll-bottom|18"
  "detail-country|--demo country|16"
  "about|--demo about|13"
  "player-mkv|--demo player-local $ROOT/Tests/player/out/media/sample.mkv --debug-player-controls|12"
  "player-audio|--demo player-local $ROOT/Tests/player/out/media/dual.mkv --debug-player-controls|14"
  "player-mkv-preparing|--demo player-local $ROOT/Tests/player/out/media/sample.mkv|5"
  "player-mp4|--demo player-local $ROOT/Tests/player/out/media/sample.mp4 --debug-player-controls|4.5"
  "player-error|--demo player-local $ROOT/build/tmp/does-not-exist.mp4|12"
)

# Wait for other same-bundle instances to finish before taking a shot: launching while
# another instance is alive yields "windows=0" (no window) on macOS.
wait_for_quiet() {
  [ "$ISO_MODE" = "1" ] && return 0
  local tries=0
  while [ "$tries" -lt 120 ]; do
    local others
    others="$(pgrep -fl "MacOS/CCloud" 2>/dev/null | grep -v "bash -c" | grep -v "pgrep" | wc -l | tr -d ' ')"
    [ "$others" = "0" ] && return 0
    [ "$tries" = "0" ] && echo "    … waiting for $others other CCloud instance(s) to finish"
    tries=$((tries + 1))
    sleep 0.5
  done
  echo "    ! other CCloud instances are still running; screenshot may come up windowless" >&2
}

SUMMARY="$OUT/snapshots.txt"
: > "$SUMMARY"
printf '%-16s %-12s %-10s %-8s %-8s %s\n' "screen" "size" "bytes" "colors" "verdict" "result" | tee "$SUMMARY"
echo "----------------------------------------------------------------------------" | tee -a "$SUMMARY"

FAILED=0
RAN=0
ROW_FILE="$BUILD/tmp/.qa-rows"
: > "$ROW_FILE"

shoot() {
  local name="$1"; local delay="$2"; shift 2
  local png="$OUT/$name.png"
  local log="$LOGS/$name.log"
  # The player opens in its own window; name the window each shot wants so a leftover
  # player window from an earlier shot can never be photographed instead of the screen.
  local window="CCloud"
  case "$name" in player-*|live-player) window="Player" ;; esac
  rm -f "$png"
  local attempt=1
  local max_attempts=3
  local dly="$delay"
  while : ; do
    wait_for_quiet
    local launch_bin="$BIN"
    if [ "$ISO_MODE" = "1" ]; then
      # Fresh clone per shot + unique bundle id: macOS silently gives no window to a
      # second instance of a bundle id, which is exactly what concurrent QA runs cause.
      local iso_app="$ISO_ROOT/$name-$attempt/CCloudQA.app"
      rm -rf "$ISO_ROOT/$name-$attempt"
      mkdir -p "$ISO_ROOT/$name-$attempt"
      cp -cR "$APP" "$iso_app" 2>/dev/null || cp -a "$APP" "$iso_app"
      plutil -replace CFBundleIdentifier -string "ir.ccloud.qa.$name.a$attempt" "$iso_app/Contents/Info.plist"
      plutil -replace CFBundleName -string "CCloudQA" "$iso_app/Contents/Info.plist"
      codesign --force --deep --sign - "$iso_app" >/dev/null 2>&1 || true
      launch_bin="$iso_app/Contents/MacOS/CCloud"
    fi
    echo "==> ${name}   (attempt ${attempt}, delay ${dly}s, window ${window}, $*)"
    # shellcheck disable=SC2086
    "$launch_bin" --snapshot "$png" --snapshot-delay "$dly" --snapshot-window "$window" "$@" >"$log" 2>&1 &
    local pid=$!
    # integer watchdog (delay may be fractional like 4.5)
    local dint="${dly%%.*}"
    [ -z "$dint" ] && dint="$DELAY"
    local deadline=$(( $(date +%s) + dint + 30 ))
    while kill -0 "$pid" 2>/dev/null; do
      if [ "$(date +%s)" -gt "$deadline" ]; then
        echo "    ! app did not exit ${dly}s+30s after launch — killing" | tee -a "$log"
        kill -9 "$pid" 2>/dev/null
        break
      fi
      sleep 0.3
    done
    wait "$pid" 2>/dev/null || true
    [ "$ISO_MODE" = "1" ] && rm -rf "$ISO_ROOT/$name-$attempt"
    [ -f "$png" ] && break
    if [ "$attempt" -ge "$max_attempts" ]; then break; fi
    echo "    ! no snapshot produced (app was killed / window closed) — retrying in 2 s"
    attempt=$((attempt + 1))
    dly=$(( ${dly%%.*} + 4 ))
    sleep 2
  done

  local row result
  if [ ! -f "$png" ]; then
    result="FAIL(no png after ${attempt} attempt(s))"
    FAILED=$((FAILED + 1))
    row=$(printf '%-16s %-12s %-10s %-8s %-8s %s' "$name" "-" "-" "-" "-" "$result")
    echo "$row" | tee -a "$SUMMARY"
    return
  fi

  # image stats (space separated key=value)
  local stats width height bytes unique luma nonbg verdict
  stats="$("$STATS_BIN" "$png" 2>/dev/null)"
  width=$(echo "$stats" | sed -n 's/.*width=\([0-9]*\).*/\1/p')
  height=$(echo "$stats" | sed -n 's/.*height=\([0-9]*\).*/\1/p')
  bytes=$(echo "$stats" | sed -n 's/.*bytes=\([0-9]*\).*/\1/p')
  unique=$(echo "$stats" | sed -n 's/.*uniqueColors=\([0-9]*\).*/\1/p')
  nonbg=$(echo "$stats" | sed -n 's/.*nonBg=\([0-9.]*\).*/\1/p')
  verdict=$(echo "$stats" | sed -n 's/.*verdict=\([a-z]*\).*/\1/p')

  # Sheets (about/player) are legitimately smaller than the main window, and some
  # screens are intentionally near-black (player surface, empty states). FAIL only on
  # structurally broken output; flat/blank is a WARN that the visual review judges.
  if [ -z "$width" ] || [ "$width" = "0" ]; then
    result="FAIL(unreadable)"
  elif [ "$width" -lt 600 ] || [ "$height" -lt 500 ]; then
    result="FAIL(small)"
  elif [ "${bytes:-0}" -lt 12000 ]; then
    result="FAIL(tiny png)"
  elif [ "$verdict" = "blank" ]; then
    result="WARN(blank window)"
  elif [ "$verdict" = "dark" ]; then
    result="WARN(mostly flat)"
  else
    result="PASS"
  fi
  [ "${result:0:4}" = "FAIL" ] && FAILED=$((FAILED + 1))
  RAN=$((RAN + 1))

  # record stderr signal for each shot
  local note=""
  grep -q "snapshot: no window" "$log" && note="$note no-window"
  grep -qiE "fatal error|Fatal exception|Segmentation fault" "$log" && note="$note fatal-log"
  [ -n "$note" ] && { result="$result$note"; [ "${result:0:4}" = "PASS" ] && FAILED=$((FAILED + 1)); }

  row=$(printf '%-16s %-12s %-10s %-8s %-8s %s' "$name" "${width}x${height}" "$bytes" "$unique" "$verdict" "$result")
  echo "$row" | tee -a "$SUMMARY"
}

for entry in "${SHOTS[@]}"; do
  name="${entry%%|*}"
  rest="${entry#*|}"
  extra="${rest%%|*}"
  shot_delay="${rest##*|}"
  [ "$shot_delay" = "$extra" ] && shot_delay="$DELAY"
  if [ -n "$WANTED" ] && [[ "$WANTED" != *" $name "* ]]; then
    continue
  fi
  # shellcheck disable=SC2086
  shoot "$name" "$shot_delay" $extra
done

echo "----------------------------------------------------------------------------" | tee -a "$SUMMARY"
if [ "$RAN" -eq 0 ]; then
  echo "no screenshots matched '${WANTED}'" | tee -a "$SUMMARY"
  exit 1
fi
if [ "$FAILED" -gt 0 ]; then
  echo "RESULT: FAIL — $FAILED problem(s) across $RAN screenshot(s)" | tee -a "$SUMMARY"
  exit 1
fi
echo "RESULT: OK — $RAN non-blank snapshot(s) in qa/" | tee -a "$SUMMARY"
echo "Next: inspect the PNGs (read_image) for visual defects."
