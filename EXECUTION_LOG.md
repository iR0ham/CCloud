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

## 2026-11-28 (review) — Scoped re-review accepted with notes; Phase B1 unblocked

Append-only entry. The held ledger commits `18dec96` and `709d9ed` are now on the remote inside
`cbc48ee`; `git ls-remote origin refs/heads/ci/github-first-foundation` and local `HEAD` both return
`cbc48ee249a9402841369fe0087091ccc85d71b5`, and the worktree is clean. `main` is unchanged at
`6dfd925095b0090b623443f396388fd4d552db63`.

### What was requested and what came back

Two independent read-only tasks were dispatched after the evidence-gap slice landed: a scoped
re-review of `6fb03bf..cbc48ee` (the earlier review requests stopped at `7b2db7b` and `6fb03bf`, both
REJECT), and a hosted-evidence audit that re-derives every claimed runner line rather than trusting
this ledger.

- Code Reviewer: **ACCEPT WITH NOTES**. All four of its earlier blockers were confirmed closed on
  evidence, not on my description, and no finding in the new range is blocking. Phase B1 (Dart
  Multi-Source contracts plus frozen shared fixtures) was declared safe to start.
- Test Engineer: **all six audited claims VERIFIED, nothing refuted.** Every branch run examined is
  `run_attempt=1` with at most one run per workflow per SHA, the earlier failures at `3d6e876`,
  `7b2db7b`, `6fb03bf` and `28869df` are still recorded as failures, and the audited logs contain
  zero `##[error]` and zero `not ok` annotations — so no red action was hidden as green.
- One requested research task returned no result and is treated as an evidence gap rather than as a
  completed input; nothing in this entry depends on it.

### New hosted fact

`cbc48ee` (documentation only) is itself hosted green: Quality `46089580613`, CI `46089580608`, Build
all platforms `46089580637` with all eight jobs successful (Android job `140807097206`). The Android
manifest gate has now passed twice independently, at `8a1ef3f` and at `cbc48ee`. The Build run was
still `in_progress` when the engineer's entry above was written; that entry's refusal to claim it was
correct, and this line is the dated completion rather than a restatement.

### Reviewer notes and their disposition

- **N1 (Low/Medium)** — `.github/workflows/build-android.yml:207-209`: when the three explicit
  candidate paths are absent, the fallback takes the first `*release*`-matching manifest in sort
  order, so the four literal assertions are not provably bound to the bytes inside the APK under test.
  Both green runs resolved
  `build/app/intermediates/merged_manifest/release/outputReleaseAppLinkSettings/AndroidManifest.xml`,
  which is the app module's merged manifest, but that binding is circumstantial. Note that the
  resolved path is **not** one of the three explicit candidates, so the queued "promote the discovered
  path into the candidate list" idea was the wrong shape; the fix is to narrow the fallback to
  `*/merged_manifest/release/*`, fail on ambiguity, and assert a package-identity token such as
  `com.ccloud.ccloud` inside the chosen file.
- **N2 (Low)** — `build-android.yml:267-268` says the optional-touchscreen contract is asserted on the
  shipped package, but only the feature name is checked, so `android:required="true"` would still pass.
  The `6fb03bf` failure dump proves the decoded manifest renders `android:required="false"` faithfully,
  so the token can simply be asserted rather than the comment being softened.
- **N3 (Low)** — `scripts/verify_provenance.py:190-195` rejects absolute paths and `..` lexically but
  never canonicalizes, so `:237` and the digest step would follow a committed symlink out of the
  checkout while the `:255-260` sweep still counted it as a documented retained file.
- **N4 (Low)** — `docs/reports/OVERNIGHT_EXECUTION_STATE.md` still described `18dec96` as unpushed at
  `cbc48ee`; corrected in this commit's checkpoint update, together with the "resolved through the
  bounded `find` fallback" wording, which the direct log read at line 1928 confirms was accurate.
- **N5 (Informational)** — the new chain proves internal consistency (package bytes == canonical repo
  bytes == documented digests), never upstream authenticity. No fetch is performed on purpose, and this
  claim must not be widened in later reports.

### Gate integrity, stated so it can be re-checked mechanically

