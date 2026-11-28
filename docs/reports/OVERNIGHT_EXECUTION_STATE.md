# CCloud Overnight Execution State (recovery checkpoint)

Append-oriented operational checkpoint. Rewrite the "current" sections when they change;
dated evidence below is a ledger and must not be restated as history that did not happen.

## Snapshot

- Repository: `/Users/roham/Documents/CCloudMac`, remote `iR0ham/CCloud` (public).
- Working branch: `ci/github-first-foundation`.
- HEAD and pushed remote branch head were both
  `cbc48ee249a9402841369fe0087091ccc85d71b5` when the previous sentence was written; that was true at
  the time and is superseded here. As of this refresh the code head is
  `eb052b248ac0255fabbf30788bd964f2d35a5315`, and `git ls-remote` and local `HEAD` both returned
  `41039b253da00005ba9083ce08833e7188bae32c` (two ledger commits on top of it) before this file was
  edited — so on resume, re-run `git ls-remote` rather than trusting any head written here.
- Commit order on the branch, continuing the previous list: `cbc48ee` (three-closed-gates ledger
  addendum) → `1382a93` (accepted re-review + hardening items) → `4c80ad3` (**H1** merged-manifest
  binding) → `e1eb4db` (**H2** optional-touchscreen assertion) → `5a9ad4a` (**H3** provenance path
  canonicalization) → `4570277` (B1-D fixtures + failing tests, hosted RED) → `ea28b29` (B1-D Dart
  contracts + codec) → `eb052b2` (analyzer-clean) → `7124c28` + `41039b2` (ledger and plan appends).
- `main`: `6dfd925095b0090b623443f396388fd4d552db63` — untouched, never developed on.
- Worktree: clean.
- Open pull requests: none. Release tags: none (`v2.0.0` was never tagged).
- Canonical identity: version `2.0.0`, global build `22` (Android `versionCode 22`).
  The next release identity (expected `2.1.0` + build `23`) is still an undecided task.

## Hosted ledger (GitHub Actions is the only execution evidence permitted)

### At `8a1ef3f` (Android assertion fix)

| Workflow | Run | Result |
| --- | --- | --- |
| Quality | `46087125801` | **success** |
| CI | `46087125795` | **success** |
| Build all platforms | `46087125808` | **success** — Android job `140799202503`, 23 steps, 0 failed, **0 skipped**, so the assertion gate passed and the artifacts were named, checksummed and uploaded |

Runner log proof: `merged manifest artifact:
build/app/intermediates/merged_manifest/release/outputReleaseAppLinkSettings/AndroidManifest.xml`
(resolved through the bounded `find` fallback — promoting that path into the explicit candidate list
is a known hardening, not worth a lone Android cycle), `ok:` for all eight decoded-APK tokens, `ok:`
for all four merged-manifest literals, `ok:` for the three badging tokens, and
`APK/AAB legal assertions passed: 14 files per package`. Artifacts:
`CCloud-Android-2.0.0-22-internal-debug-signed.apk` SHA-256
`df075103357a5e5eaf91b83bea0f46cc197cd9ecd143ef47442ab55d56e19609`, AAB SHA-256
`9f911f0137da40e3de57c9bc4143ef9801604af413ee5f9a578a42b7cc4cb36c`, `SIGNING-Android.txt` =
`internal-debug-signed`, `DISTRIBUTION-Android.txt` = `INTERNAL-ONLY-BLOCKED-RELINKING`. The earlier
Android failure (`46085379924` step 15,
`::error::APK manifest is missing the expected token: @drawable/tv_banner`) was an assertion-target
defect: `apkanalyzer manifest print` renders references and flag enums opaquely
(`@ref/0x7f070077`, `launchMode="1"`, `configChanges="0x40003fb4"`, `windowSoftInputMode="0x10"`).

### At `2a244aa` (evidence-gap slice: Windows byte-equality, provenance digests, webOS dev proxy)

