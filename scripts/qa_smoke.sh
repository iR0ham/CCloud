#!/bin/bash
# Smoke test for the packaged app (Phase B QA). Read-only outside the workspace:
# it inspects build/CCloud.app, launches it, and writes evidence into qa/.
#
#   scripts/qa_smoke.sh            # full smoke test
#   scripts/qa_smoke.sh --fast     # skip the 15s liveness window (3s instead)
#
# Checks:
#   1. bundle structure + Info.plist keys (icon, ATS arbitrary loads, arm64, version)
#   2. Resources: AppIcon.icns (10 reps), Vazirmatn fonts register via CoreText,
#      logo assets, bundled ffmpeg (self-contained, empty-env runtime, mkv remux)
#   3. ad-hoc signature validity (and records the Gatekeeper/notarization limitation)
#   4. app launches and stays alive 15s, no crash report, no ATS/sandbox/fatal errors
#   5. API reachability + live data evidence in qa/*.png (if snapshots were taken)
#
# Exit code: 0 if no hard failure (known limitations are WARN).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/CCloud.app"
BIN="$APP/Contents/MacOS/CCloud"
RES="$APP/Contents/Resources"
QA="$ROOT/qa"
LOGS="$QA/logs"
BUILD="$ROOT/build"
OUT="$QA/smoke.txt"
PLIST="$APP/Contents/Info.plist"
FAST=0
[ "${1:-}" = "--fast" ] && FAST=1
export TMPDIR="$BUILD/tmp"
mkdir -p "$QA" "$LOGS" "$TMPDIR"

PASS=0
FAIL=0
WARN=0
: > "$OUT"

say()  { echo "$*" | tee -a "$OUT"; }
ok()   { PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m  %s\n' "$*"; printf '  PASS  %s\n' "$*" >> "$OUT"; }
bad()  { FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m  %s\n' "$*"; printf '  FAIL  %s\n' "$*" >> "$OUT"; }
warn() { WARN=$((WARN+1)); printf '  \033[33mWARN\033[0m  %s\n' "$*"; printf '  WARN  %s\n' "$*" >> "$OUT"; }
section() { say ""; say "== $* =="; }

expand() { printf '%s' "$1" | sed "s|\$ROOT|$ROOT|g; s|\$APP|$APP|g; s|\$RES|$RES|g"; }

check_file() {  # path, description
  if [ -f "$1" ]; then ok "$2: $(basename "$1")"; else bad "$2 missing: $1"; fi
}
check_cmd() {   # description, then command
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$desc"; else bad "$desc"; fi
}

say "CCloud macOS smoke test — $(date '+%Y-%m-%d %H:%M:%S %z')"
say "app: $APP"
if [ -x "$BIN" ]; then
  say "binary mtime:  $(stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' "$BIN")"
  say "binary sha256: $(shasum -a 256 "$BIN" | cut -d' ' -f1)"
  say "plist  sha256: $(shasum -a 256 "$PLIST" 2>/dev/null | cut -d' ' -f1)"
fi
set +m  # no job-control "Terminated: 15" noise when we stop the app after the liveness test

# ---------------------------------------------------------------- 0. bundle
section "bundle structure"
[ -x "$BIN" ] && ok "executable exists and is executable" || bad "executable missing: $BIN"
check_file "$PLIST" "Info.plist"
check_file "$RES/AppIcon.icns" "AppIcon.icns"
check_file "$RES/logo.png" "brand logo"
case "$(file "$BIN" 2>/dev/null)" in
  *arm64*) ok "binary architecture: arm64" ;;
  *) warn "binary is not arm64: $(file "$BIN" 2>/dev/null)" ;;
esac
if cmp -s "$ROOT/Info.plist" "$PLIST" 2>/dev/null; then ok "bundled Info.plist matches project Info.plist"
else warn "bundled Info.plist differs from project Info.plist"; fi

