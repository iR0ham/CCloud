#!/bin/bash
# Fast typecheck of all Swift sources (no linking): scripts/typecheck.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
mkdir -p "$BUILD/modulecache" "$BUILD/tmp"
export TMPDIR="$BUILD/tmp"
SOURCES=()
while IFS= read -r -d '' f; do SOURCES+=("$f"); done < <(find "$ROOT/Sources" -name '*.swift' -print0 | sort -z)
swiftc -typecheck -swift-version 5 -parse-as-library -module-name CCloud \
  -module-cache-path "$BUILD/modulecache" -target arm64-apple-macos15.0 \
  -sdk "$(xcrun --show-sdk-path)" "${SOURCES[@]}"
echo "typecheck OK (${#SOURCES[@]} files)"