Required `require_token` assertions went from twelve to fifteen across the range; the orientation
prohibition went from one grep to two (portrait rejected in the merged manifest, any
`android:screenOrientation=` rejected in the shipped package); no literal was deleted, because the four
moved from the decoded manifest to the merged manifest with attribute-presence checks left behind.
`set -euo pipefail` is intact in all four Android script blocks. The only `continue-on-error: true` in
the repository is pre-existing at `.github/workflows/build-windows.yml:167` on **Build installer (Inno
Setup)**, a best-effort artifact-production step; the package asserts at `:141` and `:292`, the
installer install-and-launch job, and both new Quality provenance steps are hard-failing. The
`bundle-msvc-runtime.ps1` digest question is answered **no**: its fourteen outputs are always
hash-compared by the paired assert script, so a second digest list would duplicate the set and create
drift risk.

### Uncovered by all of this

Device and runtime acceptance is still absent for Android phone/TV, macOS, webOS and Windows media
playback; `cnativeapi.dll was not loaded by the running process` warnings mean the native plugin load
path is unproven even where the launch smoke test passed; macOS signing/notarization and the hosted UI
smoke steps are skipped in every Build run; `Live API verification` never ran (`inputs.live_api` false);
the webOS dev-proxy proof is Node 20 `vm` evidence, not Chromium 68; artifact hashes are the runner's own
`sha256sum` output, not third-party attestation. All of it is build-time CI evidence. Production release
remains blocked, and the reviewer independently confirmed that nothing in this range permits a release
claim.

Exact next action: land N1 + N2 + N3 as one focused gate-hardening slice with a mutation-shaped
regression each, hosted RED then GREEN at that SHA, then start Phase B1-D.

## 2026-11-28 (hardening slice + B1-D) — H1–H3 landed, Dart contracts hosted green

