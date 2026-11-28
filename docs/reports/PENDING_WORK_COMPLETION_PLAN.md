# CCloud Pending Work Completion Plan

**Date:** 2026-11-28  
**Branch:** `ci/github-first-foundation`  
**Committed baseline:** `3d6e8762ce8826a52297f83b5f6952a26f15ba44`  
**Remote branch head:** `3d6e8762ce8826a52297f83b5f6952a26f15ba44`  
**Uncommitted remediation:** 16 modified tracked files and the legal, test, script, and documentation paths shown by `git status`  
**Execution rule:** project builds, tests, analysis, packaging, signing, installation checks, and release jobs run only on GitHub-hosted runners. Local runtime is **NOT VERIFIED**.

## 1. Current repository and GitHub state

| Area | Verified state | Classification |
|---|---|---|
| `main` | `6dfd925095b0090b623443f396388fd4d552db63` | Not modified by this continuation |
| Development branch | `ci/github-first-foundation` tracks the same remote head | Clean synchronization at committed baseline |
| Unpushed local commits | None | Remediation is still uncommitted |
| Open pull requests | None | No review gate or merge path is active |
| Release tags | No canonical `2.0.0` / build 22 release tag | Production release not prepared |
| GitHub Releases | Historical Windows and mixed-platform releases exist | Not evidence for the current canonical branch |
| Latest CI at `3d6e876` | Run `45469044683`: success | Hosted CI passed at the committed baseline |
| Latest Quality at `3d6e876` | Run `45469044590`: failure due missing root NOTICE files | Fix exists only in the uncommitted worktree |
| Latest Build Platforms at `3d6e876` | Run `45469044568`: failure | Android assertion and Windows compatibility job failures remain hosted-unverified fixes |

## 2. Master pending-work inventory

### P0 — Complete the already-started legal and packaging slice

| Field | Finding |
|---|---|
| Original milestone | Legal, attribution, distribution-control, and cross-platform packaging |
| Files | `NOTICE`, `THIRD_PARTY_NOTICES.md`, `SOURCES.md`, `Legal/`, `scripts/stage_legal.py`, `Tests/test_stage_legal.py`, `build.sh`, `scripts/make_dist.sh`, `scripts/bundle-msvc-runtime.ps1`, `scripts/assert-windows-package.ps1`, `scripts/windows-installer-smoke.ps1`, and the four platform workflow files |
| Already completed | Canonical legal sources, license inventory, symlink-safe staging, nested Android/Flutter/webOS package layout, package assertions, macOS ZIP byte checks, internal-only labels, and Quality test wiring |
| Remaining work | Independent re-review of the remediated diff, logical commit, push, and hosted Quality plus platform-build execution |
| Tests | Six tests exist in `Tests/test_stage_legal.py` and are wired to Quality |
| Verification | Not executed locally or hosted after the fix |
| Priority | P0 |
| Acceptance | Quality passes with all canonical files; each package contains the exact expected legal paths and byte contents; no path outside the checkout or symlink target is deleted |
| Classification | IMPLEMENTED — NOT TESTED |

### P0 — webOS transport remediation and regressions

| Field | Finding |
|---|---|
| Original milestone | Security review of bounded fetch, redirect cleanup, and Luna fallback behavior |
| Files | `webos_app/service/com.ccloud.tv.service/ccloud_service.js`, `webos_app/app/js/net.js`, `Tests/webos/transport.test.js`, `.github/workflows/ci.yml` |
| Already completed | Stable `response-too-large` code; direct fallback suppression for that policy error; bounded streamed reads; exact byte accounting; redirect response/request destruction; eight deterministic tests |
| Remaining work | Hosted Node execution, review of test assertions, and a real webOS device check for Luna behavior where feasible |
| Tests covered | Content-Length oversize, unknown-length/chunked oversize, exact 8 MiB acceptance, 8 MiB + 1 rejection, UTF-8 multibyte counting, cancellation, one-shot response, and redirect cleanup |
| Verification | **NOT VERIFIED**; local test execution is prohibited |
| Priority | P0 |
| Acceptance | Hosted CI runs all eight tests green; no unbounded `text()` fallback; no duplicate response after late event; redirect sockets are destroyed |
| Classification | IMPLEMENTED — NOT TESTED |

### P0 — Android package assertion fix