| Workflow | Run | Result and specific proof |
| --- | --- | --- |
| Quality | `46087990020` | **success**; `Required NOTICE files` ran `scripts/verify_provenance.py` and printed `provenance: 10 retained files verified against SOURCES.md (offline, recomputed SHA-256, no network fetch)` |
| CI | `46087990047` | **success**; webOS job printed `# tests 10 / # pass 10 / # fail 0`, including the two new dev-proxy cap regressions, with the eight earlier tests unchanged |
| Build all platforms | `46087990039` | **success** on all eight jobs; both Windows packages printed `Legal files are SHA-256 byte-equal to the canonical repository copies (14 compared)` |

`18dec96` carries the Android addendum to `EXECUTION_LOG.md` and was **held locally, not yet
pushed** when this section was written: members share this checkout and append to the same ledger
tail, so appends are serialized to avoid two competing sections. Superseded 2026-11-28: that hold
ended, and `18dec96` / `709d9ed` reached the remote inside `cbc48ee`.

### At `cbc48ee` (independent review and hosted-evidence audit)

| Item | Result |
| --- | --- |
| Quality `46089580613` | **success** |
| CI `46089580608` | **success** |
| Build all platforms `46089580637` | **success** on all eight jobs (Android job `140807097206`) — the ledger commit is hosted green too, so no claim here rests on an unfinished run |
| Code Reviewer verdict, `6fb03bf..cbc48ee` | **ACCEPT WITH NOTES** — all four earlier blockers closed; five notes N1–N5, none blocking; Phase B1 declared safe to start |
| Test Engineer hosted-evidence audit | **all six claims VERIFIED**, nothing refuted; `net.js@2a244aa` confirmed to route the dev proxy through the shared bounded reader with the 8 MiB cap and `response-too-large` intact, and confirmed ES2017-syntax-clean for the Chromium 68 target |

Reviewer notes and how they are triaged:

- **N1 (Low/Medium)** `.github/workflows/build-android.yml:207-209` — the `find` fallback picks the
  first `*release*` manifest by sort order, so the four literal assertions are not provably bound to
  the bytes inside *this* APK. The resolved path in both green runs was
  `build/app/intermediates/merged_manifest/release/outputReleaseAppLinkSettings/AndroidManifest.xml`
  (log line `merged manifest artifact: …`), which is the app module's merged manifest — but the
  binding is circumstantial, not enforced. Fix: narrow the fallback to `*/merged_manifest/release/*`,
  fail if more than one candidate remains, and add an identity token such as
  `require_token "merged manifest" "$MERGED" 'com.ccloud.ccloud'`.
- **N2 (Low)** `build-android.yml:267-268` — the comment claims the optional-touchscreen contract is
  asserted on the shipped package, but only the feature name is checked; `android:required="false"` is
  provably rendered faithfully by `apkanalyzer` (visible in the `6fb03bf` failure dump), so the token
  can simply be added.
- **N3 (Low)** `scripts/verify_provenance.py:190-195` — `_resolve_within` rejects absolute paths and
  `..` lexically but never canonicalizes, so a committed symlink inside `Legal/licenses/` would be
  followed outside the checkout at `:237` while the directory sweep at `:255-260` still counts it as
  documented.
- **N4 (Low)** this file's own Snapshot and "not yet pushed" lines were stale at `cbc48ee` — closed by
  the two edits above.
- **N5 (Informational)** the new chain proves internal consistency (package bytes == canonical repo
  bytes == `SOURCES.md` digests), not upstream authenticity of a license text. No network fetch is
  done on purpose; the claim must never be widened in later reports.

### At `5a9ad4a` (gate-hardening slice H1 + H2 + H3) and `eb052b2` (Task B1-D head)

