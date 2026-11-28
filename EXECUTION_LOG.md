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

## 2026-11-28 (final) — Android manifest gate green on a runner for the first time

- Pushed head `8a1ef3fcd15a40df703024bcc394e37e6025fd50` (`88bc7ea` workflow fix + `8a1ef3f` docs)
  confirmed by `git ls-remote`. `main` still `6dfd925`.
- Hosted ledger at `8a1ef3f`: CI `46087125795` **success**, Quality `46087125801` **success**,
  Build all platforms `46087125808` **success** with no skipped step in the Android job
  (`140799202503`, 23 steps, 0 failed, 0 skipped).
- Assertion evidence, quoted from the runner log:
  `merged manifest artifact: build/app/intermediates/merged_manifest/release/outputReleaseAppLinkSettings/AndroidManifest.xml`,
  then `ok:` for all eight decoded-APK tokens, `ok:` for all four merged-manifest literals
  (`@drawable/tv_banner`, `android:launchMode="singleTop"`, the full `android:configChanges` list,
  `android:windowSoftInputMode="adjustResize"`), `ok:` for the three badging tokens, and
  `APK/AAB legal assertions passed: 14 files per package`. Identity printed
  `applicationId=com.ccloud.ccloud versionName=2.0.0 versionCode=22`.
  The artifact resolution therefore used the bounded `find` fallback, because this AGP layout puts
  the merged manifest under `merged_manifest/release/outputReleaseAppLinkSettings/`; promoting that
  path into the explicit candidate list is a known hardening, deferred so it does not spend an extra
  Android cycle on its own.
- Artifacts produced and checksummed on the runner:
  `CCloud-Android-2.0.0-22-internal-debug-signed.apk` SHA-256
  `df075103357a5e5eaf91b83bea0f46cc197cd9ecd143ef47442ab55d56e19609`,
  `CCloud-Android-2.0.0-22-internal-debug-signed.aab` SHA-256
  `9f911f0137da40e3de57c9bc4143ef9801604af413ee5f9a578a42b7cc4cb36c`,
  `SIGNING-Android.txt` = `internal-debug-signed` (keystore secrets are absent from this repository,
  so no release-signed claim is made) and `DISTRIBUTION-Android.txt` =
  `INTERNAL-ONLY-BLOCKED-RELINKING`. The Android distribution blocker is untouched.
- Scope boundary that still holds: this is **build-time** proof that the packaged APK/AAB declare the
  TV launcher contract and carry the canonical legal payloads. It is not device or runtime acceptance
  on Android phone, Android TV, macOS, Windows or webOS, and it does not approve any release gate.
- Ledger sequencing note: this addendum is committed locally and deliberately not pushed while the
  Full-stack Engineer is appending to the same files for the Windows/provenance/webOS evidence-gap
  slice; it will be rebased onto their pushed head to avoid two competing appends.
- Local runtime/build/test status: **NOT VERIFIED** by mandate; every statement above is hosted log
  evidence.

## 2026-11-28 (CI evidence gaps) — Windows legal byte-equality, offline provenance, bounded dev proxy

Full-stack Engineer slice over the three gaps `docs/reports/OVERNIGHT_EXECUTION_STATE.md` listed as
still open. Baseline `8a1ef3f`, pushed head `2a244aad359444bd80bbeb50468362d006aab396`, one commit per
concern:

- `221ce95` — `scripts/assert-windows-package.ps1`: the 14 staged legal paths are now SHA-256 compared
  against the canonical copies in the same checkout (`$PSScriptRoot/..`), in addition to the existing
  existence checks for the exe, `flutter_windows.dll`, the three MSVC CRT DLLs, `libmpv-2.dll` and
  `data/app.so`. The file list was split into `$runtimeFiles` + `$legalFiles` so the existing
  incompleteness message is unchanged; every mismatch is emitted as a `::error::` annotation naming the
  file with both digests, then a single throw. The compared set was read off
  `scripts/bundle-msvc-runtime.ps1` (three documents at the package root plus the whole `Legal/` tree),
  not assumed, and matches the 14 files `scripts/stage_legal.py` stages.
- `9b55536` — `scripts/verify_provenance.py` (new) plus `Tests/test_verify_provenance.py` (new) wired as
  two blocking steps in the `required-notices` job of `.github/workflows/quality.yml`, which therefore
  gained `actions/setup-python` pinned to `a26af69b…` (`v5`, Python 3.12). The checker parses both
  documented forms (the `Retained text:` / `Text SHA-256:` bullet pair and the `| path | url | digest |`
  table), recomputes SHA-256 from the bytes in the checkout, and fails on a mismatch, a missing file, a
  path that escapes the checkout, a retained bullet with no digest, an orphan digest, a non-64-hex
  digest, the same file documented twice with different digests, and any file in `Legal/licenses/` that
  `SOURCES.md` never mentions. It is offline by construction: the media_kit pub.dev archive digests are
  deliberately skipped because those tarballs are not in the checkout, which is why table rows are
  filtered by whether the first cell looks like a repository-relative path.
- `2a244aa` — `webos_app/app/js/net.js`: `proxyFetch` (the localhost-only dev branch) now ends in the
  shared `readBoundedText` instead of `response.text()`, so the last unbounded read path in the
  transport layer is covered by the same 8 MiB cap and the same `response-too-large` policy error.
  `Tests/webos/transport.test.js` gained two append-only regressions (`ok 9`, `ok 10` in the hosted run);
  the eight previous tests were not touched, and the new ones assert `textCalls: 0`, so a regression to
  the unbounded `text()` path cannot pass them.

Hosted evidence, all at `2a244aa` (`gh run list --commit <full SHA>`), nothing run locally:

