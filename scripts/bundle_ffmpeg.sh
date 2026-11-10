#!/bin/bash
# Bundles a self-contained ffmpeg into Resources/ffmpeg-bin/.
#
# The app's mkv playback remuxes with ffmpeg through `Contents/Resources/ffmpeg-bin/ffmpeg`
# (build.sh rsyncs Resources/ -> Contents/Resources/). Homebrew's ffmpeg links ~25
# absolute /opt/homebrew paths, so we copy the executable + the full non-system dylib
# closure and rewrite every link to `@loader_path/<basename>`. The resulting folder can
# be relocating anywhere (verified below from a copied path with an empty environment).
#
#   scripts/bundle_ffmpeg.sh                 # build Resources/ffmpeg-bin from Homebrew ffmpeg
#   FFMPEG_SRC=/path/to/ffmpeg scripts/bundle_ffmpeg.sh
#   scripts/bundle_ffmpeg.sh --clean         # remove the bundled copy (system ffmpeg fallback)
#
# Notes:
# - Every modified Mach-O is re-signed ad-hoc: Apple Silicon refuses to run an arm64
#   binary whose code signature was invalidated by install_name_tool.
# - bash 3.2 compatible (macOS /bin/bash): no associative arrays, no mapfile.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Resources/ffmpeg-bin"
STAGE="$ROOT/build/tmp/ffmpeg-stage"
VERIFY="$ROOT/build/tmp/ffmpeg-relocated"
MANIFEST="$DEST/MANIFEST.txt"
export TMPDIR="$ROOT/build/tmp"
mkdir -p "$TMPDIR"

if [ "${1:-}" = "--clean" ]; then
  rm -rf "$DEST" "$STAGE" "$VERIFY"
  echo "removed $DEST (app will fall back to a system ffmpeg)"
  exit 0
fi

# ---------------------------------------------------------------- locate ffmpeg
FFMPEG_SRC="${FFMPEG_SRC:-}"
if [ -z "$FFMPEG_SRC" ]; then
  for cand in /opt/homebrew/bin/ffmpeg /usr/local/bin/ffmpeg "$(command -v ffmpeg || true)"; do
    if [ -n "$cand" ] && [ -x "$cand" ]; then FFMPEG_SRC="$cand"; break; fi
  done
fi
if [ -z "$FFMPEG_SRC" ] || [ ! -x "$FFMPEG_SRC" ]; then
  echo "error: no ffmpeg found (install with: brew install ffmpeg)" >&2
  exit 1
fi
FFMPEG_SRC="$(cd "$(dirname "$FFMPEG_SRC")" && pwd)/$(basename "$FFMPEG_SRC")"
FFMPEG_SRC="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$FFMPEG_SRC")"
echo "==> Source ffmpeg: $FFMPEG_SRC"
"$FFMPEG_SRC" -hide_banner -version 2>/dev/null | head -1 | sed 's/^/    /'