| Field | Finding |
|---|---|
| Original milestone | Android release packaging and artifact upload |
| File | `.github/workflows/build-android.yml:215-217` |
| Root cause class | `unzip -l | grep -Fq` can terminate the pipeline early under `pipefail` |
| Already completed | AAB listing is written to `$RUNNER_TEMP/aab-list.txt` and checked without a pipeline |
| Remaining work | Hosted Android rerun after pushing the remediation slice |
| Verification | **NOT VERIFIED** at the new commit |
| Priority | P0 |
| Acceptance | APK and AAB assertions pass and both artifacts upload |
| Classification | IMPLEMENTED — NOT TESTED |

### P0 — Windows staging and compatibility rerun

| Field | Finding |
|---|---|
| Original milestone | Windows release packaging, legal staging, and Skia/Impeller compatibility |
| Files | `.github/workflows/build-windows.yml`, `scripts/bundle-msvc-runtime.ps1`, package assertion scripts |
| Already completed | Both staging commands now resolve inside the checkout; canonical legal files are copied into staged packages |
| Prior hosted failure | Compatibility/Skia runner lost communication while its build was in progress |
| Remaining work | Rerun both Windows configurations and distinguish a runner failure from an application failure |
| Verification | Release staging and compatibility behavior are **NOT VERIFIED** after remediation |
| Priority | P0 for CI, P1 for device/runtime acceptance |
| Acceptance | Both Windows jobs complete, packages install/start, checksums verify, and legal assertions pass |
| Classification | IMPLEMENTED — NOT TESTED |

### P0 — Release and distribution gates

| Field | Finding |
|---|---|
| Original milestone | Production release gating |
| Files | `.github/workflows/release.yml`, `Legal/DISTRIBUTION_STATUS.md`, artifact labels |
| Already completed | Publication requires the exact production variable, expected signing per platform, and exact `production-approved` distribution labels for all platforms |
| Current labels | macOS: internal-only pending source material; Android: internal-only blocked relinking; Windows: internal-only blocked GPL/nonfree; webOS: internal-only pending device acceptance |
| Remaining work | Preserve gates and complete the independent native-media licensing/provenance work |
| Priority | P0 for release only; no production gate may be weakened |
| Acceptance | Release occurs only when all gates pass on evidence |
| Classification | PUSHED — NOT VERIFIED for current baseline; production publication BLOCKED |

### P0 — Commit and push the already-started remediation slice

| Field | Finding |
|---|---|
| Current state | Remediation is in the worktree, not committed or pushed |
| Required work | Append a dated `EXECUTION_LOG.md` entry, create focused commits for legal packaging, webOS transport, Android/Windows CI, canonical documentation, and pending-work tracking; push only to `ci/github-first-foundation` |
| Guardrails | Do not alter `main`, force-push, rewrite history, or include secrets/generated package copies |
| Acceptance | Clean worktree, remote branch advanced, exact new SHA recorded |
| Priority | P0 — first action after inventory approval |
| Classification | REVIEWED — NOT COMMITTED |

### P1 — Hosted verification of the remediation slice

| Field | Finding |
|---|---|
| Required workflows | CI, Quality, Build all platforms |
| Evidence required | `headSha`, job conclusions, test counts, artifact hashes, signing and distribution labels, package legal contents, Android APK/AAB upload, Windows portable/installer results, webOS IPK results, macOS ZIP result |
| Acceptance | No failure is ignored; environment failure must be retried or explicitly reported; source failure requires a new remediation cycle |
| Priority | P0 |
| Classification | NOT STARTED — depends on commit/push |

### P1 — Independent review of remediated diff and evidence

| Field | Finding |
|---|---|
| Prior review | The reviewer reported five findings: Windows path, webOS cap bypass, macOS symlink deletion, Android/webOS legal layout, and redirect socket cleanup |
| Current state | Source remediation is present and tests were expanded, but the exact remediated diff has not had a fresh independent re-review |
| Acceptance | Reviewer confirms the original findings are resolved, no new defect is introduced, and the hosted evidence is correctly interpreted |
| Priority | P0 before Phase B |
| Classification | TESTED — NOT REVIEWED (after hosted evidence is obtained) |

### P2 — Phase B1 Multi-Source contracts and migration

| Field | Finding |
|---|---|
| Files | Dart `flutter_app/lib/core/live_contracts.dart`, `live_catalog_codec.dart`, and matching tests; Swift `Sources/Core/LiveTVContracts.swift`, `LiveTVCatalogCodec.swift`; webOS `webos_app/app/js/playlist_contracts.js`; shared migration fixtures |
| Current state | Target contract files are absent |
| Required behavior | schema-v1 round-trip, deterministic defaults, secret-ref URL omission, corrupt/future-state rejection, legacy preservation |
| Tests | Test-first hosted RED then GREEN for each platform |
| Priority | P1 after remediation slice is verified |
| Classification | NOT STARTED |