| Head | Workflow | Run | Result and specific proof |
| --- | --- | --- | --- |
| `5a9ad4a` | Quality | `46093092478` | **success**; `provenance: 10 retained files verified against SOURCES.md (offline, recomputed SHA-256, no network fetch)` and `Ran 14 tests in 0.011s` / `OK` — the fourteenth test is the new `test_documented_symlink_cannot_leave_the_checkout` |
| `5a9ad4a` | CI | `46093092487` | **success** |
| `5a9ad4a` | Build all platforms | `46093092524` | **success**, 8/8 jobs; Android job `140818355917` printed `ok: merged manifest contains com.ccloud.ccloud`, `ok: APK manifest contains package="com.ccloud.ccloud"`, `ok: APK manifest contains android:required="false"` and `ok: APK manifest pairs android.hardware.touchscreen with android:required="false"` |
| `eb052b2` | Quality | `46094277018` | **success**; same provenance line, `Ran 14 tests in 0.007s` / `OK` |
| `eb052b2` | CI | `46094276971` | **success**; Flutter job `140821955659`: `No issues found! (ran in 15.3s)` and `🎉 133 tests passed, 1 skipped`, with all five `live_contracts_test.dart` cases green by name; webOS job `140821955598` on `node: v20.20.2`: `# tests 10 / # pass 10 / # fail 0`; the one skip is the pre-existing macOS-host-only `platform_identity_test.dart` case |
| `eb052b2` | Build all platforms | `46094276974` | **success**, completed `2026-11-28T02:00:31Z`; eight jobs all `completed success`; Android job `140824185335` has **0 failed and 0 skipped steps** with `20` `ok:` lines, `0` `##[error]` annotations and `APK/AAB legal assertions passed: 14 files per package`; Windows installer job `140825644700` reprinted `Legal files are SHA-256 byte-equal to the canonical repository copies (14 compared)` against `C:\Program Files\CCloud` |

Hosted RED for the test-first order: CI `46093489869` at `4570277` is **failure** in job
`140819528805`, step `Analyze`, with `Target of URI doesn't exist:
'package:ccloud/core/live_catalog_codec.dart'` (and `live_contracts.dart`) — the exact Step 2
prediction. Build `46093489864` at that SHA is **cancelled with zero jobs started** (a queued run
replaced by the next push), so it is evidence about nothing. `ea28b29` stayed red for a diagnosed
non-gate reason: CI `46093928877` job `140820881485` and Build `46093928922` jobs `140821258518` /
`140821258527` all failed only in step `Analyze` on `warning • Unused import …`, which is why `Test`
showed `skipped` there; `eb052b2` fixed the warning without touching an assertion.

Gate integrity across `1382a93..eb052b2`, re-derived by the project manager rather than copied:
`require_token` call sites went **15 → 18**; `build-android.yml` is `+55/−4`; the only added `|| true`
is the touchscreen context-window dump that feeds a hard `::error::` + `exit 1` check; no
`continue-on-error`, `set +`, test `skip`/`only`/`todo` or dropped required token appears in the range;
`set -euo pipefail` is intact in all four Android script blocks; the standing macOS skips (sign,
temporary keychain removal, hosted UI smoke, UI evidence upload) and the CI `Live API verification`
skip are unchanged.

### Earlier heads, for continuity

- `6fb03bf`: Quality `46085379874` success, CI `46085379959` success (first hosted proof of the
  `node:url` harness fix), Build Platforms `46085379924` failed only the Android assertion step.

- `7b2db7b`: Quality success; CI failed only `webOS static` (3 of 8, harness `url` mock defect);
  Build Platforms failed only the Android identity-assertion step.
- `3d6e876`: Quality failed (missing canonical notices); CI success; Build Platforms failed
  (Android assertion + a Windows runner communications loss).

Local build/test/analyze/package/runtime status: **NOT VERIFIED by mandate**, intentionally.
The owner's Mac is not used for project execution workloads.

## Completed and verified (evidence-backed)

1. Canonical legal packaging: root `NOTICE`, `THIRD_PARTY_NOTICES.md`, `SOURCES.md`, `Legal/`
   tree, `scripts/stage_legal.py`, six `Tests/test_stage_legal.py` regressions, and nested
   package assertions for macOS, Windows, Android and webOS — hosted Quality + Build evidence
   at `6fb03bf`.
2. webOS bounded transport: service and browser transports enforce `response-too-large`,
   destroy redirect responses/requests, use a bounded byte-counting reader, and suppress direct
   fallback only for that policy code — hosted `node --test` at `6fb03bf`.
3. Test-harness fidelity: `Tests/webos/transport.test.js` now injects the whole `node:url`
   module (production calls legacy `url.parse`/`url.resolve`) and fails loudly if those members
   disappear.