# ---------------------------------------------------------------- helpers
is_system_dep() {
  case "$1" in
    /usr/lib/*|/System/*|/Library/Apple/*) return 0 ;;
    @executable_path/*|@loader_path/*|@rpath/*) return 0 ;;
    *) return 1 ;;
  esac
}

# Resolve @rpath/... / relative entries against the binary's LC_RPATH entries and the
# usual Homebrew locations. Prints the resolved absolute path (or nothing).
resolve_dep() {
  local dep="$1" bin="$2" rp out
  case "$dep" in
    @rpath/*)
      local name="${dep#@rpath/}"
      while IFS= read -r rp; do
        [ -z "$rp" ] && continue
        # Substitute @loader_path with the binary's directory in the rpath.
        local expanded="${rp/@loader_path/$(dirname "$bin")}"
        expanded="${expanded/@executable_path/$(dirname "$bin")}"
        if [ -f "$expanded/$name" ]; then echo "$expanded/$name"; return 0; fi
      done < <(otool -l "$bin" | awk '/cmd LC_RPATH/{f=1} f&&/path /{print $2; f=0}')
      for cand in "/opt/homebrew/lib/$name" "/usr/local/lib/$name"; do
        [ -f "$cand" ] && { echo "$cand"; return 0; }
      done
      out="$(ls -d /opt/homebrew/Cellar/*/lib/"$name" 2>/dev/null | head -1 || true)"
      [ -n "$out" ] && { echo "$out"; return 0; }
      return 1 ;;
    /*)
      [ -f "$dep" ] && { echo "$dep"; return 0; }
      return 1 ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------- stage closure
rm -rf "$STAGE" "$VERIFY"
mkdir -p "$STAGE"
cp -f "$FFMPEG_SRC" "$STAGE/ffmpeg"
chmod u+w "$STAGE/ffmpeg"

echo "==> Collecting non-system dylib closure"
# bash 3.2 chokes on empty-array expansion under `set -u`, so the work queue is a
# newline-delimited file instead of an array.
QUEUE_FILE="$STAGE/.queue"
printf '%s\n' "$STAGE/ffmpeg" > "$QUEUE_FILE"
PROCESSED=0
DYLIB_COUNT=0
while [ -s "$QUEUE_FILE" ]; do
  BIN="$(head -1 "$QUEUE_FILE")"
  tail -n +2 "$QUEUE_FILE" > "$QUEUE_FILE.next" || true
  mv -f "$QUEUE_FILE.next" "$QUEUE_FILE"
  PROCESSED=$((PROCESSED + 1))
  # `otool -L` lines: "<path> (compatibility version ..." — skip the header line.
  while IFS= read -r DEP; do
    [ -z "$DEP" ] && continue
    is_system_dep "$DEP" && continue
    RESOLVED="$(resolve_dep "$DEP" "$BIN" || true)"
    if [ -z "$RESOLVED" ]; then
      echo "error: cannot resolve dependency '$DEP' of $(basename "$BIN")" >&2
      exit 1
    fi
    BASE="$(basename "$RESOLVED")"
    TARGET="$STAGE/$BASE"
    if [ ! -f "$TARGET" ]; then
      cp -f "$RESOLVED" "$TARGET"
      chmod u+w "$TARGET"
      printf '%s\n' "$TARGET" >> "$QUEUE_FILE"
      DYLIB_COUNT=$((DYLIB_COUNT + 1))
    fi
    install_name_tool -change "$DEP" "@loader_path/$BASE" "$BIN"
  done < <(otool -L "$BIN" | tail -n +2 | awk '{print $1}')
done
rm -f "$QUEUE_FILE"

echo "    binaries processed: $PROCESSED (closure size $DYLIB_COUNT dylibs)"

# ---------------------------------------------------------------- ids + signing
echo "==> Rewriting dylib IDs and re-signing (ad-hoc)"
for f in "$STAGE"/*.dylib; do
  [ -e "$f" ] || continue
  install_name_tool -id "@loader_path/$(basename "$f")" "$f"
done
# Re-sign executable + dylibs; install_name_tool invalidates the original signature.
for f in "$STAGE"/*; do
  codesign --force --sign - --timestamp=none "$f" >/dev/null 2>&1 || {
    echo "error: codesign failed for $(basename "$f")" >&2
    exit 1
  }
done

# ---------------------------------------------------------------- verify links
echo "==> Verifying no absolute Homebrew references remain"
BAD=0
for f in "$STAGE"/*; do
  if otool -L "$f" | tail -n +2 | awk '{print $1}' | grep -qE '^(/opt/homebrew|/usr/local|/tmp/)'; then
    echo "  BAD refs in $(basename "$f"):" >&2
    otool -L "$f" | grep -E '^\s+(/opt/homebrew|/usr/local|/tmp/)' >&2 || true
    BAD=1
  fi
done
[ "$BAD" -eq 0 ] || { echo "error: bundle is not self-contained" >&2; exit 1; }

# ---------------------------------------------------------------- verify runtime
echo "==> Verifying the staged copy (empty environment)"
env -i "$STAGE/ffmpeg" -hide_banner -version >/dev/null
env -i "$STAGE/ffmpeg" -hide_banner -loglevel error -f lavfi -i testsrc=duration=1:size=160x120:rate=10 \
  -c:v libx264 -preset ultrafast -f null - >/dev/null
echo "    ffmpeg runs and encodes with empty env"

echo "==> Verifying a relocated copy (Contents/Resources/ffmpeg-bin layout)"
mkdir -p "$VERIFY/Contents/Resources"
cp -a "$STAGE" "$VERIFY/Contents/Resources/ffmpeg-bin"
env -i "$VERIFY/Contents/Resources/ffmpeg-bin/ffmpeg" -hide_banner -version >/dev/null
env -i "$VERIFY/Contents/Resources/ffmpeg-bin/ffmpeg" -hide_banner -loglevel error \
  -f lavfi -i testsrc=duration=1:size=160x120:rate=10 -c:v libx264 -preset ultrafast -f null - >/dev/null
echo "    relocated copy runs (no DYLD_* env, no /opt/homebrew)"

# ---------------------------------------------------------------- install
echo "==> Installing into Resources/ffmpeg-bin"
rm -rf "$DEST"
cp -a "$STAGE" "$DEST"
chmod +x "$DEST/ffmpeg"

# A short manifest for QA/reproducibility (harmless extra file in the bundle).
{
  echo "CCloud bundled ffmpeg"
  echo "source: $FFMPEG_SRC"
  echo "version: $("$DEST/ffmpeg" -hide_banner -version 2>/dev/null | head -1)"
  echo "built: $(date '+%Y-%m-%d %H:%M:%S %z')"
  echo "files: $(ls -1 "$DEST" | wc -l | tr -d ' ')"
  echo "size: $(du -sh "$DEST" | cut -f1)"
  echo "links are @loader_path/<basename>; every Mach-O is ad-hoc signed"
  echo ""
  echo "sha256:"
  (cd "$DEST" && shasum -a 256 ffmpeg *.dylib | sed 's/^/  /')
} > "$MANIFEST"

COUNT=$(ls -1 "$DEST" | wc -l | tr -d ' ')
SIZE=$(du -sh "$DEST" | cut -f1)
echo "==> Done: $DEST ($COUNT files, $SIZE) — self-contained, ad-hoc signed"