### P2 — Phase B2 parser, identity hash, and source registry

| Field | Finding |
|---|---|
| Files | `playlist_parser`, `source_registry`, `identity_hash`, shared fixtures, and equivalent Dart/Swift/JavaScript files |
| Current state | Target files are absent |
| Required behavior | M3U classification, bounded parsing, metadata extraction, duplicate handling, sensitive URL classification, stable IDs |
| Cross-language acceptance | Same fixtures produce the same classification, identity, and issue semantics in Dart, Swift, and JavaScript |
| Priority | P1 after B1 |
| Classification | NOT STARTED |

### P2 — Phase B3 unified logical catalog

| Field | Finding |
|---|---|
| Files | `channel_identity`, `unified_catalog`, built-in adapter, tests |
| Required behavior | stable logical identity, explicit association only, candidate matching, no automatic merge, preserved built-in Iran catalog behavior |
| Priority | P1 |
| Classification | NOT STARTED |

### P2 — Phase B4 repository and playlist management

| Field | Finding |
|---|---|
| Files | per-platform repositories, secret adapters, state stores, playlist manager UI/screens |
| Required behavior | add/rename/enable/disable/remove/refresh playlists, persistent state, migration, status, counts, errors, bounded refresh |
| Dependency gate | Flutter `file_picker` and `flutter_secure_storage` may be added only after license and behavior review |
| Priority | P1 |
| Classification | NOT STARTED |

### P2 — Phase C controlled failover and source diagnostics

| Field | Finding |
|---|---|
| Required behavior | priority, retry caps, backoff, cooldown, cancellation, source health, no URL-only probing, per-channel recovery serialization |
| Platform integration | extend existing Swift `PlaybackController`, Flutter `player_screen.dart`, and webOS player rather than creating another player |
| Priority | P1 |
| Classification | NOT STARTED |

### P2 — Phases D/E/F subtitles

| Field | Finding |
|---|---|
| D | subtitle contracts, parsers, renderer adapters |
| E | authorized-root discovery and native picker integration |
| F | persisted preferences, styling, timing offset, RTL/mixed-text proof |
| Hard rule | every format/platform capability claim requires actual renderer or device evidence |
| Priority | P1, sequential after B/C |
| Classification | NOT STARTED |

### P2 — Phase G verification and release documentation

| Field | Finding |
|---|---|
| Required outputs | compatibility matrix, commit-scoped verification report, final implementation report, release notes, manifest, checksums |
| Required device evidence | Android phone/TV, webOS TV, macOS UI, Windows media playback |
| Current state | No Multi-Source/Subtitle runtime acceptance evidence exists |
| Priority | P0 before release |
| Classification | NOT STARTED |

## 3. Remaining release blockers

| Blocker | Current evidence | Consequence |
|---|---|---|
| macOS FFmpeg release provenance and corresponding source | Internal-only label; canonical provenance incomplete | Cannot mark macOS production-ready |
| Android relinking materials | Internal-only label | Cannot mark Android production-ready |
| Windows native media GPL/nonfree configuration | Internal-only label | Cannot mark Windows production-ready |
| webOS device acceptance | No TV install/remote/subtitle evidence | Cannot mark webOS production-ready |
| macOS Developer ID and notarization | Only ad-hoc signing observed | Cannot publish a trusted macOS release |
| Android release signing | Only internal debug signing observed | Cannot publish a trusted Android release |
| `RELEASE_PRODUCTION_READY` | Absent | Release workflow remains intentionally blocked |
| Production signing secrets | Not configured/authorized | Release remains blocked |

These blockers must not be bypassed or relabeled without new evidence and explicit owner authority.

## 4. Dependency graph and execution sequence

```text
Inventory reconciliation
        ↓
Finish already-started legal/webOS/CI remediation
        ↓
Append execution-log evidence → logical commits → push development branch
        ↓
Hosted CI + Quality + Build Platforms
        ↓
Fix genuine hosted failures → re-verify
        ↓
Independent re-review of exact SHA and evidence
        ↓
B1 contracts/migration (Dart → Swift → JavaScript)
        ↓
B2 parser/identity/source registry
        ↓
B3 unified catalog
        ↓
B4 repositories/playlist management
        ↓
C failover and source diagnostics
        ↓
D/E/F subtitle system
        ↓
G cross-platform verification and final documentation
        ↓
Unified version/build decision and release manifest
        ↓
Production gates
```