4. Android assertion diagnosability: `.github/workflows/build-android.yml` checks
   `apkanalyzer manifest print` and `aapt dump badging` exit status, labels every required token
   through `require_token`, and dumps the decoded manifest/badging on failure. No token was
   removed and the gate stays hard.
5. Windows mpv provenance wording: `SOURCES.md` / `THIRD_PARTY_NOTICES.md` now separate the
   upstream-attested mpv git commit `652a1dd90711839acdccc08004056d25514ef2d8` (40-hex SHA-1),
   the wrapper-published MD5 download check `a832ef24b3a6ff97cd2560b5b9d04cd8`, and the verified
   pub.dev archive SHA-256 `dff76da2778729ab650229e6b4ec6ec111eb5151431002cbd7ea304ff1f112ab`.
6. Phase A architecture audit (`docs/audits/MULTISOURCE_SUBTITLE_ARCHITECTURE_AUDIT.md`) and
   Phase B–G plan (`docs/superpowers/plans/2026-11-25-multi-source-subtitles.md`).
7. Pending-work inventory: `docs/reports/PENDING_WORK_COMPLETION_PLAN.md`, including the dated
   correction section for the `7b2db7b` hosted run.
8. Independent review closed: **ACCEPT WITH NOTES** for `6fb03bf..cbc48ee`, with all four earlier
   blockers confirmed resolved and the gate-integrity question answered mechanically — required
   `require_token` count went from 12 to 15, the orientation prohibition from 1 grep to 2, no literal
   was dropped (the four moved from the decoded manifest to the merged manifest, with attribute-
   presence checks left in their place), `set -euo pipefail` unchanged in all four Android script
   blocks, and no `continue-on-error`, `if-no-files-found: warn`, `skip` or `set +…` added anywhere
   in the range.
9. Gate integrity, stated precisely: the only `continue-on-error: true` in the repository is
   pre-existing at `.github/workflows/build-windows.yml:167` on **Build installer (Inno Setup)**, a
   best-effort artifact-production step. Every verification step is hard-failing: the package assert
   at `:141`, the compatibility assert at `:292`, the installer install+launch smoke job, and both
   new Quality provenance steps.
10. Hosted-evidence audit by the Test Engineer: all six claims VERIFIED from fresh runner logs,
    nothing refuted; all 26 branch runs are `run_attempt=1` with at most one run per workflow per SHA,
    and the failures at `3d6e876`, `7b2db7b`, `6fb03bf` and `28869df` remain recorded as failures —
    no red was converted to green.
11. Reviewer notes H1/H2/H3 closed on runners: `.github/workflows/build-android.yml` now selects the
    merged manifest from four explicit candidates, hard-fails on an ambiguous narrowed fallback, and
    binds `$APP_ID` (read from the APK under test) into both manifest assertions; the optional-
    touchscreen contract is asserted as a value and as a feature pairing; `_resolve_within` in
    `scripts/verify_provenance.py` canonicalizes both sides and re-checks containment, with a committed
    symlink regression that runs in Quality (`Ran 14 tests` / `OK`). Hosted green at `5a9ad4a` and
    `eb052b2`.
12. Phase B1-D is the first Phase B code in the repository: `flutter_app/lib/core/live_contracts.dart`
    (420 lines), `flutter_app/lib/core/live_catalog_codec.dart` (507 lines),
    `flutter_app/test/live_contracts_test.dart` (93 lines) and the two frozen fixtures
    `Tests/fixtures/migration/catalog-v1.json` / `flutter-legacy-prefs.json`, which match the plan's
    Shared Fixtures block byte-for-byte. Hosted RED `46093489869` → hosted GREEN `46094276971` with all
    five cases green by name inside `133 tests passed, 1 skipped` (the skip is pre-existing and
    macOS-host-only). `Tests/fixtures/multi-source/*` remains unauthored because B2 owns it.

## Current task

- The remediation slice and the reviewer's hardening notes are both **closed with hosted evidence**:
  H1 = `4c80ad3`, H2 = `e1eb4db`, H3 = `5a9ad4a`, all green at `5a9ad4a` and again at `eb052b2`.
