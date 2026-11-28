#!/bin/bash
# Build + run the schema-v1 live catalog contract harness on a macOS runner:
#
#   Tests/live-foundation/run.sh
#
# Compiles the *production* `Sources/Core/` files the live foundation owns — `PersianNumber.swift`,
# `Models.swift` and `LiveTVModels.swift` (the runtime row types the built-in adapter reads),
# `LiveTVM3UText.swift`, `LiveTVContracts.swift`, `LiveTVCatalogCodec.swift`, `LivePlaylistParser.swift`,
# `LiveTVChannelIdentity.swift`, `UnifiedLiveCatalog.swift`, `BuiltInLiveCatalogAdapter.swift` and
# `LiveCatalogStore.swift` (the task B4-2 persistence seam, which is why the harness now writes to a temporary
# directory) —
# together with `main.swift`, so the binary under test is the code the
# app ships rather than a copy of it. The list is explicit rather than a glob: a new production file that
# nobody adds here is silently outside the harness, which is how a mirror port can drift unnoticed. Then it judges the run by exactly three things: the compiler
# succeeded, the process exited zero, and the harness reported at least MIN_ASSERTIONS
# checks. That last rule is what stops a harness that stops executing its groups (a
# renamed helper, an early return) from passing quietly, which is how contract tests
# usually stop protecting anything.
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
# Raised 150 -> 420 after task B3-S landed, because the harness counted exactly 420 checks on the
# hosted run that turned that commit green (`==> live foundation assertions: 420 (floor 150)`). The
# floor is a ratchet, not an estimate: a group that stops executing now fails the job instead of
# lowering the count unnoticed, and a legitimate reduction has to be argued in the commit that makes it.
#
# Raised 420 -> 432 after the singleton-seeding precondition landed, because the harness counted exactly 432
# checks on the hosted run that verified it at 45bcf65 (`==> live foundation assertions: 432 (floor 420)`, job
# 140918188906). The number is read off the runner's own log rather than computed from the diff: an earlier
# probe on the owner's Mac reported 168 for a state that hosted scored 420, and that figure is recorded in
# EXECUTION_LOG.md as inadmissible evidence, not as a floor.
MIN_ASSERTIONS=432

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/live_foundation"
SDK="$(xcrun --show-sdk-path)"

echo "==> Compiling live_foundation (swiftc, production LiveTVContracts + LiveTVCatalogCodec + LivePlaylistParser + channel identity)"
xcrun swiftc \
  -O \
  -swift-version 5 \
  -module-name CCloudLiveFoundationTests \
  -module-cache-path "$WORK/modulecache" \
  -target arm64-apple-macos15.0 \
  -sdk "$SDK" \
  "$ROOT/Sources/Core/PersianNumber.swift" \
  "$ROOT/Sources/Core/Models.swift" \
  "$ROOT/Sources/Core/LiveTVModels.swift" \
  "$ROOT/Sources/Core/LiveTVM3UText.swift" \
  "$ROOT/Sources/Core/LiveTVContracts.swift" \
  "$ROOT/Sources/Core/LiveTVCatalogCodec.swift" \
  "$ROOT/Sources/Core/LivePlaylistParser.swift" \
  "$ROOT/Sources/Core/LiveTVChannelIdentity.swift" \
  "$ROOT/Sources/Core/UnifiedLiveCatalog.swift" \
  "$ROOT/Sources/Core/BuiltInLiveCatalogAdapter.swift" \
  "$ROOT/Sources/Core/LiveCatalogStore.swift" \
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