Parallelism is safe only after shared fixtures and contracts are frozen:

- B1-D must precede B1-S and B1-J because it establishes shared schema fixtures.
- B2-D must precede B2-S and B2-J because it establishes shared playlist fixtures.
- B3 platform tasks may run after B2 is complete.
- B4 platform tasks may run after B3 is complete, but platform files must have one owner.
- Legal review, security review, and UI research can overlap with later implementation only when they do not edit the same files.

## 5. Immediate acceptance checklist

- [ ] Pending-work inventory is written to this file and reconciled against repository/GitHub state.
- [ ] `EXECUTION_LOG.md` records the remediation and hosted verification results as dated entries.
- [ ] The remediation slice is committed logically and pushed only to `ci/github-first-foundation`.
- [ ] CI, Quality, and Build Platforms run against the exact accepted SHA.
- [ ] All five original review findings are confirmed fixed by re-review and hosted evidence.
- [ ] Android APK/AAB upload and both Windows package configurations pass.
- [ ] Eight webOS transport tests pass on a hosted runner.
- [ ] B1/B2 target files exist and pass shared-fixture hosted tests in Dart, Swift, and JavaScript.
- [ ] Multi-Source and subtitle runtime features have real hosted/device evidence before being marked supported.
- [ ] Canonical version/build identity and release manifest agree for every artifact.
- [ ] No legal or distribution gate is relaxed to obtain a green run.

## 6. Conclusion

The immediate critical path is **not new feature work**. The Team must first finish the remediation slice that is already implemented but not committed or hosted-verified, then obtain an independent re-review. Only after that evidence is available may Phase B implementation begin.

The final release outcome is currently **DEVELOPMENT BUILDS PARTIALLY VERIFIED — REMEDIATION NOT COMMITTED — RELEASE BLOCKED**, based on the `3d6e876` hosted ledger. The next task is to convert the remediated worktree into a hosted-verified commit.

---

## 7. Dated correction — 2026-11-28 (after the hosted run at `7b2db7b`)

This section supersedes nothing above it; the snapshot in sections 1-6 described the
worktree before the remediation slice was committed and is retained as history.

### 7.1 Classification corrections

| Item | Section 1-6 state | Actual state after `7b2db7b` |
| --- | --- | --- |
| Legal packaging slice | REVIEWED — NOT COMMITTED | **PUSHED — HOSTED VERIFIED (Quality success)** |
| Android pipefail-safe AAB read | expected to clear the Android gate | committed, but **not the cause** of the Android failure; failure is earlier |
| Windows builds | BLOCKED (runner comms loss at `3d6e876`) | **hosted success** at `7b2db7b` (analyze, release build, runtime smoke, installer install/startup smoke) |
| webOS transport tests | TESTED — NOT REVIEWED | **REVIEWED — REJECTED**: 3 of 8 tests fail on the Node 20 pinned runner because the injected `url` mock hides the legacy module API the service uses |
| Phase A/B audit documents | not committed | committed in `7b2db7b` |

Section 1-6 listed the inventory before any of it was committed; the commit/push task is now
done, and the remaining critical path is the two defects below.

### 7.2 New inventory items

| # | Task | State | Files | Remains | Priority | Acceptance |
| --- | --- | --- | --- | --- | --- | --- |
| N1 | webOS test-harness `url` mock | IN PROGRESS (diagnosed, fix specified) | `Tests/webos/transport.test.js:9,42` | inject the whole `node:url` module and add a guard so a missing legacy `parse`/`resolve` fails loudly | P0 | 8/8 tests green in the hosted `webOS static` job at the new SHA |
| N2 | Android APK-manifest assertion is undebuggable | IN PROGRESS | `.github/workflows/build-android.yml:158-244` | check `apkanalyzer manifest print` status, label every token assertion, dump manifest/badging on failure; keep every token mandatory | P0 | either green, or one `::error::` naming the exact missing token |
| N3 | mpv digest mislabel | **RESOLVED in worktree** (pending hosted + review) | `SOURCES.md:101-118`, `THIRD_PARTY_NOTICES.md:58-72` | hosted Quality must re-confirm the staged bytes | P1 | documents distinguish git SHA-1, MD5 download check and pub.dev SHA-256 |
| N4 | Ledger integrity | RESOLVED in worktree | `EXECUTION_LOG.md` | none | P1 | dated addenda only; prior entries untouched apart from the explicit correction wording |

### 7.3 Consequence for sequencing

