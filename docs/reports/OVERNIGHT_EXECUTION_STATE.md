# CCloud Overnight Execution State (recovery checkpoint)

Append-oriented operational checkpoint. Rewrite the "current" sections when they change;
dated evidence below is a ledger and must not be restated as history that did not happen.

## Snapshot

- Repository: `/Users/roham/Documents/CCloudMac`, remote `iR0ham/CCloud` (public).
- Working branch: `ci/github-first-foundation`.
- HEAD: `6fb03bff7f6c1feffa02cb2a840285d5cbcec263`.
- Remote branch head: identical (`git ls-remote` confirmed) → **synchronized, nothing unpushed**
  except this checkpoint file while it is staged-but-unpushed.
- `main`: `6dfd925095b0090b623443f396388fd4d552db63` — untouched, never developed on.
- Worktree: clean apart from this file.
- Open pull requests: none. Release tags: none (`v2.0.0` was never tagged).
- Canonical identity: version `2.0.0`, global build `22` (Android `versionCode 22`).
  The next release identity (expected `2.1.0` + build `23`) is still an undecided task.

## Hosted ledger (GitHub Actions is the only execution evidence permitted)

At `6fb03bf`:

| Workflow | Run | Result |
| --- | --- | --- |
| Quality | `46085379874` | **success** — Repository hygiene, Required NOTICE files, Version consistency, Workflow lint, Dependency vulnerability scan, Secret scan |
| CI | `46085379959` | **success** — Flutter analyze and tests, macOS arm64 typecheck, Version and canonical metadata, webOS static JS/JSON/service validation (8/8 transport regressions green on the Node 20 runner); Live API verification skipped by design (`live_api=false`) |
| Build all platforms | `46085379924` | webOS IPK **success**, macOS arm64 **success**, Windows Dart analyze / release build / compatibility package (Skia) / runtime smoke / installer install + smoke **success**. Android job (`140793625386`) **failure** at step 15 "Assert APK identity, version, TV launcher/banner, and activity configuration"; Analyze ✓, Test ✓, universal release APK ✓, release App Bundle ✓, artifact naming/upload skipped |

Android failure, as reported by the new diagnostics:
`::error::APK manifest is missing the expected token: @drawable/tv_banner`. Root cause is the
assertion target, not the app: `apkanalyzer manifest print` renders resource references and flag
enumerations as opaque values (`@ref/0x7f070077`, `launchMode="1"`, `configChanges="0x40003fb4"`,
`windowSoftInputMode="0x10"`), so those four literal tokens could never match. Fixed in the working
tree by asserting the literals against the merged release manifest aapt2 compiled into the APK,
while the decoded APK manifest keeps presence checks and the now-real orientation-lock prohibition.
No token was removed and no check was optionalised. Status: **PUSHED, NOT YET HOSTED VERIFIED**.

Prior heads, for continuity:

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

## Current task

- Re-verify the corrected Android assertion on a runner (next `Build all platforms` run) and
  confirm the APK/AAB artifacts, signing label and checksums get produced end to end.
- An independent read-only re-review of `7b2db7b..6fb03bf` was requested through the Team;
  it was accepted this turn (earlier attempts returned `COLLABORATION_MCP_TEAM_LEADER_REQUIRED`).
  The Android assertion commit added after that delegation must be folded into the verdict.

## Remaining tasks (ordered, with the real gate for each)

1. **Android hosted re-verification** — the corrected assertion must go green on a runner, and the
   job must then reach artifact naming, checksum and upload. If a literal token still fails against
   the merged manifest, that is a genuine source-manifest defect and must be fixed in
   `flutter_app/android/app/src/main/AndroidManifest.xml`, not by relaxing the gate.
2. **Independent re-review** — verdict must be ACCEPT (or ACCEPT WITH NOTES with the notes
   triaged) before Phase B starts.
3. **Phase B1 — cross-language contracts, then B2 parsers/registries** (Dart first, then Swift,
   then JavaScript, sharing the frozen fixtures). No B1/B2 file exists yet; verified by search.
4. **Windows package byte-equality evidence gap** — `bundle-msvc-runtime.ps1` /
   `assert-windows-package.ps1` stage and assert canonical legal files, but byte-equality against
   the repository copies should be asserted the way Android and webOS do (`cmp`-equivalent).
5. **Provenance hash enforcement** — nothing currently proves the hashes quoted in `SOURCES.md`
   were recomputed in CI; consider a hosted Quality job that re-verifies retained license text
   digests against GNU/upstream URLs.
6. **Remaining security and packaging review** — `proxyFetch` in `webos_app/app/js/net.js`
   (localhost dev-only) still reads `r.text()` unbounded; decide whether to bound it or keep the
   documented dev-only exception.
7. **Phase C failover, Phase D/E/F subtitles, Phase G full matrix** — after B is hosted-green.
8. **Unified versioning decision + release manifest** — canonical `2.0.0+22` today; the release
   bump and manifest generation are not implemented.
9. **Docs synchronization** — `OVERNIGHT_RELEASE_EXECUTION_REPORT.md` at the end, per mission.

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

1. Read the Android job outcome of run `46085379924` (job `140793625386`). If it failed, fetch
   `gh run view 46085379924 --repo iR0ham/CCloud --log-failed` and locate the `::error::` line
   naming the missing token, then fix the smallest appropriate scope.
2. Integrate the Team reviewer's verdict; triage notes into work items or accept.
3. Push this checkpoint together with the next corrective/implementation slice, so no docs-only
   commit spends a full hosted Android cycle.
4. Then start Phase B1-D (Dart contracts + shared fixtures) with hosted RED → GREEN, per
   `docs/superpowers/plans/2026-11-25-multi-source-subtitles.md`.

## How to resume after an interruption

- `cd /Users/roham/Documents/CCloudMac && git status --short && git log --oneline -6`
- `git ls-remote origin ci/github-first-foundation`
- `gh run list --repo iR0ham/CCloud --commit <HEAD> --json databaseId,workflowName,status,conclusion`
- Constraints that still apply: GitHub-hosted execution only; never weaken a quality, legal or
  distribution gate to obtain green; never invent legal documents, source archives, signing
  evidence, device acceptance, or EPG data; never force-push; never develop on `main`; keep
  `EXECUTION_LOG.md` append-only; replies to the owner are in Persian.
