# CCloud Overnight Execution State (recovery checkpoint)

Append-oriented operational checkpoint. Rewrite the "current" sections when they change;
dated evidence below is a ledger and must not be restated as history that did not happen.

## Snapshot

- Repository: `/Users/roham/Documents/CCloudMac`, remote `iR0ham/CCloud` (public).
- Working branch: `ci/github-first-foundation`.
- HEAD: `18dec96` locally; pushed remote branch head is `2a244aad359444bd80bbeb50468362d006aab396`
  (`git ls-remote` confirmed) → local is one ledger commit ahead, held on purpose (see Current task).
- Commit order on the branch: `88bc7ea` (Android assertion target fix) → `8a1ef3f` (ledger +
  checkpoint) → `221ce95` (Windows byte-equality) → `9b55536` (provenance digests) → `2a244aa`
  (webOS dev-proxy bound).
- `main`: `6dfd925095b0090b623443f396388fd4d552db63` — untouched, never developed on.
- Worktree: clean apart from the checkpoint edits in this commit.
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

`18dec96` carries the Android addendum to `EXECUTION_LOG.md` and is **committed locally, not yet
pushed**: members share this checkout and append to the same ledger tail, so appends are serialized
to avoid two competing sections.

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

## Current task

- Android assertion gate: **hosted verified green** at `8a1ef3f` (run `46087125808`), first time it
  has ever passed.
- Evidence-gap slice: **hosted verified green** at `2a244aa` (Windows byte-equality, provenance
  digests, webOS dev-proxy bound).
- Waiting on: the Full-stack Engineer's final report for that slice, and the Code Reviewer's verdict.
- Local, unpushed: `18dec96` (Android addendum) plus this checkpoint update — pushed after the
  engineer's ledger appends land so both tails of `EXECUTION_LOG.md` stay ordered.

## Remaining tasks (ordered, with the real gate for each)

1. **Independent re-review** — the verdict must be ACCEPT (or ACCEPT WITH NOTES with the notes
   triaged) before Phase B starts. It was requested for `7b2db7b..6fb03bf`; the Android assertion
   commit `88bc7ea` and the evidence-gap slice `221ce95`/`9b55536`/`2a244aa` must be folded into it.
2. **Phase B1 — cross-language contracts, then B2 parsers/registries** (Dart first, then Swift,
   then JavaScript, sharing the frozen fixtures). No B1/B2 file exists yet; verified by search.
3. ~~Windows package byte-equality evidence gap~~ — **closed and hosted verified**: both Windows
   packages print `Legal files are SHA-256 byte-equal to the canonical repository copies
   (14 compared)` at run `46087990039`.
4. ~~Provenance hash enforcement~~ — **closed and hosted verified**: `scripts/verify_provenance.py`
   recomputes every retained-text digest recorded in `SOURCES.md` offline as a blocking Quality step
   (`provenance: 10 retained files verified…`). Deliberately no network re-fetch comparison; that
   would make the gate depend on upstream availability.
5. ~~webOS dev-proxy unbounded read~~ — **closed and hosted verified**: `proxyFetch` now uses the
   same bounded byte-counting reader and the `response-too-large` policy code, covered by two new
   deterministic regressions (10/10 green in CI `46087990047`).
6. **Remaining security and packaging review** — re-scan the new scripts (`verify_provenance.py`,
   the Windows digest loop, `net.js`) for path-escaping and error-swallowing patterns, and decide
   whether `bundle-msvc-runtime.ps1` should also be digest-checked rather than copy-verified.
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

1. Collect the Full-stack Engineer's final report for `221ce95`/`9b55536`/`2a244aa` and the Code
   Reviewer's verdict; triage notes into work items or accept.
2. Rebase and push the held ledger commits (`18dec96` plus this checkpoint update) once the
   engineer's `EXECUTION_LOG.md` appends are on the remote, so the file keeps one ordered tail.
3. Fold the reviewer's findings, if any, into a focused corrective slice, and extend the independent
   review to `88bc7ea..2a244aa` rather than re-reviewing `7b2db7b..6fb03bf`.
4. Start Phase B1-D (Dart contracts + shared fixtures) with hosted RED → GREEN, per
   `docs/superpowers/plans/2026-11-25-multi-source-subtitles.md`, only after step 1 accepts.
5. Known hardening queued for the next workflow-touching slice: promote
   `build/app/intermediates/merged_manifest/release/outputReleaseAppLinkSettings/AndroidManifest.xml`
   into the explicit candidate list in `.github/workflows/build-android.yml`.

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