# ---------------------------------------------------------------- 1. plist keys
section "Info.plist keys"
plist_get() { plutil -extract "$1" raw -o - "$PLIST" 2>/dev/null; }
expect() { # key expected
  local got; got="$(plist_get "$1")"
  if [ "$got" = "$2" ]; then ok "$1 = $got"; else bad "$1 = '$got' (expected '$2')"; fi
}
expect CFBundleExecutable "CCloud"
expect CFBundleIdentifier "ir.ccloud.macapp"
expect CFBundleIconFile "AppIcon"
expect CFBundlePackageType "APPL"
expect CFBundleShortVersionString "2.0.0"
expect LSMinimumSystemVersion "15.0"
expect NSHighResolutionCapable "true"
expect NSAppTransportSecurity.NSAllowsArbitraryLoads "true"
expect NSAppTransportSecurity.NSAllowsLocalNetworking "true"
expect LSApplicationCategoryType "public.app-category.entertainment"

# ---------------------------------------------------------------- 2. icon
section "AppIcon.icns"
if [ -f "$RES/AppIcon.icns" ]; then
  ICNS_CHECK="$BUILD/tmp/qa-icns-check.iconset"
  rm -rf "$ICNS_CHECK"
  if iconutil -c iconset "$RES/AppIcon.icns" -o "$ICNS_CHECK" 2>/dev/null; then
    missing=""
    for rep in icon_16x16.png icon_16x16@2x.png icon_32x32.png icon_32x32@2x.png \
               icon_128x128.png icon_128x128@2x.png icon_256x256.png icon_256x256@2x.png \
               icon_512x512.png icon_512x512@2x.png; do
      [ -f "$ICNS_CHECK/$rep" ] || missing="$missing $rep"
    done
    if [ -z "$missing" ]; then
      ok "10 representations present (16…1024 px incl. @2x)"
      dims="$(sips -g pixelWidth -g pixelHeight "$ICNS_CHECK/icon_512x512@2x.png" 2>/dev/null | awk '/pixel/{print $2}' | paste -sd x -)"
      [ "$dims" = "1024x1024" ] && ok "largest representation is 1024x1024" || warn "largest rep is $dims"
    else
      bad "missing icon representations:$missing"
    fi
  else
    bad "iconutil cannot decode AppIcon.icns"
  fi
else
  bad "AppIcon.icns missing from Contents/Resources"
fi