This section is appended after the reviewer's `1382a93` entry and records the slice that entry asked
for ("land N1 + N2 + N3 as one focused gate-hardening slice with a mutation-shaped regression each,
hosted RED then GREEN at that SHA, then start Phase B1-D"), plus Task B1-D of
`docs/superpowers/plans/2026-11-25-multi-source-subtitles.md`. Nothing above this line is restated or
corrected; the earlier entries remain the record of their own heads.

### Commits, one logical concern each

| SHA | Concern | Files |
| --- | --- | --- |
| `4c80ad3` | H1 — bind the merged-manifest assertions to the APK under test | `.github/workflows/build-android.yml` |
| `e1eb4db` | H2 — assert the optional touchscreen instead of describing it | `.github/workflows/build-android.yml` |
| `5a9ad4a` | H3 — canonicalize provenance paths before trusting containment | `scripts/verify_provenance.py`, `Tests/test_verify_provenance.py` |
| `4570277` | B1-D Step 1 — fixtures and the failing test (hosted RED) | `Tests/fixtures/migration/catalog-v1.json`, `Tests/fixtures/migration/flutter-legacy-prefs.json`, `flutter_app/test/live_contracts_test.dart` |
| `ea28b29` | B1-D Step 3 — contracts and codec | `flutter_app/lib/core/live_contracts.dart`, `flutter_app/lib/core/live_catalog_codec.dart` |
| `eb052b2` | B1-D analyzer cleanup (branch head) | `flutter_app/test/live_contracts_test.dart`, `flutter_app/lib/core/live_catalog_codec.dart` |

H1 changed the candidate list, the fallback and the identity assertions; H2 added the
`android:required="false"` token and its feature pairing; neither removed an assertion. Across `4c80ad3`
and `e1eb4db`, `build-android.yml` gains 55 lines and loses 4: the old candidate-loop terminator, the old
`find … -path '*release*' … | sort | head -1 || true` fallback, and the two comment lines the new pairing
comment replaced. The required-assertion count in that workflow goes from fifteen `require_token` call
sites to eighteen (`:273`, `:274`, `:288`), plus the non-`require_token` touchscreen pairing block.
`set -euo pipefail` is intact in all four script blocks, and the
only `continue-on-error: true` in the repository is still the pre-existing Inno Setup step at
`.github/workflows/build-windows.yml:167`, untouched by instruction.

### Hosted evidence, all of it on GitHub runners

No local build, test, analyze, format or package command was run at any point in this slice. Local
runtime is NOT VERIFIED by design, so every claim below is a runner log line.

| Head | Quality | CI | Build all platforms |
| --- | --- | --- | --- |
| `5a9ad4a` (H1+H2+H3) | `46093092478` success | `46093092487` success | `46093092524` success, 8/8 jobs |
| `4570277` (B1-D RED) | `46093489916` success | `46093489869` **failure**, job `140819528805`, step `Analyze` | `46093489864` cancelled while still queued, no job started |
| `ea28b29` (B1-D impl) | `46093928872` success | `46093928877` **failure**, job `140820881485`, step `Analyze` | `46093928922` **failure** at `Analyze` in jobs `140821258518` (windows/Dart analyze) and `140821258527` (android), same root cause |
| `eb052b2` (head) | `46094277018` success | `46094276971` success, job `140821955659` | `46094276974` success, 8/8 jobs, android job `140824185335` |

`Live API verification` is `skipped` in every CI run because `inputs.live_api` is false; that is the
documented policy state, not a suppression added here. The RED commit therefore has its failing evidence
in CI (`ci.yml` runs the `flutter` job), and the cancellation of its Build run is a concurrency-group
replacement of a queued run under `build-platforms.yml:39-41`, not a suppressed test.

### Runner lines that prove the new assertions executed

| Assertion | Quoted runner line |
| --- | --- |
| H1 explicit-candidate selection | `merged manifest artifact: build/app/intermediates/merged_manifest/release/outputReleaseAppLinkSettings/AndroidManifest.xml` (run `46093092524`, job `140818355917`; repeated at the head in run `46094276974`, job `140824185335`) |
| H1 identity token, merged manifest | `ok: merged manifest contains com.ccloud.ccloud` |
| H1 identity token, shipped package | `ok: APK manifest contains package="com.ccloud.ccloud"` |
| H2 optional-touchscreen value | `ok: APK manifest contains android:required="false"` |
| H2 feature/value pairing | `ok: APK manifest pairs android.hardware.touchscreen with android:required="false"` |
| H3 provenance gate | `provenance: 10 retained files verified against SOURCES.md (offline, recomputed SHA-256, no network fetch)` |
| H3 regression suite | `Ran 14 tests in 0.007s` / `OK` (was 13 tests before the symlink vector) |
| B1-D RED cause | `error • Target of URI doesn't exist: 'package:ccloud/core/live_catalog_codec.dart' • test/live_contracts_test.dart:4:8 • uri_does_not_exist` and the same for `live_contracts.dart:5:8`, plus `Undefined name 'LiveCatalogMigration'` — exactly the Step 2 prediction |
| B1-D GREEN analyze | `No issues found! (ran in 15.3s)` (run `46094276971`, job `140821955659`) |
| B1-D GREEN tests | `🎉 133 tests passed, 1 skipped.`, with all five `live_contracts_test.dart` cases marked ✅ |

The skipped test is the pre-existing macOS-host-only `platform_identity_test.dart` case, not anything
added here.

### Deliberate deviations, recorded so the plan and the log cannot drift

- **H1 identity token is derived, not hardcoded.** The review asked for "a package-identity token such
  as `com.ccloud.ccloud`" asserted inside the selected manifest. The step asserts `$APP_ID`, which
  `apkanalyzer manifest application-id "$APK"` reads from the APK under test and which the same script
  already pins with `test "$APP_ID" = "com.ccloud.ccloud"`. That is strictly stronger than a literal in
  `$MERGED`: the token comes from the artifact, so a foreign release manifest that merely happens to sit
  under `build/app/intermediates` cannot satisfy the pairing `require_token "APK manifest" "$MANIFEST"
  package="$APP_ID"` plus `require_token "merged manifest" "$MERGED" "$APP_ID"`.
- **B1-D's test file drops one import.** The plan's Step 1 text imports `package:ccloud/core/live_catalog_codec.dart`
  while every assertion reaches the codec through `LiveCatalogMigration`, so at `ea28b29` the hosted
  `flutter analyze` failed with `warning • Unused import: 'package:ccloud/core/live_catalog_codec.dart'
  • test/live_contracts_test.dart:4:8 • unused_import`. The gate was not weakened; the dead import was
  removed at `eb052b2`, all five tests and every assertion stay byte-for-byte as the plan writes them,
  and a comment records why the import is absent. `_optDateText` also changed from an explicit `null`
  comparison to `value?.toUtc().toIso8601String()` for the one `prefer_null_aware_operators` info in the
  same report.
- **The `ea28b29` CI failure is not gate noise.** `flutter analyze` runs before `flutter test`, so the
  warning aborted the job and `Test` was `skipped`; the first run where the five new tests actually
  executed is `46094276971`.

### Falsifiability by controlled mutation — NOT EXECUTED

No broken commit was pushed and no mutation was run on a runner; the whole repository stayed green at
every pushed head except the two documented RED states above. Each row names the edit that would make
the assertion fail and the `::error::` text the runner would then print.

| New assertion | Controlled mutation (NOT EXECUTED) | Expected runner output (NOT EXECUTED) |
| --- | --- | --- |
| H1 candidate list | delete the `outputReleaseAppLinkSettings/AndroidManifest.xml` entry and make the four explicit paths absent | `::error::the release merged AndroidManifest.xml was not found; the literal manifest contract cannot be checked` only if the narrowed `*/merged_manifest/release/*` glob also misses; with the glob present the same artifact is still selected, which is why the fallback is retained |
| H1 fallback ambiguity | make AGP emit two `*/merged_manifest/release/*` manifests (e.g. an extra variant directory) | `::error::the merged-manifest fallback is ambiguous (2 candidates); refusing to assert the literal manifest contract against a guessed artifact` plus one `fallback candidate:` line each |
| H1 identity binding | point `$MERGED` at a manifest whose `package=` differs from the APK's application id | `::error::merged manifest is missing the expected token: com.ccloud.ccloud` |
| H2 optional touchscreen | set `android:required="true"` for `android.hardware.touchscreen` in `android/app/src/main/AndroidManifest.xml` | `::error::APK manifest is missing the expected token: android:required="false"` |
| H2 pairing | move `android:required="false"` onto another `uses-feature` so the touchscreen entry loses it | `::error::the shipped package does not pair android.hardware.touchscreen with android:required="false"; a D-pad-only TV cannot install it` |
| H3 containment | revert `base = root.resolve(...)` / `target = (base / …).resolve(...)` to `target = root / Path(*pure.parts)` | `retained path must stay inside the checkout: Legal/licenses/MIT-one.txt`, and the new `test_documented_symlink_cannot_leave_the_checkout` goes RED while the same fixture verifies `1 / []` once the bytes are inside the checkout |
| B1-D schema gate | drop the `schemaVersion` preflight in `LiveCatalogStateCodec.decode` | `future and corrupt states fail closed` fails: `FormatException` is not thrown for `{"schemaVersion":2}` |
| B1-D omission rule | write `'streamUrl'` unconditionally in `_sourceJson` | `v1 fixture round-trips and secret URLs are not serialized` fails on `isNot(contains('streamUrl'))` |
| B1-D capability ceiling | let `_optCapability` return any string | the same test fails at the `'maybe'` case with `throwsFormatException` |
| B1-D additive defaults | require `recentWatches` / `sourcePolicy` instead of defaulting them | `additive v1 preference defaults to the standard source policy` fails with `live catalog preference.sourcePolicy must be a JSON object` |

The RED half of H3 was therefore stated, not executed, by instruction; the RED half of B1-D was
executed and is run `46093489869`.

### Interfaces B1-D now produces for B1-S and B1-J

`flutter_app/lib/core/live_contracts.dart` owns `PlaylistSourceType`, `PlaylistRefreshStatus`,
`SourceHealth`, `SourceOrigin`, `rendererSupportValues`, and the records `PlaylistRecord`,
`ChannelMember`, `ChannelSourceRecord`, `SourcePolicy`, `LivePlaybackContext`,
`PlaybackAttemptContext`, `LogicalChannel`, `ChannelAssociation`, `ChannelPreference`,
`ChannelWatchRecord`, `LiveCatalogState`, `CatalogIssue`, `UnifiedCatalogSnapshot`,
`LiveCatalogMigration.migrate(String?)` / `.encode(LiveCatalogState)`.
`flutter_app/lib/core/live_catalog_codec.dart` owns `LiveCatalogStateCodec.supportedSchemaVersion`,
`.decode(String)` and `.encode(LiveCatalogState)`. Shared fixtures produced:
`Tests/fixtures/migration/catalog-v1.json` and `Tests/fixtures/migration/flutter-legacy-prefs.json`,
both byte-identical to the plan's Shared Fixtures block (verified by `diff` against the plan lines, not
by eye). `Tests/fixtures/multi-source/*` stays unauthored here because B2 owns it, and no Swift or
JavaScript file was touched.

