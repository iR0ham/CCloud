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

## 2026-11-28 (later) — Hosted verification of the remediation slice at `7b2db7b`

- The remediation slice was committed and pushed only to `ci/github-first-foundation`. Remote head confirmed by `git ls-remote`: `7b2db7b29808723d73ce6517d2dd841984959982`, commits `ec34633` (legal packaging), `0f3a0d8` (webOS transport), `7b2db7b` (docs). `main` remains at `6dfd925`. Worktree was clean after push.
- Hosted ledger at `7b2db7b`:
  - Quality `46083219680`: **success**. The canonical-notice gate that failed at `3d6e876` is now green, and `Tests/test_stage_legal.py` ran on the runner.
  - CI `46083219625`: **failure** confined to `webOS static JS/JSON/service validation`. The new step `Run webOS transport regressions` reported `# tests 8 / # pass 5 / # fail 3`. The three failures are exactly the `loadService` cases; each asserted `errorCode === 'response-too-large'` and received `undefined`. Flutter tests, macOS typecheck and version/metadata jobs passed.
  - Build all platforms `46083219805`: **failure** confined to `android / Android/TV universal APK + AAB`, step "Assert APK identity, version, TV launcher/banner, and activity configuration". macOS, Windows (analyze, release build, runtime smoke, installer install/startup smoke) and webOS IPK jobs succeeded.
- Root cause of the CI failure (verified from the log and source, not inferred): `webos_app/service/com.ccloud.tv.service/ccloud_service.js:6` binds `var URL = require('url')` and uses the legacy module functions `URL.parse` (:24) and `URL.resolve` (:54), while `Tests/webos/transport.test.js:42` injected `{ URL: URLclass }`. The WHATWG static `URL.parse` exists only on Node ≥ 22.1.0, and `.github/workflows/ci.yml:158-160` pins Node `20`, so `URL.parse` was `undefined` inside the sandbox and production code took its invalid-address branch, which carries no `errorCode`. The transport policy itself is not contradicted by these three failures.
- Correction to the earlier `3d6e876` entry in this log: the Android failure was **not** the `unzip | grep -q` SIGPIPE in the AAB assertion. At both `3d6e876` and `7b2db7b` the step aborts ~0.9 s after printing `applicationId=com.ccloud.ccloud versionName=2.0.0 versionCode=22`, i.e. before the AAB block. The `apkanalyzer manifest print` invocation has no exit-status check and every manifest/badging token is tested by a silent `grep -Fq`, so the runner cannot say which condition failed. That assertion block has never passed since it was introduced in `1a4902c`. The pipefail-safe AAB read remains correct and is kept.
- Legal-document integrity correction: the 40-hex value `652a1dd90711839acdccc08004056d25514ef2d8` was mislabeled "mpv archive SHA-256" in `SOURCES.md` and `THIRD_PARTY_NOTICES.md`. Read-only inspection of the pinned package `~/.pub-cache/hosted/pub.dev/media_kit_libs_windows_video-1.0.11` shows it is the **mpv git commit SHA-1** (`CHANGELOG.md` links `mpv-player/mpv@652a1dd`), encoded in the archive name `mpv-dev-x86_64-20230924-git-652a1dd.7z`, and the only archive integrity field the wrapper publishes is MD5 `a832ef24b3a6ff97cd2560b5b9d04cd8` (`windows/CMakeLists.txt:67-71`). The wrapper's real pub.dev archive SHA-256 is `dff76da2778729ab650229e6b4ec6ec111eb5151431002cbd7ea304ff1f112ab`. Both documents now state the identifiers with their correct algorithms and keep the Windows provenance blocker intact; no license, written offer, source archive or relinking procedure was invented.
- Local runtime/build/test status for this slice: **NOT VERIFIED** by mandate. All evidence above is GitHub-hosted.


## 2026-11-28 (later still) — Hosted ledger at `6fb03bf`, Android assertion root cause