# ---------------------------------------------------------------- 3. fonts
section "fonts (Vazirmatn)"
if [ -d "$RES/Fonts" ]; then
  N_FONTS=$(ls -1 "$RES/Fonts"/*.ttf 2>/dev/null | wc -l | tr -d ' ')
  [ "$N_FONTS" -ge 9 ] && ok "$N_FONTS Vazirmatn .ttf files bundled" || bad "expected 9 fonts, found $N_FONTS"
  FONT_BIN="$BUILD/tmp/qa-font-check"
  if [ ! -x "$FONT_BIN" ] || [ "$ROOT/scripts/qa_font_check.swift" -nt "$FONT_BIN" ]; then
    swiftc -O -target arm64-apple-macos15.0 -sdk "$(xcrun --show-sdk-path)" \
      -module-cache-path "$BUILD/modulecache" \
      "$ROOT/scripts/qa_font_check.swift" -o "$FONT_BIN" >/dev/null 2>&1
  fi
  if [ -x "$FONT_BIN" ]; then
    FONT_OUT="$("$FONT_BIN" "$RES/Fonts" 2>&1)"
    echo "$FONT_OUT" >> "$OUT"
    if echo "$FONT_OUT" | grep -q "RESULT: OK"; then ok "all fonts register via CoreText (Vazirmatn family present)"
    else bad "font registration failed — see qa/smoke.txt"; fi
  else
    bad "could not compile qa_font_check.swift"
  fi
else
  bad "Contents/Resources/Fonts missing"
fi

# ---------------------------------------------------------------- 4. ffmpeg
section "bundled ffmpeg"
FF="$RES/ffmpeg-bin/ffmpeg"
if [ -x "$FF" ]; then
  ok "ffmpeg present at Contents/Resources/ffmpeg-bin/ffmpeg"
  NDEPS=$(ls -1 "$RES/ffmpeg-bin"/*.dylib 2>/dev/null | wc -l | tr -d ' ')
  [ "$NDEPS" -ge 10 ] && ok "$NDEPS bundled dylibs" || warn "unexpected dylib count: $NDEPS"
  if env -i "$FF" -hide_banner -version >"$LOGS/ffmpeg-version.log" 2>&1; then
    ok "runs with an empty environment ($(head -1 "$LOGS/ffmpeg-version.log"))"
  else
    bad "ffmpeg fails to run with empty environment"
  fi
  REFS=$(for f in "$RES/ffmpeg-bin"/*; do
           if [ "$(basename "$f")" != "MANIFEST.txt" ]; then
             otool -L "$f" 2>/dev/null | tail -n +2 | awk '{print $1}'
           fi
         done | grep -E '^(/opt/homebrew|/usr/local)' | sort -u)
  [ -z "$REFS" ] && ok "no absolute Homebrew references (fully self-contained)" || bad "absolute refs remain: $REFS"
  # real playback path: mkv -> fMP4 HLS remux (same command as the engine)
  RM="$BUILD/tmp/qa-remux"
  rm -rf "$RM"; mkdir -p "$RM/out"
  if env -i "$FF" -hide_banner -loglevel error -y -f lavfi -i testsrc=duration=6:size=320x240:rate=24 \
       -f lavfi -i sine=frequency=440:duration=6 -c:v libx264 -preset ultrafast -c:a aac -shortest "$RM/test.mkv" 2>"$LOGS/ffmpeg-mkvmk.log" \
     && env -i "$FF" -hide_banner -nostdin -i "$RM/test.mkv" -map 0:v:0 -map 0:a:0? -c copy \
       -f hls -hls_time 2 -hls_playlist_type event -hls_segment_type fmp4 \
       -hls_fmp4_init_filename init.mp4 -hls_segment_filename "$RM/out/seg%05d.m4s" \
       "$RM/out/playlist.m3u8" >"$LOGS/ffmpeg-remux.log" 2>&1; then
    if [ -s "$RM/out/playlist.m3u8" ] && [ -s "$RM/out/init.mp4" ] && ls "$RM/out"/seg*.m4s >/dev/null 2>&1; then
      ok "mkv → fMP4 HLS remux works (playlist + init.mp4 + segments)"
    else
      bad "remux produced incomplete output"
    fi
  else
    bad "mkv → fMP4 HLS remux failed (see qa/logs/ffmpeg-remux.log)"
  fi
else
  warn "no bundled ffmpeg — the app will look for a system ffmpeg instead"
fi

# ---------------------------------------------------------------- 5. signature
section "code signature"
if codesign --verify --deep --strict "$APP" >"$LOGS/codesign.log" 2>&1; then
  ok "ad-hoc signature valid (codesign --verify --deep --strict)"
else
  bad "code signature invalid — see qa/logs/codesign.log"
fi
SIG=$(codesign -dv "$APP" 2>&1 | sed -n 's/^Signature=//p')
say "  signature: ${SIG:-unknown}"
if spctl --assess --type execute -vv "$APP" >"$LOGS/spctl.log" 2>&1; then
  ok "Gatekeeper assessment passes"
else
  warn "Gatekeeper rejects the app (expected: ad-hoc, not notarized) — README documents right-click → Open / xattr -dr"
fi
if xattr -p com.apple.quarantine "$APP" >/dev/null 2>&1; then
  warn "app has com.apple.quarantine attribute (will prompt on first launch)"
else
  ok "no quarantine attribute on the built app"
fi

# ---------------------------------------------------------------- 6. liveness
section "launch liveness"
pkill -f "CCloud.app/Contents/MacOS/CCloud" 2>/dev/null && sleep 0.5
LIVE_LOG="$LOGS/launch-15s.log"
START_STAMP="$LOGS/.launch-start"
touch "$START_STAMP"
ALIVE_SECONDS=$([ "$FAST" = "1" ] && echo 3 || echo 15)
"$BIN" --tab movies >"$LIVE_LOG" 2>&1 &
APP_PID=$!
echo "  launched pid $APP_PID, waiting ${ALIVE_SECONDS}s…"
sleep "$ALIVE_SECONDS"
if kill -0 "$APP_PID" 2>/dev/null; then
  ok "app still alive after ${ALIVE_SECONDS}s"
  ps -p "$APP_PID" -o pid=,rss=,etime=,%cpu= >> "$OUT" 2>/dev/null || true
  kill -TERM "$APP_PID" 2>/dev/null
  sleep 1
  kill -9 "$APP_PID" 2>/dev/null || true
  wait "$APP_PID" 2>/dev/null || true
else
  bad "app exited before ${ALIVE_SECONDS}s"
fi

# crash reports created during this run
CRASH_DIR="$HOME/Library/Logs/DiagnosticReports"
if [ -d "$CRASH_DIR" ]; then
  CRASHES=$(find "$CRASH_DIR" -maxdepth 1 -name 'CCloud*' -newer "$START_STAMP" 2>/dev/null)
  if [ -z "$CRASHES" ]; then ok "no crash report for CCloud in $CRASH_DIR"
  else bad "crash report(s) found:"; echo "$CRASHES" | sed 's/^/        /' >> "$OUT"; fi
else
  warn "no DiagnosticReports directory to inspect"
fi

if [ -f "$LIVE_LOG" ]; then
  grep -qE "fatal error|Fatal exception|Segmentation fault|EXC_BAD" "$LIVE_LOG" && bad "fatal error in app log" || ok "no fatal error in stderr log"
  grep -qiE "App Transport Security|NSURLErrorDomain: -1022|NSURLErrorDomain: -1009" "$LIVE_LOG" \
    && bad "ATS/transport error in app log" || ok "no ATS/transport errors in stderr log"
  grep -qiE "sandbox.*denied|Operation not permitted|errno: 1\b" "$LIVE_LOG" \
    && warn "possible sandbox-denied operation in app log (see qa/logs/launch-15s.log)" || true
  if grep -q "\[ccloud\]" "$LIVE_LOG"; then
    ok "app logged its startup diagnostics ($(grep -c '\[ccloud\]' "$LIVE_LOG") lines)"
  else
    warn "app produced no [ccloud] log lines (is stderr wired to the terminal?)"
  fi
fi

# ---------------------------------------------------------------- 7. API + live data
section "backend / live data"
GENRE_PATH="/api/genre/all/4F5A9C3D9A86FA54EACEDDD635185/"
API_OK=0
for host in server-hi-speed-iran.info hostinnegar.com windowsdiba.info; do
  for scheme in http https; do
    code=$(curl -sS -o "$BUILD/tmp/qa-api.json" -w '%{http_code}' --max-time 8 "$scheme://$host$GENRE_PATH" 2>/dev/null || echo "000")
    size=$(wc -c < "$BUILD/tmp/qa-api.json" 2>/dev/null | tr -d ' ')
    if [ "$code" = "200" ] && [ "${size:-0}" -gt 10 ]; then
      ok "API $scheme://$host → HTTP 200 (${size}B)"
      API_OK=1
      break 2
    else
      say "  … $scheme://$host → $code"
    fi
  done
done
if [ "$API_OK" = "0" ]; then
  warn "no API host reachable from this machine (network/geo limitation, app shows Persian error state)"
fi
if [ -f "$QA/movies.png" ]; then
  STATS_BIN="$BUILD/tmp/qa-image-stats"
  if [ -x "$STATS_BIN" ]; then
    S=$("$STATS_BIN" "$QA/movies.png")
    COLORS=$(echo "$S" | sed -n 's/.*uniqueColors=\([0-9]*\).*/\1/p')
    if [ "${COLORS:-0}" -gt 3000 ]; then ok "live content rendered in qa/movies.png ($COLORS distinct colours → posters/artwork loaded)"
    else bad "qa/movies.png looks empty ($COLORS colours) — live API data may not be rendering"; fi
  fi
else
  warn "no qa/movies.png yet — run scripts/qa_snapshots.sh first for visual evidence"
fi

# ---------------------------------------------------------------- summary
section "summary"
say "  PASS: $PASS   FAIL: $FAIL   WARN: $WARN"
say "  evidence: qa/smoke.txt, qa/logs/, qa/*.png"
if [ "$FAIL" -gt 0 ]; then
  say "RESULT: FAIL"
  exit 1
fi
say "RESULT: PASS ($WARN known limitation warning(s))"
exit 0
