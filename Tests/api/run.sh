#!/bin/bash
# Build + run the live CCloud API verification harness (owned by api-data).
#
#   Tests/api/run.sh
#
# Compiles the *real* Sources/Core/Models.swift + Sources/Core/APIClient.swift together with the
# harness (so it tests production code, not a copy), then runs every endpoint against the live
# backend. Exits non-zero if any check fails. Build artifacts stay inside Tests/api/build.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
API="$ROOT/Tests/api"
BUILD="$API/build"
OUT="$API/out"
CACHE="$BUILD/modulecache"
TMPD="$BUILD/tmp"
BIN="$BUILD/verify_api"
SDK="$(xcrun --show-sdk-path)"

mkdir -p "$CACHE" "$TMPD" "$OUT"
export TMPDIR="$TMPD"

echo "==> Compiling verify_api (swiftc, live Models+APIClient)"
xcrun swiftc \
  -O \
  -swift-version 5 \
  -parse-as-library \
  -module-name VerifyAPI \
  -module-cache-path "$CACHE" \
  -target arm64-apple-macos15.0 \
  -sdk "$SDK" \
  "$ROOT/Sources/Core/Models.swift" \
  "$ROOT/Sources/Core/APIClient.swift" \
  "$API/verify_api.swift" \
  -o "$BIN"

echo "==> Running live verification (this hits the backend, ~1-2 min)"
set +e
"$BIN" "$@" 2>&1 | tee "$OUT/verify.log"
STATUS="${PIPESTATUS[0]}"
set -e

echo "==> verify_api exit status: $STATUS"
exit "$STATUS"