### Uncovered by all of this

Device and runtime acceptance remains absent for Android phone/TV, macOS, webOS and Windows media
playback; the Dart contracts are data and a codec, so nothing about playback, failover timing, the
`SourcePolicy` ceilings under load, or a real `SharedPreferences` round-trip is proven by a green
runner. `flutter_secure_storage` and `file_picker` are still absent by gate, so `streamSecretRef` has no
verified store behind it on any platform. Local runtime is NOT VERIFIED by mandate. Signing,
notarization, production distribution, EPG programme data and upstream authenticity of the retained
license texts are unchanged by this slice.

Exact next action: B1-S mirrors these contracts in Swift against the same
`Tests/fixtures/migration/catalog-v1.json`, then B1-J mirrors them in the webOS JavaScript, then B2
freezes the cross-language agreement fixtures.

## 2026-11-28 (project manager) — Independent re-derivation of the H1–H3 / B1-D entry

The section above was written by the implementing engineer and pushed while the project manager was
re-reading the same runner logs from the API. Rather than post a second copy of the same record, this
addendum states only what was independently confirmed, what was added, and one coordination fact.

Confirmed from fresh downloads, not from the report: `git ls-remote` equals local `HEAD`; the
hardening slice is green at `5a9ad4a` (Quality `46093092478`, CI `46093092487`, Build `46093092524`)
and the head is green at `eb052b2` (Quality `46094277018`, CI `46094276971`, Build `46094276974`,
completed `2026-11-28T02:00:31Z`, eight jobs all `completed success`). In Android job `140824185335`
the manager counted `20` `ok:` lines, `0` `##[error]` annotations, and **`0` skipped steps**, with
`merged manifest artifact: …/merged_manifest/release/outputReleaseAppLinkSettings/AndroidManifest.xml`
appearing exactly once; `APK/AAB legal assertions passed: 14 files per package` also appears once. The
provenance suite prints `Ran 14 tests` in both Quality runs (`0.011s` at `5a9ad4a`, `0.007s` at the
head), so the fourteenth test is executed, not merely committed. Windows installer job `140825644700`
reprinted `Legal files are SHA-256 byte-equal to the canonical repository copies (14 compared)` against
the installed tree `C:\Program Files\CCloud`, and webOS job `140821955598` on `node: v20.20.2` printed
`# tests 10 / # pass 10 / # fail 0 / # skipped 0`.