Phase B still may not start until N1 and N2 have hosted evidence at one SHA and the
Code Reviewer re-approves that head. The dependency graph in section 4 is unchanged; only
the P0 completion states moved.

## 8. Dated update — 2026-11-28 (hosted ledger at `6fb03bf`)

Section 7 stays as written; this section records what its items became.

### 8.1 Item outcomes

| # | Then | Now | Evidence |
| --- | --- | --- | --- |
| N1 | IN PROGRESS | **HOSTED VERIFIED** | CI `46085379959` success at `6fb03bf`; `webOS static JS/JSON/service validation` ran all eight transport regressions green on the pinned Node `20` runner |
| N2 | IN PROGRESS | **DIAGNOSED AND FIXED IN WORKTREE — NOT YET HOSTED VERIFIED** | Build Platforms `46085379924` / Android job `140793625386` step 15 reported `::error::APK manifest is missing the expected token: @drawable/tv_banner`, i.e. exactly one attributable condition instead of a silent abort |
| N3 | RESOLVED in worktree | **HOSTED VERIFIED (documents)** | Quality `46085379874` success: Required NOTICE files, Repository hygiene and Version consistency green after the rewording |
| N4 | RESOLVED in worktree | **HOLDS** | `EXECUTION_LOG.md` gained only dated addenda, including the retraction of the earlier SIGPIPE theory |

### 8.2 What N2 actually was

The Android manifest block never passed since it was introduced because it asserted **source
literals** against `apkanalyzer manifest print` output, which decodes binary resources and renders
references and flag enumerations opaquely (`@ref/0x7f070077`, `launchMode="1"`,
`configChanges="0x40003fb4"`, `windowSoftInputMode="0x10"`). The app manifest was correct; the
assertion target was wrong. The corrected step asserts the literals against the merged release
manifest that aapt2 compiles into the APK, keeps presence checks on the decoded shipped manifest,
and makes the orientation-lock prohibition enforceable in both artifacts. No token was dropped, no
gate was relaxed, and a missing merged-manifest artifact fails the job rather than skipping checks.

### 8.3 Consequence for sequencing

Phase B may start once this Android fix is green on a runner and the pending independent re-review
is integrated; the review was requested for `7b2db7b..6fb03bf` and must be extended to the Android
assertion commit. The section 4 dependency graph is otherwise unchanged. Platform acceptance still
lacks device/runtime evidence for Android phone/TV, Windows, macOS and webOS, and the four
distribution labels stay `INTERNAL-ONLY-*`; production release remains blocked by the native-media
provenance, relinking, signing/notarization and device-acceptance items in section 6.

## 9. Dated update — 2026-11-28 (hosted ledger at `2a244aa`, three evidence gaps closed)

Sections 7 and 8 stay as written. The Full-stack Engineer slice that ran after section 8 took the three
items still open in `docs/reports/OVERNIGHT_EXECUTION_STATE.md` (Windows legal byte-equality, provenance
digest enforcement, `proxyFetch` read bound) and moved all three to hosted-verified.

### 9.1 Item outcomes

| # | Gap | Now | Commits | Hosted evidence |
| --- | --- | --- | --- | --- |
| G1 | Windows package asserted legal-file existence only | **HOSTED VERIFIED** | `221ce95` | `Build all platforms` `46087990039` success; `…(14 compared)` byte-equality line printed for the portable dir, the installed `C:\Program Files\CCloud` tree and the Skia compat package |
| G2 | `SOURCES.md` digests were claims nothing recomputed | **HOSTED VERIFIED** | `9b55536` | Quality `46087990020` success; `provenance: 10 retained files verified against SOURCES.md (offline, recomputed SHA-256, no network fetch)` plus `Ran 13 tests … OK` in `Required NOTICE files` `140801997670` |
| G3 | localhost dev proxy ended in an unbounded `response.text()` | **HOSTED VERIFIED** | `2a244aa` | CI `46087990047` success; `webOS static` `140801998020` ran `# tests 10 / # pass 10 / # fail 0` on Node `20`, the two dev-proxy regressions included |

The same run kept every earlier gate intact: nothing was made optional, no `continue-on-error` or
`|| true` was introduced, `build-android.yml` was not touched, and the Android job (`140802338051`) is
green at this head — so section 8's N2 is now hosted-verified on a re-based head rather than only on
`8a1ef3f`.

### 9.2 Why G1 + G2 together matter more than each alone

