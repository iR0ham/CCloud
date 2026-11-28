# CCloud Overnight Execution State (recovery checkpoint)

Append-oriented operational checkpoint. Rewrite the "current" sections when they change;
dated evidence below is a ledger and must not be restated as history that did not happen.

## Snapshot

- Repository: `/Users/roham/Documents/CCloudMac`, remote `iR0ham/CCloud` (public).
- Working branch: `ci/github-first-foundation`.
- HEAD and pushed remote branch head are both
  `cbc48ee249a9402841369fe0087091ccc85d71b5` (`git ls-remote` confirmed): nothing is held locally
  any more. This section said `18dec96` was unpushed while `2a244aa` was the remote head; that was
  true at the time of writing and is superseded here, which is the dated correction the reviewer's
  note N4 asked for.
- Commit order on the branch: `88bc7ea` (Android assertion target fix) → `8a1ef3f` (ledger +
  checkpoint) → `221ce95` (Windows byte-equality) → `9b55536` (provenance digests) → `2a244aa`
  (webOS dev-proxy bound) → `18dec96` (Android green addendum) → `709d9ed` (checkpoint refresh) →
  `cbc48ee` (three-closed-gates ledger addendum).
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

## Current task

- The remediation slice is **closed**: reviewed (ACCEPT WITH NOTES), independently audited, and hosted
  green at every commit through `cbc48ee`.
- Active work moved to the reviewer's hardening notes: one focused slice for N1 (bind the merged
  manifest to this APK), N2 (assert `android:required="false"` instead of only claiming it) and
  N3 (canonicalize the provenance checker's path resolution), each with its own hosted RED → GREEN.
- Phase B1-D (Dart Multi-Source contracts + frozen shared fixtures) is unblocked and starts after
  that slice, so the reviewed head does not move underneath an open review.
- Nothing is held locally: HEAD equals the remote head.

## Remaining tasks (ordered, with the real gate for each)

1. ~~Independent re-review~~ — **closed**: ACCEPT WITH NOTES for `6fb03bf..cbc48ee`, notes N1–N5
   triaged into the work items below. The Android assertion commit `88bc7ea` and the evidence-gap
   slice `221ce95`/`9b55536`/`2a244aa` were folded into it, as this section previously required.
2. **Gate-hardening slice (from the review)** — N1 narrow the merged-manifest `find` fallback to
   `*/merged_manifest/release/*`, fail on ambiguity, and assert a package-identity token in it;
   N2 add `require_token "APK manifest" "$MANIFEST" 'android:required="false"'` or correct the
   comment; N3 make `scripts/verify_provenance.py` canonicalize and re-check containment. Each fix
   must be shown able to go RED on a runner before it is trusted GREEN.
3. **Phase B1 — cross-language contracts, then B2 parsers/registries** (Dart first, then Swift,
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
6. ~~Remaining security and packaging review~~ — **done, with one residual fix**: the re-scan of
   `verify_provenance.py`, the Windows digest loop and `net.js` produced only N3 above, and the
   `bundle-msvc-runtime.ps1` question is answered **no** — its 14 outputs are always hash-compared by
   the paired assert script, so a separate digest list would only duplicate the set and risk drift.
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

1. Land the gate-hardening slice as remaining-task item 2 (N1 + N2 in
   `.github/workflows/build-android.yml`, N3 in `scripts/verify_provenance.py` plus a mutation-shaped
   regression), one logical commit per concern, pushed to `ci/github-first-foundation` and verified by
   a fresh Quality + CI + Build run at that exact SHA.
2. Then start Phase B1-D (Dart contracts + frozen shared fixtures) with hosted RED → GREEN per
   `docs/superpowers/plans/2026-11-25-multi-source-subtitles.md`; the review verdict explicitly allows
   B1 to begin, so no further approval gate is needed before it.
3. Keep `EXECUTION_LOG.md` appends serialized: this checkpoint update and the log addendum for the
   review land together, and any later append waits for the previous member's push.
4. Do not report or tag anything as release-ready: the reviewer confirmed at `cbc48ee` that
   `INTERNAL-ONLY-*` labels and the absent `RELEASE_PRODUCTION_READY=true` still close publication,
   and every release job shows `skipped`.
5. Superseded instructions that used to be here: extend the review to `88bc7ea..2a244aa` (done), and
   promote the discovered merged-manifest path into the explicit candidate list — that framing was
   wrong, because the path the runner actually resolved is *not* one of the three explicit candidates,
   so the correct fix is N1's narrowed fallback plus an identity token, not a path promotion.

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