- Phase B has started: **Task B1-D** (Dart contracts, codec, five contract tests, two frozen migration
  fixtures) is implemented and hosted-verified at unit level, with its own RED (`46093489869`) and
  GREEN (`46094276971`) pair. Nothing outside `flutter_app/lib/core`, `flutter_app/test` and
  `Tests/fixtures/migration` was touched, so no Swift, JavaScript, UI or playback file is in scope yet.
- Active work is now the **scoped independent review of `1382a93..41039b2`** (the two workflow commits,
  the provenance fix, the first Phase B Dart code and the ledger appends). B1-S stays queued until that
  verdict lands, because B1-S and B1-J mirror the Dart contract shape and a defect found afterwards
  would be paid for three times.
- Nothing is held locally beyond this checkpoint edit: HEAD equals the remote head at `41039b2`.

## Remaining tasks (ordered, with the real gate for each)

1. ~~Independent re-review~~ — **closed**: ACCEPT WITH NOTES for `6fb03bf..cbc48ee`, notes N1–N5
   triaged into the work items below. The Android assertion commit `88bc7ea` and the evidence-gap
   slice `221ce95`/`9b55536`/`2a244aa` were folded into it, as this section previously required.
2. ~~Gate-hardening slice~~ — **closed with hosted evidence**: H1 added the runner-resolved
   `outputReleaseAppLinkSettings` path as an explicit candidate, narrowed the fallback glob to
   `*/merged_manifest/release/*`, made an ambiguous remainder `exit 1`, and asserts `$APP_ID` (read
   from the APK at `:179`, pinned at `:183`) inside both the merged manifest and the decoded shipped
   manifest; H2 asserts `android:required="false"` *and* pairs it with
   `android.hardware.touchscreen`; H3 canonicalizes both sides in `_resolve_within` and re-checks
   containment, proven by a committed symlink vector that runs on the runner (`Ran 14 tests`).
   Residual, stated precisely: H1 proves the selected manifest declares the APK's `applicationId`, not
   that those exact bytes were compiled into the APK. The RED halves of H1/H2 are **stated, not
   executed**, because no intentionally broken commit was pushed.
3. **Scoped re-review of `1382a93..41039b2`** — gate: an independent verdict on the changed Android
   gate, the provenance fix and the Dart contracts, with the pre-existing macOS-skip set and the
   `Live API verification` skip confirmed unchanged.
4. **Phase B1 continuation — B1-S (Swift), then B1-J (JavaScript), then B2 parsers/registries**, all
   sharing the frozen fixtures. `Tests/fixtures/multi-source/*` is still unauthored by design (B2 owns
   it); verified by search.
5. ~~Windows package byte-equality evidence gap~~ — **closed and hosted verified**: both Windows
   packages print `Legal files are SHA-256 byte-equal to the canonical repository copies
   (14 compared)` at run `46087990039`, and the installer job repeats it against
   `C:\Program Files\CCloud` at run `46094276974`.
6. ~~Provenance hash enforcement~~ — **closed and hosted verified**: `scripts/verify_provenance.py`
   recomputes every retained-text digest recorded in `SOURCES.md` offline as a blocking Quality step
   (`provenance: 10 retained files verified…`). Deliberately no network re-fetch comparison; that
   would make the gate depend on upstream availability.
7. ~~webOS dev-proxy unbounded read~~ — **closed and hosted verified**: `proxyFetch` now uses the
   same bounded byte-counting reader and the `response-too-large` policy code, covered by two new
   deterministic regressions (10/10 green in CI `46087990047` and again `46094276971`).
8. ~~Remaining security and packaging review~~ — **done**: the re-scan of `verify_provenance.py`, the
   Windows digest loop and `net.js` produced only N3 above (now fixed by H3), and the
   `bundle-msvc-runtime.ps1` question is answered **no** — its 14 outputs are always hash-compared by
   the paired assert script, so a separate digest list would only duplicate the set and risk drift.
9. **Phase C failover, Phase D/E/F subtitles, Phase G full matrix** — after B is hosted-green.
10. **Unified versioning decision + release manifest** — canonical `2.0.0+22` today; the release
    bump and manifest generation are not implemented.
