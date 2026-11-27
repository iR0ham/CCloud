# CCloud Execution Log

This is an append-only execution record. New evidence is added as dated entries; earlier entries are not rewritten.

## 2026-11-24 — Android prerequisite repair and security follow-up

- Branch: `ci/github-first-foundation`.
- Pushed head: `3d6e8762ce8826a52297f83b5f6952a26f15ba44`.
- Commits included:
  - `69e1ca9` — public backend identifier centralization and bounded webOS fetch responses.
  - `3d6e876` — Android Linux native prerequisites and QA lookup from `BackendConfig.swift`.
- Hosted CI at `3d6e876`: **success**.
- Hosted Quality at `3d6e876`: **failure only because root `NOTICE` and `THIRD_PARTY_NOTICES.md` were absent**. The gate remains intentionally hard.
- Hosted platform build at `3d6e876`:
  - macOS arm64 build: **success**.
  - Windows analyze, release build, runtime smoke, installer install/startup smoke: **success**.
  - webOS IPK: **success**.
  - Android universal APK and AAB: both built successfully with application ID `com.ccloud.ccloud`, version `2.0.0`, version code `22`; the job then failed in package assertions before artifact upload.
- Android assertion failure evidence: the job reached the AAB manifest assertion after successful APK/AAB builds. The current command is `unzip -l "$AAB" | grep -Fq ...` under `set -o pipefail`; early `grep -q` exit can SIGPIPE `unzip` and produce a false failure. Fix by writing the archive listing to a file before grepping, then rerun hosted acceptance.
- Local runtime/build/test status: **NOT VERIFIED** by mandate; all runtime evidence comes from GitHub-hosted runners.

## 2026-11-24 — Legal notice and distribution-control implementation in progress

- Canonical `NOTICE`, `THIRD_PARTY_NOTICES.md`, `SOURCES.md`, `Legal/`, and `scripts/stage_legal.py` are being implemented.
- Workflow staging and package assertions are being added for macOS, Windows, Android/TV, and webOS.
- Production redistribution remains blocked for:
  - Android: missing verified relinking material for statically linked FFmpeg inside `libmpv.so`.
  - Windows: GPL/nonfree native-media evidence and incomplete exact build/source provenance.
  - macOS: release-specific FFmpeg/source inventory is not yet pinned or captured.
- No repository-wide `LICENSE`, written offer, corresponding-source archive, or relinking procedure is being invented.

## 2026-11-28 — Continuation audit, remediation, and pending-work plan

- Baseline verified: `ci/github-first-foundation` and its remote head were both `3d6e8762ce8826a52297f83b5f6952a26f15ba44`; no unpushed commits or open pull requests were found.
- Hosted ledger at the baseline remains: CI `45469044683` success, Quality `45469044590` failure, Build Platforms `45469044568` failure.
- Remediation now present in the worktree:
  - canonical legal documents, license texts, staging script, six legal regressions, and nested package assertions for macOS, Android, Windows, and webOS;
  - Windows staging commands resolve inside the checkout;
  - macOS staging avoids following symlinked destinations and rejects escaping staging paths;
  - Android AAB inspection is pipefail-safe;
  - webOS service and browser transports enforce `response-too-large`, preserve that policy across fallback, destroy redirect responses/requests, and read direct bodies with a bounded byte-counting reader;
  - `Tests/webos/transport.test.js` now contains eight deterministic regressions, including unknown-length oversize, exact 8 MiB, UTF-8 byte accounting, cancellation, one-shot completion, and fallback suppression.
- Phase A architecture audit and the detailed Phase B-G plan were inspected; no B1/B2 contract, parser, identity-hash, source-registry, or shared-fixture implementation files were present.
- The new pending-work inventory is `docs/reports/PENDING_WORK_COMPLETION_PLAN.md`. Its first critical path is to commit and push this remediation slice, run hosted CI/Quality/Build Platforms on the exact SHA, and obtain independent re-review before starting Phase B.
- No local build, test, analyze, format, package, install, signing, or runtime execution was performed. Hosted results for this remediation are **NOT VERIFIED** until the pushed SHA runs GitHub Actions.