Packaging asserts "shipped file == repository file" (Android archive bytes, webOS and macOS `cmp`, now
Windows SHA-256), while the provenance gate asserts "repository file == the digest `SOURCES.md`
documents". Composed, that makes the documented digests transitively true for the shipped legal texts on
all four platforms. Before this slice Windows broke the chain at the first link and all four platforms
broke it at the second, because no machine ever recomputed a digest.

### 9.3 What did not change

- Falsifiability is documented rather than executed: the exact controlled mutation for each of the five
  new assertion classes is recorded in the `## 2026-11-28 (CI evidence gaps)` section of
  `EXECUTION_LOG.md`. `Tests/test_verify_provenance.py` does run fixture-tree mutations on the runner,
  which is the only red/green evidence the GitHub-only mandate permits.
- Section 3 production blockers are untouched: native-media provenance and redistribution, Android
  relinking materials, corresponding-source offers, Windows GPL build configuration, Developer ID
  signing/notarization, and every real-device acceptance item. `Legal/DISTRIBUTION_STATUS.md` still reads
  `INTERNAL-ONLY-*` for all four platforms, and the canonical identity is still `2.0.0` / build `22`.
- No Phase B multi-source or subtitle contract work was started.

### 9.4 Consequence for sequencing

The CI-side evidence inventory is closed. Each of the four rows that section 2 classified
"IMPLEMENTED — NOT TESTED" is now hosted-verified at `2a244aa`: legal packaging (Quality `46087990020`,
including the new provenance recomputation), webOS transport (CI `46087990047`, `# pass 10`), the Android
manifest assertion (job `140802338051` success), and the Windows staging plus Skia compatibility rerun
(jobs `140802337977` and `140803894634` success, both printing the 14-file byte-equality line). The
section 2 tables stay exactly as written; this section supersedes their classification under the
append-only rule.

The next real gate is not more automation: it is the scoped code re-review of `8a1ef3f..2a244aa` (the
previous request stopped at `6fb03bf`) and, beyond that, owner-supplied device acceptance plus the
legal/signing decisions in section 3. Phase B may be planned against a stable foundation once that review
lands; it should not wait on further CI plumbing, because further CI would now only add checks for
evidence classes that already exist.

## 10. Dated update — 2026-11-28 (independent review accepted; hardening items added)

Sections 1–9 above are the historical snapshot and are not restated as current truth. This section
records what changed after the `2a244aa` ledger, at head `cbc48ee`.

### 10.1 Inventory outcome

| Item | Previous state | Now | Evidence |
| --- | --- | --- | --- |
| Independent review (`#9`) | outstanding, last verdict REJECT at `6fb03bf` | **ACCEPT WITH NOTES** for `6fb03bf..cbc48ee` | reviewer re-derived the four prior blockers as closed from runner logs and committed blobs, not from this plan's wording |
| Hosted evidence claims for the three closed gates | asserted by the implementing member | **independently VERIFIED** | Test Engineer re-downloaded the logs for runs `46087125808`, `46087990039`, `46087990020`, `46087990047`, `46089580613`, `46089580608`, `46089580637`; nothing refuted |
| `cbc48ee` (docs-only) hosted status | Build still running | **green** — Quality `46089580613`, CI `46089580608`, Build `46089580637` 8/8 jobs | Android job `140807097206`; second independent pass of the manifest gate |
| `bundle-msvc-runtime.ps1` digest question | open decision | **closed, answer no** | its 14 staged outputs are hash-compared by the paired assert script in every Windows job, so a second digest list duplicates and can drift |
| Security re-scan of the new scripts | open | **done, one residual fix (N3)** | path containment is lexical only in `scripts/verify_provenance.py:190-195` |
| Phase B1 readiness | blocked on review | **unblocked** | reviewer: no confirmed defect in the range prevents B1; only non-blocking prerequisites listed below |

### 10.2 New work items created by the review (each with its real gate)

- **H1 — bind the merged manifest to the APK under test** (`N1`, Low/Medium). Gate: a hosted run where
  narrowing the fallback and asserting an identity token still passes, plus a stated mutation showing
  the assertion can go RED when the wrong manifest is selected. Without it the four literal contracts
  rest on a first-match `find` over `build/app/intermediates`.
- **H2 — assert `android:required="false"` instead of only describing it** (`N2`, Low). Gate: hosted
  pass with the token added; the decoded rendering is already proven faithful by the `6fb03bf` dump.
- **H3 — canonicalize path resolution in the provenance checker** (`N3`, Low). Gate: a new
  `Tests/test_verify_provenance.py` vector using a committed symlink that escapes the checkout, RED
  first on a runner, then GREEN after the fix.
