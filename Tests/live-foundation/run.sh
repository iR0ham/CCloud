#!/bin/bash
# Build + run the schema-v1 live catalog contract harness on a macOS runner:
#
#   Tests/live-foundation/run.sh
#
# Compiles the *production* `Sources/Core/LiveTVContracts.swift` and
# `Sources/Core/LiveTVCatalogCodec.swift` together with `main.swift`, so the binary
# under test is the code the app ships rather than a copy of it. Then it judges the
# run by exactly three things: the compiler succeeded, the process exited zero, and
# the harness reported at least MIN_ASSERTIONS checks. That last rule is what stops a
# harness that stops executing its groups (a renamed helper, an early return) from
# passing quietly, which is how contract tests usually stop protecting anything.
#
# No local counterpart is intended: the repository policy is GitHub-hosted builds
# only, so this script exists to run on `macos-15` from `.github/workflows/ci.yml`.
# Any Swift runtime evidence therefore comes from that job's log, never from a
# developer machine.
#
# Artifacts go in `mktemp -d` and are removed on exit, so a run can never leave a
# `Tests/live-foundation/build` directory behind; the repository forbids tracked build
# output, and `set -e` plus the trap keeps a failure from hiding one.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
MIN_ASSERTIONS=150

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/live_foundation"
SDK="$(xcrun --show-sdk-path)"

echo "==> Compiling live_foundation (swiftc, production LiveTVContracts + LiveTVCatalogCodec)"
xcrun swiftc \
  -O \
  -swift-version 5 \
  -module-name CCloudLiveFoundationTests \
  -module-cache-path "$WORK/modulecache" \
  -target arm64-apple-macos15.0 \
  -sdk "$SDK" \
  "$ROOT/Sources/Core/LiveTVContracts.swift" \
  "$ROOT/Sources/Core/LiveTVCatalogCodec.swift" \
  "$HERE/main.swift" \
  -o "$BIN"

echo "==> Running live catalog contract harness"
# The status is captured, not propagated through a pipe, so `grep` below can never be
# the reason a failing run looked successful.
set +e
OUTPUT="$("$BIN" "$ROOT" 2>&1)"
STATUS=$?
set -e
printf '%s\n' "$OUTPUT"
if [ "$STATUS" -ne 0 ]; then
  echo "FAIL: live foundation harness exited $STATUS" >&2
  exit "$STATUS"
fi

COUNT="$(printf '%s\n' "$OUTPUT" | sed -n 's/^assertions: \([0-9][0-9]*\)$/\1/p' | tail -n 1)"
if [ -z "$COUNT" ]; then
  echo "FAIL: harness printed no 'assertions: <n>' line, so the run cannot be judged" >&2
  exit 1
fi
if [ "$COUNT" -lt "$MIN_ASSERTIONS" ]; then
  echo "FAIL: harness reported $COUNT assertions, below the floor of $MIN_ASSERTIONS" >&2
  exit 1
fi

echo "==> live foundation assertions: $COUNT (floor $MIN_ASSERTIONS)"
echo "live foundation OK"