- Quality `46087990020` **success**. `Required NOTICE files` (`140801997670`) ran
  `python3 scripts/verify_provenance.py` and printed ten `provenance: ok Legal/licenses/…` lines with
  sizes and digests, then the count that proves the recomputation happened:
  `provenance: 10 retained files verified against SOURCES.md (offline, recomputed SHA-256, no network fetch)`.
  `python3 Tests/test_verify_provenance.py` then printed `Ran 13 tests in 0.005s` / `OK`.
- CI `46087990047` **success**, including `webOS static JS/JSON/service validation` (`140801998020`)
  with `# tests 10`, `# pass 10`, `# fail 0` on the pinned Node `20` runner — i.e. the ten transport
  regressions, the two dev-proxy cases among them.
- `Build all platforms` `46087990039` **completed success**, 8/8 jobs. The new Windows assertion printed
  `Legal files are SHA-256 byte-equal to the canonical repository copies (14 compared): D:\a\CCloud\CCloud`
  in three separate packages: `Windows release build` (`140802337977`) for
  `D:\a\_temp\ccloud-release\windows`, `Windows installer install + smoke test` (`140803894618`) for the
  real install target `C:\Program Files\CCloud`, and `Windows compatibility package (Skia)`
  (`140803894634`) for `…\windows-compat`. The installer-job line is stronger evidence than a staged
  directory: the bytes that reach the installed tree are the canonical ones.
- `android / Android/TV universal APK + AAB` (`140802338051`) is **success at this head too**, so the
  `8a1ef3f`-baseline Android evidence above now holds after my three commits as well.
- Ledger sequencing: this branch also carries the two addenda that were deliberately held locally on top
  of my pushed head — `18dec96` (Android manifest gate) and `709d9ed` (recovery-checkpoint refresh) — so
  that one append per ledger file wins instead of two competing edits in the same file.

Falsifiability — the exact controlled mutation for each new assertion. These are stated deliberately,
not committed and not run: no local execution is permitted by mandate and a committed failing state
would break the branch.

- Windows byte-equality: append one byte to the staged `NOTICE` in a packaged directory after
  `bundle-msvc-runtime.ps1` has run. Existence still passes; the assert must emit
  `::error::staged legal file is not byte-equal to the canonical copy: NOTICE: package <hash> != canonical <hash>`
  and throw `Legal byte-equality failed for 1 staged file(s): NOTICE: …`. The pre-slice version passed.
- Provenance gate: flip one hex character in any `- Text SHA-256:` value in `SOURCES.md`, or append one
  byte to `Legal/licenses/GPL-2.0.txt` while leaving the document alone. Both must print
  `error: … digest mismatch for Legal/licenses/GPL-2.0.txt: SOURCES.md says <documented>, the file is <actual>`
  and exit 1. Deleting a `Text SHA-256:` bullet must produce
  `retained text … has no \`Text SHA-256\` entry`, and dropping an undocumented text into
  `Legal/licenses/` must produce `is packaged as a retained license text but has no digest entry in
  SOURCES.md`. The fixture-tree forms of the mismatch and mutated-byte cases are executed as tests
  `test_digest_mismatch_names_the_offending_file` and `test_mutated_license_byte_breaks_the_gate` inside
  `Tests/test_verify_provenance.py`, which the runner ran green, so the failure path itself has hosted
  evidence rather than only a stated prediction.
- webOS dev proxy: restore `return r.text();` in `proxyFetch`. Test 9 fails (the oversized body resolves,
  `textCalls` becomes 1, `cancels` 0) and test 10 fails on `textCalls: 0`; the other eight still pass,
  which is exactly why this path was invisible before.

Still unverified after this slice, deliberately:

- Nothing here is device or runtime acceptance. The Windows jobs prove install and launch on a runner,
  not playback; Android, macOS and webOS still have no device evidence, and the four distribution
  labels stay `INTERNAL-ONLY-*`. `Legal/DISTRIBUTION_STATUS.md` and the release gate variables are
  untouched. Canonical version/build stayed `2.0.0` / `22`, and no Phase B multi-source or subtitle
  contract work was started.
- The dev-proxy bound is Node 20 `vm` evidence against the real `net.js`, not a Chromium 68 browser run;
  the ES2017 compatibility of the change is argued from the diff (function call into an existing helper,
  no new syntax) rather than from a webOS device.
- The provenance gate proves the retained texts match the digests this repository documents, not that
  those texts are the true upstream license bodies.
- Platform byte-equality is now uniform rather than a gap: Android compares the extracted archive
  members against the canonical bytes, webOS `cmp`s the IPK payload, and `scripts/make_dist.sh`
  `cmp`s the macOS bundle resources during the hosted package step, but Windows alone previously checked
  only that the legal files existed. This slice closes that last asymmetry, so for every packaged
  platform: packaged legal file == canonical repository file (packaging assertion) and canonical
  repository file == the digest `SOURCES.md` claims (Quality provenance gate). The combination is what
  makes the documented digests transitively true for shipped packages, which neither half did alone.
- What that chain still does not prove: that the documented digest is the genuine upstream license text.
  Nothing fetches upstream, so the gate is internal-consistency evidence, not upstream verification, and
  the FFmpeg / libmpv / mpv native-media provenance, relinking, corresponding-source and signing
  blockers are unchanged by this slice.

Exact next action: hand `8a1ef3f..2a244aa` to the Code Reviewer for the scoped re-review, because the
previous review request stopped at `6fb03bf`. No further packaging- or provenance-assertion work is
queued behind this slice; the remaining critical path is that verdict plus owner-supplied device
acceptance and the legal/signing decisions, not more CI.
