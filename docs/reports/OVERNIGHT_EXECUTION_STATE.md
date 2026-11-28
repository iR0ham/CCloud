# CCloud Overnight Execution State (recovery checkpoint)

Append-oriented operational checkpoint. Rewrite the "current" sections when they change;
dated evidence below is a ledger and must not be restated as history that did not happen.

## Snapshot

- Repository: `/Users/roham/Documents/CCloudMac`, remote `iR0ham/CCloud` (public).
- Working branch: `ci/github-first-foundation`.
- HEAD and pushed remote branch head were both
  `41039b253da00005ba9083ce08833e7188bae32c` when the previous sentence was written; that was true at
  the time and is superseded here. As of this refresh local `HEAD` and `git ls-remote` both returned
  `fcd456c37de9ef8fdf50a2ec018e3794241f06d4` — so on resume, re-run `git ls-remote` rather than
  trusting any head written here.
- Commit order on the branch, continuing the previous list: `cbc48ee` (three-closed-gates ledger
  addendum) → `1382a93` (accepted re-review + hardening items) → `4c80ad3` (**H1** merged-manifest
  binding) → `e1eb4db` (**H2** optional-touchscreen assertion) → `5a9ad4a` (**H3** provenance path
  canonicalization) → `4570277` (B1-D fixtures + failing tests, hosted RED) → `ea28b29` (B1-D Dart
  contracts + codec) → `eb052b2` (analyzer-clean) → `7124c28` + `41039b2` + `597b4db` (ledger, plan
  and project-manager reconciliation) → `28019c8` (**canonical wire date form + symmetric
  schema-version gate**) → `fcd456c` (**element-scoped touchscreen assertion + H1 observability**).
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

### At `fcd456c` (scoped independent review of `1382a93..597b4db` and its two blocking notes)

**Verdict: ACCEPT WITH NOTES** for `1382a93..597b4db`. Provenance of the verdict, stated plainly: the
team's Code Reviewer member was unreachable — `team_delegate` returned
`COLLABORATION_MCP_TEAM_LEADER_REQUIRED` for two different member ids in this session shape — so the
review was commissioned as a **separate strictly read-only review by a local agent with no role in the
implementation**, which is the fallback the owner's directive authorizes. It is **not** a team-member
verdict and must not be cited as one. The reviewer confirmed no write, stage, stash, reset, clean,
commit or push, and no local execution workload of any kind.

What that review independently re-derived, rather than accepted from this report: the eight-file
numstat of `1382a93..eb052b2`; `require_token` **15 → 18** with no call site removed; `release.yml`,
`quality.yml`, `ci.yml`, `build-windows.yml`, `build-macos.yml` and `build-webos.yml` **byte-identical**
across the whole range (only `build-android.yml` changed), so `RELEASE_PRODUCTION_READY`, the macOS
signing/notarization skips and the `Live API verification` skip are unchanged in the strongest possible
sense; `1382a93` baseline Android job `140815355943` had **16** `ok:` lines and **no**
`android:required="false"` line, so the +4 delta is exactly H1(2)+H2(2); both fixtures
`cmp`-identical to the plan block including the trailing `0a` (`catalog-v1.json` 454 bytes,
`443a57bd…`; `flutter-legacy-prefs.json` 317 bytes, `c85168a5…`); B1-D declaration-for-declaration
faithful to the plan's `Interfaces produced` block with `LiveCatalogMigration.migrate/encode`
byte-identical to it; and `EXECUTION_LOG.md` append-only (`git log -p … | grep '^-[^-]'` empty).
It also found the Dart test at `4570277` RED is a valid historical gate because
`live_contracts.dart:3` imports the codec transitively.

Ten findings; the ones that changed state here:

| Note | Severity | Disposition |
| --- | --- | --- |
| Persisted timestamp **text form was never pinned**; Dart emits `.000Z`, the frozen fixture is seconds-precision, and the repo's existing Swift `.iso8601` strategy cannot parse Dart's output | **High** | **Closed by decision + test** in `28019c8`. Canonical form is RFC 3339 UTC with exactly three fractional digits; decoding accepts both forms; frozen with a committed `expect(... '2026-01-01T00:00:00.000Z')` plus a lenient-decode pair |
| `encode` accepted a schema version `decode` refuses, so it could write an unreadable document | Low | **Closed** in `28019c8`: `encode` now throws `FormatException('Unsupported live catalog schema')` (same prefix as `decode`) and writes the constant; new test `encode rejects a schema version the codec cannot decode` |
| The new whole-manifest `require_token "APK manifest" "$MANIFEST" 'android:required="false"'` is **provably non-binding** — four matches exist (`leanback`, `touchscreen`, `androidx.window.extensions`, `androidx.window.sidecar`) so `required="true"` passes | Medium | **Closed** in `fcd456c`: re-pointed at the element window, so the count stays **18** while binding power increases |
| H2 pairing was positional (`grep -A2`), fragile to an `apkanalyzer` reflow in both directions | Medium | **Closed** in `fcd456c`: window bounded by the element's own `/>` with `awk`, plus a hard failure when the window declares `android:required="true"`. The reviewer confirmed the `|| true` cannot mask a missing entry and that `set -euo pipefail` behaves correctly; only the *reason* in the old comment was wrong (no SIGPIPE exists in that statement) and it was rewritten |
| The log could not distinguish explicit-candidate selection from the narrowed fallback | Low | **Closed** in `fcd456c` by `merged manifest selected by:`; first run printed **`explicit candidate`** |
| `supportedSchemaVersion` is a public Dart symbol absent from the plan | Low | **Open → lands as a plan edit before B1-S** (recorded in the plan addendum) so the Swift/JS ports mirror a stated contract instead of inventing one |
| Non-recursive `Legal/licenses/` sweep; `documented.add(key)` runs before the containment rejection; `sha256_of` does not re-check containment itself; `_optDateText` null-aware rewrite | Low | Latent, not live (no symlink is tracked anywhere in the repo, `stage_legal.py` copies from a hardcoded tuple). Deferred to a hardening item, listed under Remaining tasks |
| `PENDING_WORK_COMPLETION_PLAN.md` §11.1 attributed the H3 `Ran 14 tests` / `OK` evidence to CI `46094276971`, which contains no such line | Medium | **Rejected after checking the document.** The committed H3 row (`:452`, added at `41039b2`) already cites Quality `46094277018`, which is where the provenance suite runs (`.github/workflows/quality.yml:131-133`); the only `46094276971` reference in that file is the correct B1-D GREEN row (`:453`). No correction was made. The other baseline-occurrence finding *was* confirmed, by re-fetching the logs: `provenance: 10 retained files verified…` really does appear at Quality job `140815355485:164` on `1382a93`, and `merged manifest artifact: …outputReleaseAppLinkSettings…` at Android job `140815355943:1943`, while both baseline logs contain **zero** `android:required="false"` lines |
| Two `EXECUTION_LOG.md` evidence rows quote lines that already existed at the baseline | Low | **Corrected by dated addendum**; the `Ran 14 tests` row is the one that evidences H3 |
| H2 falsifiability table predicted the wrong error for the `required="true"` mutation | Medium | **Corrected by dated addendum**; still **stated, not executed** |