Three specific claims the report made were checked because they decide acceptance, and all three hold.
`build-android.yml` at head derives the identity token from the artifact rather than hardcoding it:
`:179` reads `APP_ID="$("$APKANALYZER" manifest application-id "$APK")"`, `:183` pins it with
`test "$APP_ID" = "com.ccloud.ccloud"`, and `:273`/`:274` then require that same value in the selected
merged manifest and as `package="…"` in the decoded shipped manifest. `require_token` call sites are
`15` at `1382a93` and `18` at head, and the only added `|| true` in the range is the
`grep -A2 -F 'android:name="android.hardware.touchscreen"' … > "$TOUCHSCREEN" || true` context dump,
which sits in front of a hard `::error::` + `exit 1` check. The `4570277` Build run
`46093489864` really is a queued-run cancellation with **zero jobs started**, so it neither supports
nor contradicts any platform gate.

Two points of precision to carry forward. First, the residual limit of H1 is narrower than the note
above implies but is not zero: the new assertions prove the selected merged manifest declares the same
`applicationId` as the APK under test, not that those exact file bytes were compiled into that APK, so
a stale artifact from the same module and variant could still satisfy the pair. That is the remedy the
review asked for, and the remaining gap is recorded here rather than presented as closed. Second, the
engineer's mid-task chat summary said the analyzer commit "only removed that dead import", while the
committed diff also rewrites `_optDateText` to `value?.toUtc().toIso8601String()`; the ledger entry
above discloses both correctly, so this is a reporting-precision note about the interim message, not a
defect in the recorded evidence.

Coordination fact: this branch's ledger tail is written by more than one member on one shared
checkout. The engineer's `7124c28` landed first, so the manager's overlapping draft was discarded
instead of committed, and this shorter addendum takes its place. Future appends must re-read
`git ls-remote` immediately before writing the tail.

Acceptance position: H1, H2 and H3 are **closed with hosted evidence**; Task B1-D is **implemented and
hosted-verified at unit level** — its RED (`46093489869`) and GREEN (`46094276971`, five named cases
inside `133 tests passed`) both exist — and `Tests/fixtures/migration/catalog-v1.json` plus
`flutter-legacy-prefs.json` were compared against the plan's Shared Fixtures block and match
byte-for-byte, so B1-S and B1-J may consume them as frozen. Nothing here changes the release posture:
all four platforms stay `INTERNAL-ONLY-*`, `RELEASE_PRODUCTION_READY` is unset, device and runtime
acceptance is NOT VERIFIED, and the falsifiable mutations for H1 and H2 remain **stated, not
executed** because no intentionally broken commit was pushed.

Exact next action: obtain a scoped independent review of `1382a93..41039b2` — the two workflow commits,
the provenance fix and the first Phase B Dart code — before any Swift file is written, because B1-S
duplicates the Dart contract shape and a defect found afterwards would be paid for three times.