- H1–H3 are one focused slice, one logical commit per concern, and must not be split across Android
  build cycles.
- **Not work items:** `N4` (checkpoint staleness) is closed by this commit's checkpoint update; `N5`
  is a reporting constraint — internal consistency must never be reported as upstream authenticity.

### 10.3 Sequencing consequence

The remediation-and-evidence arc is finished. The critical path is now: H1–H3 hardening slice →
Phase B1-D (Dart contracts + frozen shared fixtures) → B1-S → B1-J → B2 cross-language agreement.
Device/runtime acceptance, native-media relinking, corresponding-source material, and signing or
notarization remain owner-side blockers and are unchanged by any of the green CI evidence above.

## 11. Dated update — 2026-11-28 (hardening slice closed, Phase B1-D landed)

Section 10.2 listed H1, H2 and H3 as the gate-hardening slice that had to precede Phase B1. All three
are landed and hosted green, and Task B1-D of
`docs/superpowers/plans/2026-11-25-multi-source-subtitles.md` is landed behind them with a real RED run
and a real GREEN run. The commits are `4c80ad3` (H1), `e1eb4db` (H2), `5a9ad4a` (H3), `4570277` (B1-D
fixtures and failing test), `ea28b29` (B1-D contracts and codec) and `eb052b2` (B1-D analyzer cleanup,
the branch head). `EXECUTION_LOG.md` carries the runner-line detail; this section only moves the
inventory.

### 11.1 Item outcomes

| Item | Previous state | Now | Evidence |
| --- | --- | --- | --- |
| H1 (`N1`) | fallback picked the first `*release*` manifest in sort order | **closed** | the discovered path is now an explicit candidate, the glob is narrowed to `*/merged_manifest/release/*`, more than one remainder is a hard failure, and `$APP_ID` from the APK is asserted in both artifacts — run `46093092524`, job `140818355917`, line `merged manifest artifact: build/app/intermediates/merged_manifest/release/outputReleaseAppLinkSettings/AndroidManifest.xml` |
| H2 (`N2`) | comment claimed the optional-touchscreen contract, code checked the feature name | **closed** | `ok: APK manifest contains android:required="false"` and `ok: APK manifest pairs android.hardware.touchscreen with android:required="false"` in the same job |
| H3 (`N3`) | containment was lexical, so a committed symlink could leave the checkout | **closed** | `_resolve_within` canonicalizes both sides and re-checks containment; `Tests/test_verify_provenance.py` grew the escaping-symlink vector, `Ran 14 tests` / `OK` in run `46094277018` |
| Phase B1-D | next item on the critical path | **closed for Dart** | RED `46093489869` (`uri_does_not_exist` for both new libraries) then GREEN `46094276971` (`No issues found!`, `🎉 133 tests passed, 1 skipped.`) |
| Shared fixtures for B1-S / B1-J | not present | **present** | `Tests/fixtures/migration/catalog-v1.json`, `Tests/fixtures/migration/flutter-legacy-prefs.json`, both byte-identical to the plan's Shared Fixtures block |
| Gate integrity | fifteen `require_token` call sites at `1382a93` | **eighteen**, none deleted | three added at `build-android.yml:273`, `:274` and `:288` (merged-manifest identity, shipped-package identity, `android:required="false"`), plus the touchscreen pairing check that is not a `require_token` |

### 11.2 What did not change

`Legal/DISTRIBUTION_STATUS.md`, the four `INTERNAL-ONLY-*` labels, `RELEASE_PRODUCTION_READY`, and the
canonical identity `2.0.0` / build `22` are untouched. No assertion was downgraded, no step gained
`continue-on-error`, and no `skip`/`todo` was introduced; the only `continue-on-error: true` in the
repository is still the pre-existing Inno Setup artifact step at `.github/workflows/build-windows.yml:167`.
`main` is still `6dfd925…`, no tag was created, and nothing was published or released. `Tests/fixtures/`
gained only the two migration fixtures named in the plan — `Tests/fixtures/multi-source/*` belongs to B2
and was not authored here.

### 11.3 Deliberate non-work

No Swift (B1-S) and no JavaScript (B1-J) file was touched, so the three-platform parity claim is still
unproven and can only be made after B2. No dependency was added: `file_picker` and `flutter_secure_storage`
stay behind the B4 gate, which means `streamSecretRef` has a persisted shape but no verified store behind it
on any platform. No UI, no version bump, no release action, no local build or test run.

### 11.4 Falsifiability status