11. **Docs synchronization** — `OVERNIGHT_RELEASE_EXECUTION_REPORT.md` at the end, per mission.

## Open blockers (production release)

- Android: no verified relinking material for statically linked FFmpeg inside `libmpv.so`.
- Windows: GPL/nonfree native-media posture plus incomplete build/source provenance.
- macOS: FFmpeg provenance is not pinned (hosted job uses unpinned `brew install ffmpeg`).
- webOS: no device installation/runtime acceptance.
- Signing/notarization: no verified `developer-id-notarized` macOS or `release-signed` Android
  evidence; all four platforms carry `INTERNAL-ONLY-*` labels and none has
  `production-approved`, and `RELEASE_PRODUCTION_READY` is not `true`.
- EPG: no licensed Iran-covering feed verified; the XMLTV mapping/no-data seam must stay explicit
  and no programme data may be invented.

None of these may be cleared by changing a label, a flag, or a document claim.

## Exact next action

1. ~~Land the gate-hardening slice~~ — **done**: `4c80ad3` (H1) + `e1eb4db` (H2) + `5a9ad4a` (H3), one
   concern per commit, hosted green at `5a9ad4a` (Quality `46093092478`, CI `46093092487`, Build
   `46093092524`) and green again at the head.
2. ~~Start Phase B1-D~~ — **done**: `4570277` (fixtures + failing tests, hosted RED
   `46093489869`) → `ea28b29` (contracts) → `eb052b2` (analyzer-clean, hosted GREEN `46094276971`
   inside a fully green Build `46094276974`).
3. **Get the scoped independent review of `1382a93..41039b2` back, then start B1-S** from
   `docs/superpowers/plans/2026-11-25-multi-source-subtitles.md` (Swift contracts against the same
   `Tests/fixtures/migration/catalog-v1.json`), with the plan's hosted RED before implementation and
   hosted GREEN after. Do not push while that review is in flight — two earlier verdicts came back
   partial exactly because the head moved underneath the reviewer.
4. Keep `EXECUTION_LOG.md` appends serialized, and re-check `git ls-remote` immediately before writing
   the tail: in this slice the engineer's `7124c28` landed while the project manager was composing an
   overlapping section, and the duplicate draft was discarded rather than committed.
5. Do not report or tag anything as release-ready: `INTERNAL-ONLY-*` labels, the absent
   `RELEASE_PRODUCTION_READY=true`, the four skipped macOS release steps and the skipped
   `Live API verification` all still close publication at `eb052b2`, and green CI is build-time
   evidence only.
6. Superseded instructions that used to be here: extend the review to `88bc7ea..2a244aa` (done); and
   the claim that promoting the discovered merged-manifest path into the explicit candidate list was
   the *wrong* framing. Landed H1 does both the path promotion **and** the narrowed fallback plus the
   `$APP_ID` identity token, which is strictly better than either alone — the earlier sentence was
   written before anyone knew the fourth candidate would be a legitimate explicit entry.

## How to resume after an interruption

- `cd /Users/roham/Documents/CCloudMac && git status --short && git log --oneline -8`
- `git ls-remote origin ci/github-first-foundation`
- `gh api "repos/iR0ham/CCloud/actions/runs?head_sha=<SHA>&per_page=10" --jq '.workflow_runs[] | "\(.id)|\(.name)|\(.status)|\(.conclusion // "-")"'`
  (use `.id`; `.databaseId` returns null on this API version)
- Job logs need `--allow-escape-sequences` plus ANSI stripping:
  `gh api repos/iR0ham/CCloud/actions/jobs/<job>/logs --allow-escape-sequences | sed -r 's/\x1b\[[0-9;]*[A-Za-z]//g'`
- Constraints that still apply: GitHub-hosted execution only; never weaken a quality, legal or
  distribution gate to obtain green; never invent legal documents, source archives, signing
  evidence, device acceptance, or EPG data; never force-push; never develop on `main`; keep
  `EXECUTION_LOG.md` append-only; serialize ledger appends because members share this checkout;
  replies to the owner are in Persian.