| Head | Workflow | Run | Result and specific proof |
| --- | --- | --- | --- |
| `597b4db` | Quality | `46096515368` | **success** |
| `597b4db` | CI | `46096515292` | **success**; `macOS arm64 typecheck` `140828979218` printed only `typecheck OK (44 files)` — **no Swift test has ever run on a hosted runner**, which is what B1-S creates |
| `597b4db` | Build all platforms | `46096515354` | **success**, completed `2026-11-28T02:24:25Z` (still `in_progress` when the review reported it, so the review's own record of that row was correct at its timestamp) |
| `7124c28` | — | none | **NO RUNS EXIST**; it was pushed in a multi-commit push so only the tip triggered. A docs commit is not verified evidence and must not be described as verified |
| `28019c8` + `fcd456c` | Quality | `46098424061` | **success**; `Required NOTICE files` job `140835074353`: `Ran 14 tests in 0.009s` / `OK`, 9 steps / 0 skipped |
| `28019c8` + `fcd456c` | CI | `46098424212` | **success**; Flutter job `140835074852`: `No issues found! (ran in 14.6s)` and `🎉 134 tests passed, 1 skipped` — one more than the `597b4db` baseline's `133`, which is exactly the single added `test(...)`; both touched cases green by name (`v1 fixture round-trips and secret URLs are not serialized`, `encode rejects a schema version the codec cannot decode`); the one skip is still the pre-existing `platform_identity_test.dart` macOS-host case. `Live API verification` `140835076043` remains job-level `skipped` |
| `28019c8` + `fcd456c` | Build all platforms | `46098424038` | **success**, 8/8 jobs; Android job `140835074730` printed `applicationId=com.ccloud.ccloud versionName=2.0.0 versionCode=22`, `merged manifest selected by: explicit candidate`, `ok: merged manifest contains com.ccloud.ccloud`, `ok: APK manifest contains package="com.ccloud.ccloud"`, `ok: APK touchscreen element contains android:required="false"` and `ok: APK manifest pairs android.hardware.touchscreen with android:required="false"`, with **20** real `ok:` lines (baseline count unchanged), **0** `##[error]` and **23 steps / 0 skipped** |

Gate integrity across `597b4db..fcd456c`, counted by the project manager on the pushed diff: three
files, `+32/−19`, `+18/−5`, `+45/−0`; added lines matching
`continue-on-error|set +|.skip(|.only|todo(|if-no-files-found: warn` = **0**; `require_token` call
sites still **18**; no candidate path, no ambiguity `exit 1`, no artifact, no upload and no release
condition changed. The removed `grep -Fq` branch duplicates nothing: the same token against the same
window file is now asserted through `require_token`, which is the stricter and more diagnostic form.

### At `aab31be` (B1-S and B1-J landed to hosted RED) and the corrective slice on top

Per-commit hosted truth, taken from the runner APIs at this head rather than from earlier reports:

- `10a1986` — B1-S harness/fixtures, intended RED: CI `46101769870` **failure**, Quality `46101769917`
  success, Build `46101769890` success.
- `78830ca` — Swift port: CI `46103129293` **failure** (`macOS arm64 typecheck`), Build `46103129306`
  **failure** (`macos / macOS arm64 build`), Quality `46103129323` success. Both failures were the same
  compile errors in the new Swift files, seen from two jobs.
- `809964a`, `5922626` — **zero runs each** (`total_count: 0`): pushed inside a batch, and
  `cancel-in-progress` leaves only the tip's runs. Their content is carried by later tips; the commits
  themselves are unverified.
- `aef55e1` — B1-J suite before its port, intended RED: CI `46103926430` **failure** (webOS +
  `macOS arm64 typecheck`), Quality `46103926409` success, Build `46103926434` success.
- `aab31be` — webOS port: CI `46104459953` **failure**, Quality `46104460135` success, Build
  `46104460101` success. Failing jobs `140853973038` (step `Run webOS regressions`,
  `# tests 30 / # pass 18 / # fail 12`) and `140853973103` (step `Run Live TV foundation tests`, one Swift
  failure at `Tests/live-foundation/main.swift:913`). `Flutter analyze and tests` and
  `Version and canonical metadata` were green; `Live API verification` skipped.

Root causes, four distinct ones — one source defect and three test/harness defects:
`node:assert/strict` versus a `vm.runInNewContext` realm (10 failures), a single-argument
`assert.equal` (1), a calendar-rollover gap the module's own comment denied (1, the only source defect),
and Foundation escaping `/` as `\/` inside an encoded-text substring test (1 Swift). Escaping evidence is
in-repo at `Sources/Core/APIClient.swift:206`; the Dart overflow-acceptance evidence is the dart:core
`DateTime.parse` documentation, quoted in the plan addendum's item 11.

The corrective slice (11 assertions added, none removed or relaxed) is **implemented, NOT VERIFIED** — no
runner has executed it. Phase B still lacks a review by the team Code Reviewer: `team_delegate` refuses with
`COLLABORATION_MCP_TEAM_LEADER_REQUIRED`, so §3's fallback read-only review applies and is labelled as such.

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
13. **Read-only review of `1382a93..597b4db` returned ACCEPT WITH NOTES and its two blocking notes are
    closed on runners** at `fcd456c` (Quality `46098424061`, CI `46098424212`, Build `46098424038`).
    This item supersedes two earlier sentences in this section: item 11's "asserted as a value and as a
    feature pairing" described, at the time it was written, an assertion whose whole-manifest token was
    in fact non-binding (four `android:required="false"` matches exist), and the review's own count
    correction applies here too — `|| true` occurrences across `1382a93..eb052b2` are **3 → 3**, not
    "+1 added", because H1 removed the baseline's `… | head -1 || true` fallback at
    `1382a93:208`; that phrasing understated a strengthening. The canonical wire date form
    (RFC 3339 UTC, three fractional digits, both forms accepted on read), the symmetric
    schema-version gate with its shared `Unsupported live catalog schema` message, the element-scoped
    touchscreen window with its `required="true"` hard failure, and the
    `merged manifest selected by: explicit candidate` observability line are all hosted-verified as
    build-time evidence. Device and runtime behaviour remains **NOT VERIFIED**.

## Current task

- **Checkpoint 2026-11-28 (later): B1-S and B1-J are implemented but not yet hosted-green.** The ports
  landed across `10a1986` → `aab31be`; the last run at `aab31be` (CI `46104459953`) is red for four
  attributed causes, and the corrective slice that answers them is in the working tree at the time of this
  edit. Active work is therefore: push that slice as one focused commit, read the CI run at the new head, and
  mark B1-S/B1-J verified only on `live foundation OK` + the `assertions: <n>` line plus `# fail 0`. Task B2
  (parsers/registries and `Tests/fixtures/multi-source/*`) must not start before that, because B2 consumes the
  catalog interfaces these two tasks are supposed to prove. The bullets below are the state as of `fcd456c`
  and are kept for continuity, not corrected.
- The remediation slice and the reviewer's hardening notes are both **closed with hosted evidence**:
  H1 = `4c80ad3`, H2 = `e1eb4db`, H3 = `5a9ad4a`, all green at `5a9ad4a` and again at `eb052b2`.
- Phase B has started: **Task B1-D** (Dart contracts, codec, five contract tests, two frozen migration
  fixtures) is implemented and hosted-verified at unit level, with its own RED (`46093489869`) and
  GREEN (`46094276971`) pair. Nothing outside `flutter_app/lib/core`, `flutter_app/test` and
  `Tests/fixtures/migration` was touched, so no Swift, JavaScript, UI or playback file is in scope yet.
- Active work is now **Task B1-S** (Swift contracts + codec + the first hosted Swift test runner). The
  scoped independent review of `1382a93..597b4db` is **back** (ACCEPT WITH NOTES, and it explicitly
  answered "B1-S may start on top of the current Dart contracts"), and the two notes it required to
  land *before* B1-S — the canonical wire date form and the schema-version interface statements — are
  committed and green at `fcd456c`. Nothing is held locally beyond this checkpoint edit: local `HEAD`
  equals the remote head at `fcd456c`.
- Still true from the previous entry, unchanged: no Swift, JavaScript, UI or playback file has been
  modified by any of this work, and `Tests/fixtures/multi-source/*` remains unauthored because B2 owns
  it. `live_contracts.dart` and `live_catalog_codec.dart` have **no production consumer** — they are
  imported only by each other and by their test, so caller behaviour on a `FormatException` (must
  surface, must never clear the catalog) is still unproven and unowned by any test. That belongs to
  B4-S/B4-D, not B1.

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
3. ~~Scoped re-review of `1382a93..41039b2`~~ — **closed**: ACCEPT WITH NOTES over
   `1382a93..597b4db`, delivered by a local read-only reviewer because the team's Code Reviewer member
   was unreachable, and the macOS-skip set plus the `Live API verification` skip were confirmed
   unchanged by byte-identical workflow files across the range. Deferred residuals from its Low
   findings, which change no shipped behaviour and belong to a later hardening pass rather than to
   B1: make the `Legal/licenses/` documentation sweep recursive (`rglob`) so nested retained text
   cannot escape the "undocumented file" invariant; move `documented.add(key)` after the containment
   rejection in `verify_provenance.py:246` so one rejected entry cannot mask a second signal; state the
   containment contract at the interface so callers other than the current one cannot pass an
   uncanonicalized path to `sha256_of`; restore a direct symbol reference in the Dart test
   (`LiveCatalogStateCodec.supportedSchemaVersion`) so the importability guarantee B1-S/B1-J are
   specified against is proven, not inferred.
4. **Phase B1 continuation — B1-S (Swift) in flight, then B1-J (JavaScript), then B2
   parsers/registries**, all sharing the frozen fixtures. `Tests/fixtures/multi-source/*` is still
   unauthored by design (B2 owns it); verified by search. The binding interface decisions B1-S and
   B1-J must honour are recorded in the plan's dated addendum
   (`docs/superpowers/plans/2026-11-25-multi-source-subtitles.md`), because the plan's own text left
   five things unspecified: the Swift runner used a bare `swiftc` with no `-sdk`/`-target` while every
   hosted Swift compile in this repo pins both, no fixture-path anchor was named for a `mktemp -d`
   binary, nothing made the Swift step's assertions *countable* (so a `try?`-and-return on a missing
   fixture would be a silently passing step), the date strategy was unspecified between the repo's
   existing `.iso8601` and Dart's millisecond output, and B1-J's test location contradicted the repo's
   `Tests/webos/` convention.
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
3. ~~Get the scoped independent review back, then start B1-S~~ — the review landed (ACCEPT WITH
   NOTES, local read-only reviewer) and its two blocking notes are committed and green at `fcd456c`, so
   the review-in-flight push freeze is lifted. **Current exact next action: land Task B1-S** from
   `docs/superpowers/plans/2026-11-25-multi-source-subtitles.md` — Swift contracts and codec against
   the same frozen `Tests/fixtures/migration/catalog-v1.json`, `Tests/live-foundation/{main.swift,run.sh}`
   created from scratch, one added step in `ci.yml`'s `macos-typecheck` job — with the plan's hosted
   **RED before** implementation (that run is the first time any Swift test executes on a runner, so
   there is no prior baseline to compare against) and hosted **GREEN after**, on the same branch. B1-S
   must not touch a Dart, webOS or existing Swift app file, must not wire any consumer, and must not
   read or rewrite `UserDefaults`/Application Support: the migration trigger and disk I/O are B4-S.
   Then B1-J, then the item-3 deferred hardening.
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
7. **Current exact next action (supersedes the "land Task B1-S" sentence in item 3, which is done through
   implementation but not through green evidence):** commit the corrective slice in the working tree —
   `Sources/Core/LiveTVCatalogCodec.swift`, `Tests/live-foundation/main.swift`,
   `Tests/webos/live_contracts.test.js`, `webos_app/app/js/playlist_contracts.js` and the three ledger/plan
   documents — as one focused commit, push once (item 3's `cancel-in-progress` lesson), then read the CI run
   at that head for `live foundation OK` and `# fail 0` and record the numbers here. Only after that: B2,
   then the deferred provenance/test hardening residuals, then B3 cross-port agreement — where the Dart
   `DateTime.parse` leniency documented in plan item 11 is closed against the same frozen fixture.
8. **Item 7's gate is satisfied; this supersedes it.** The head `4c98e97` is hosted green: CI `46106921574`
   all jobs `success`, webOS job `140861641671` prints `# tests 30 / # pass 30 / # fail 0`, macOS job
   `140861641921` retains `typecheck OK (46 files)` + `assertions: 227 (floor 150)` + `live foundation OK`,
   Flutter job `140861641881` prints `No issues found!` and `🎉 135 tests passed, 1 skipped.`, Quality
   `46106921571` passes six jobs including `Ran 15 tests … OK` / `10 retained files verified` in the
   Required NOTICE files job. **B1-J is therefore hosted-verified as a contract** (first time the module's
   assertions ever executed on a runner) and the provenance hardening slice is hosted-verified. Device and OS
   acceptance remain NOT VERIFIED, so nothing about release protection changed. **Current exact next action:
   Task B2-D** — the Dart M3U parser, `stableKeyHash` and source registry over
   `Tests/fixtures/multi-source/*.m3u*`, following the corrected task map in
   `docs/reports/PENDING_WORK_COMPLETION_PLAN.md` §13; B2 must not carry the Dart date-reading tightening,
   which belongs to B3.

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