The B1-D RED is executed evidence. The H1, H2 and H3 mutation regressions are stated with their exact
expected `::error::` text in `EXECUTION_LOG.md` and are **NOT EXECUTED**, by instruction not to push a
deliberately broken commit; the passing assertions themselves are runner-quoted, so the gate is proven
to run even where the RED half is only specified.

### 11.5 Consequence for sequencing

The critical path is now B1-S (Swift mirror) → B1-J (webOS JavaScript mirror) → B2 (cross-language
agreement fixtures over the same `Tests/fixtures/migration/catalog-v1.json`). Device and runtime
acceptance, native-media relinking, corresponding-source material, signing/notarization and any EPG
programme data remain owner-side blockers, and no green runner in this range changes that.

## 12. Dated update — 2026-11-28 (B1-S and B1-J implemented; hosted GREEN still open)

Section 11's sequencing was followed: `10a1986` (Swift harness, intended RED `46101769870`) → `78830ca`
(Swift port) → `809964a` (runner compile fix) → `aef55e1` (webOS suite, intended RED `46103926430`) →
`5922626` (Swift test compile fix) → `aab31be` (webOS port). Nothing outside the two ports, their tests and
the ledger documents is in this range: no UI, playback, storage or consumer file changed.

### 12.1 Item outcomes

| Item | Section 11 said | Actual state now | Evidence |
| --- | --- | --- | --- |
| Phase B1-S (Swift mirror) | next critical-path item | **implemented, hosted GREEN NOT VERIFIED** | last run at `aab31be`: CI `46104459953` job `140853973103` failed step `Run Live TV foundation tests` on one substring assertion (`main.swift:913`); the `Typecheck Swift sources` step is green. No `assertions: <n>` line has ever been printed by a runner. |
| Phase B1-J (webOS mirror) | after B1-S | **implemented, hosted GREEN NOT VERIFIED** | same run, job `140853973038` step `Run webOS regressions`: `# tests 30 / # pass 18 / # fail 12`. |
| Cross-realm test harness | not anticipated | new defect class, fixed in the working tree | 10 of the 12 JS failures were `node:assert/strict` versus a `vm.runInNewContext` prototype realm, not contract differences; the loader now evaluates the module in the test realm with the host globals shadowed. |
| Calendar strictness | assumed uniform | **not uniform, and now a recorded B3 item** | `new Date` and Dart `DateTime.parse` both roll an impossible day forward (the dart:core page states out-of-range components are "interpreted as overflows", `2020-01-42` → 2020-02-11, and names `DateFormat.parseStrict` as the rejecting alternative); Swift's `ISO8601DateFormatter` range behaviour is undocumented. The webOS and Swift codecs now state the bound themselves; `flutter_app/lib/core/live_catalog_codec.dart` still delegates to `DateTime.parse`. |
| Encoded-text comparison across ports | open question | **answered: not possible for URLs** | Foundation escapes `/` as `\/` in JSON on Apple platforms (in-repo proof `Sources/Core/APIClient.swift:206`), so the Swift port's URL assertions are by parsed value. B3 must compare ports by parsed value, not raw bytes. |
| Independent review of Phase B | section 10/11 pattern | **still not by the team reviewer** | `team_delegate` refuses with `COLLABORATION_MCP_TEAM_LEADER_REQUIRED` in this session shape; what exists is a strictly read-only local review, labelled as such in `EXECUTION_LOG.md`. |

### 12.2 What did not change

No gate was relaxed to get here: `cancel-in-progress`, the `MIN_ASSERTIONS=150` floor, the four
`INTERNAL-ONLY-*` platform labels, the unset `RELEASE_PRODUCTION_READY`, the skipped
`Live API verification` job and the skipped macOS release steps all still stand. `809964a` and `5922626`
have zero hosted runs of their own (`total_count: 0`) because they were pushed inside a batch, so those two
commits are individually unverified even though their content is carried by the tip. Device, OS and runtime
acceptance for macOS, Android phone, Android TV, Windows and webOS remains NOT VERIFIED, and the
`streamSecretRef` value still has no verified secret store behind it on any platform.

### 12.3 Consequence for sequencing

The critical path becomes: push and read the corrective run at the new head (that is the gate for B1-S/B1-J)
→ B2 cross-language agreement fixtures over the same `Tests/fixtures/migration/catalog-v1.json`, with the
Dart date-reading tightening folded into B3 → B4 wiring. Section 11's owner-side blockers are unchanged, and
one green runner at the new head would still not change them.
