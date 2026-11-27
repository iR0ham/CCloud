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