- Pushed head confirmed by `git ls-remote`: `6fb03bff7f6c1feffa02cb2a840285d5cbcec263` on
  `ci/github-first-foundation`. `main` untouched at `6dfd925`. Three previously reported
  corrections were verified present in that HEAD by read-only `git show` inspection: the
  `node:url` module injection plus legacy-API guard in `Tests/webos/transport.test.js`, the
  attributable `require_token` assertions in `.github/workflows/build-android.yml`, and the
  commit-vs-checksum wording in `SOURCES.md`.
- Hosted ledger at `6fb03bf`:
  - Quality `46085379874`: **success** (Repository hygiene, Required NOTICE files, Version
    consistency, Workflow lint, Dependency vulnerability scan, Secret scan). The legal-document
    rewording kept the notice gate green.
  - CI `46085379959`: **success**, including `webOS static JS/JSON/service validation`. This is
    the first hosted proof that the `9979ea9` test-harness fix exercises the production transport
    policy on the pinned Node `20` runner; the three previously failing `loadService` cases pass.
  - Build all platforms `46085379924`: webOS IPK, macOS arm64, Windows analyze / release build /
    Skia compatibility package / runtime smoke / installer install+startup smoke all **success**.
    `android` (job `140793625386`) **failed** at step 15, the same assertion step as `7b2db7b`.
- The new diagnostics did their job and named the condition instead of aborting silently:
  `::error::APK manifest is missing the expected token: @drawable/tv_banner`, followed by the
  decoded manifest. Faithfully rendered tokens all reported `ok:` first (`android.software.leanback`,
  `android.intent.category.LEANBACK_LAUNCHER`, `android:banner=`, `android:taskAffinity=""`,
  `android.hardware.touchscreen`), and identity printed `applicationId=com.ccloud.ccloud
  versionName=2.0.0 versionCode=22`.
- Root cause (evidence, not inference): `apkanalyzer manifest print` decodes binary resources and
  renders references and flag enumerations as opaque values, never as source literals —
  `android:banner="@ref/0x7f070077"`, `android:launchMode="1"`,
  `android:configChanges="0x40003fb4"`, `android:windowSoftInputMode="0x10"`. Those four literal
  assertions therefore could never pass against that rendering, which explains why the block has
  failed identically since it was introduced in `1a4902c`. The Android source manifest is correct;
  the **assertion target** was wrong. This is a workflow defect, not a product defect.
- Fix in `.github/workflows/build-android.yml` (no token removed, no check optionalised):
  - literal tokens `@drawable/tv_banner`, `android:launchMode="singleTop"`, the full
    `android:configChanges="…"` flag list and `android:windowSoftInputMode="adjustResize"` are now
    asserted against the merged release manifest that aapt2 compiled into this APK, resolved from
    known AGP intermediate locations with a bounded `find` fallback and a hard failure if no such
    artifact exists;
  - the decoded APK manifest still asserts every attribute's **presence** (`android:launchMode=`,
    `android:configChanges=`, `android:windowSoftInputMode=`, `android:banner=`) plus the values it
    renders faithfully, so an attribute dropped from the shipped package still fails;
  - the portrait prohibition is now real in both directions: `android:screenOrientation="portrait"`
    is rejected in the merged declaration, and any `android:screenOrientation=` is rejected in the
    shipped package (the previous literal grep against the decoded manifest was vacuous because the
    value is an enum);
  - `require_token` now also dumps the specific artifact it checked.
- Confirmed from the same decoded manifest that no plugin contributes an orientation lock (only
  `com.ccloud.ccloud.MainActivity` and `io.flutter.plugins.urllauncher.WebViewActivity` appear, and
  `android:screenOrientation` occurs nowhere in it), so the new absence gate is safe for this tree.
- Independent review: the scoped re-review of `7b2db7b..6fb03bf` was requested through the Team and
  this time the delegation was **accepted** (`COLLABORATION_MCP_TEAM_LEADER_REQUIRED` from earlier
  attempts was transient session shape, not a permanent block).
- New recovery checkpoint created: `docs/reports/OVERNIGHT_EXECUTION_STATE.md`.
- Local runtime/build/test status for this slice: **NOT VERIFIED** by mandate. The corrected Android
  assertion has not yet run on a runner; it is **PUSHED, NOT YET HOSTED VERIFIED** until the next
  `Build all platforms` run.
