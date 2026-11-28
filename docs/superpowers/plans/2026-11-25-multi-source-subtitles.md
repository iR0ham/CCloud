# Multi-Source IPTV + Advanced Subtitle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add independent playlist management, stable logical-channel/source identities, controlled multi-source playback, and renderer-gated embedded/external subtitle support without replacing the existing players or regressing current CCloud behavior.

**Architecture:** Extend the existing Swift, Flutter, and webOS playback stacks with a shared conceptual contract: playlist records own channel members; a source registry owns playback endpoints; a logical catalog applies only explicit user associations; existing source walking/failover is extended rather than replaced. Subtitle discovery, selection, preferences, and rendering remain separate responsibilities integrated at each player's existing track/session boundary. The built-in Iran catalog remains a fixed adapter into the unified catalog.

**Tech Stack:** Swift 5/AppKit/SwiftUI/AVFoundation/CryptoKit; Flutter/Dart/media_kit/libmpv/shared_preferences/path_provider/http/crypto, with `file_picker` and `flutter_secure_storage` only after the B4 dependency/license gate; ES2017 JavaScript/Chromium 68/webOS HTML5 video; GitHub Actions; Node's built-in test runner for pure webOS logic.

**Spec:** Owner-supplied “CCloud — Multi-Source IPTV & Advanced Subtitle System” specification (2026-11-24), persisted as requirements and traceability in `docs/audits/MULTISOURCE_SUBTITLE_ARCHITECTURE_AUDIT.md`.

**Audit:** `docs/audits/MULTISOURCE_SUBTITLE_ARCHITECTURE_AUDIT.md`

**Baseline:** `ci/github-first-foundation` at `3d6e8762ce8826a52297f83b5f6952a26f15ba44`

## Global Constraints

- GitHub-hosted build/test/analyze/package only. Local runtime is **NOT VERIFIED**.
- CCloud 2.0.0 build 22 identity remains unchanged unless a separately authorized release task changes `version.json`.
- Preserve the built-in Iran catalog composition: Famelack supplies the Iran channel list; iptv-org Iran/Persian playlists add backup URLs only and never add channels.
- Preserve media favorites, watch history, Continue Watching, auto-next, link-health behavior, Live TV search, the diagnostics/EPG workstream boundaries, and the existing public API identifier.
- Do not introduce a second playback engine solely for subtitles.
- No account, paywall, premium tier, paid API, mandatory paid subtitle service, or artificial playlist/source/settings limit.
- Preserve the existing visual identity, components, navigation, theme, and typography. New controls must support desktop keyboard/mouse, Android touch, Android TV remote input, macOS conventions, and webOS remote input without adding a redundant application shell.
- Keep parsing and file I/O off the UI path, reuse unchanged parse results, permit only one active recovery chain per logical channel, cancel obsolete work, and dispose subtitle/player resources on teardown.
- Do not invent EPG programmes or claim an Iran-covering licensed feed. Preserve explicit no-data states.
- SRT, WebVTT, ASS, SSA, embedded MKV/MP4/HLS subtitle, styling, and RTL claims are gated by actual renderer/device evidence.
- Do not scan unauthorized filesystems. Automatic subtitle discovery is limited to roots explicitly authorized by the user.
- Treat playlist text, URLs, subtitle files, XMLTV, logos, and provider metadata as untrusted input.
- CI uses deterministic fixtures and controlled mock streams; it must not depend on random public IPTV availability.
- Redact credentials and sensitive URL query values from logs, crash reports, diagnostics, and test snapshots.
- Persist secrets only through verified platform secret-storage mechanisms. A platform without a verified mechanism must reject credential-bearing URLs explicitly rather than store them in plaintext.
- Do not disable TLS certificate validation or add insecure network workarounds.
- Native-media provenance, Android relinkable-object, Windows native-package, and FFmpeg release blockers remain hard release gates.
- No production release, tag, signing change, or distribution-status change is authorized by this plan.
- Status, provenance, source, notice, and verification records are append-only decision ledgers; add dated evidence instead of rewriting historical claims.
- Scheduled playlist refresh is out of scope for Phase B because no reliable existing scheduler was found. Manual refresh, cache reuse, and in-flight request deduplication are required instead.
- Every capability is labeled `Supported`, `Partially Supported`, `Unsupported`, or `Not Yet Verified`; compilation alone never proves support.

## Verification and Execution Rules

- All commands in this document are future implementation commands. None was executed while authoring this plan.
- Build, format, analyze, test, package, and render commands run only on GitHub-hosted runners. Device/emulator evidence must identify the hosted runner or physical device, OS/firmware, app commit, and renderer/engine version.
- A test-first task records a RED GitHub Actions run before implementation and a GREEN run on the same task branch afterward. A source-only review is not a substitute for either run.
- Each task commit contains only that task's owned files. Do not amend a failed task commit; fix forward with a new commit.
- Parallel workers may own different platform files. They may not own the same file. The dependency and ownership tables below are authoritative.
- `git add` and `git commit` commands shown in tasks are for the future authorized implementation phase. No commit or push was performed during plan authoring.

## Canonical Contract

The three platforms use the same field names and semantics. Dates are RFC 3339 UTC strings in persisted JSON. Arrays preserve user/source order. IDs are opaque and contain no raw URL, credential, provider token, or display name.

### Enumerations

| Contract | Values |
|---|---|
| `PlaylistSourceType` | `builtIn`, `remoteUrl`, `localFile` |
| `PlaylistRefreshStatus` | `idle`, `refreshing`, `ready`, `error` |
| `SourceHealth` | `unverified`, `available`, `failed`, `disabled` |
| `SourceOrigin` | `playlist`, `user` |
| `PlaylistFormat` | `m3uChannelList`, `hlsMediaManifest`, `empty`, `invalid` |
| `CatalogIssueCode` | `invalidUrl`, `missingName`, `missingStream`, `unsupportedMediaManifest`, `malformedEntry`, `oversizedInput`, `limitExceeded`, `identityCollision`, `staleRefresh`, `secretStorageUnavailable`, `localAccessUnavailable`, `catalogUnavailable` |
| `SourceFailureKind` | `transport`, `timeout`, `http`, `unsupportedMedia`, `demux`, `decoder`, `temporaryBuffering`, `cancelled`, `unknown` |
| `SubtitleOrigin` | `embedded`, `externalFile`, `discoveredFile` |
| `SubtitleFormat` | `srt`, `webvtt`, `ass`, `ssa`, `embeddedUnknown` |
| `RendererSupport` | `Supported`, `Partially Supported`, `Unsupported`, `Not Yet Verified` |

### Persisted and runtime records

```text
PlaylistRecord
  playlistId: String
  name: String
  sourceType: PlaylistSourceType
  locationRef: String
  enabled: Boolean
  createdAt: DateTime
  lastUpdatedAt: DateTime?
  lastSuccessfulRefresh: DateTime?
  refreshStatus: PlaylistRefreshStatus
  lastErrorCode: String?
  channelCount: Int
  parsingVersion: Int = 1

ChannelMember
  memberId: String
  playlistId: String
  providerNamespace: String
  providerChannelId: String
  displayName: String
  normalizedName: String
  logoUrl: String?
  group: String?
  countryCode: String?
  languages: [String]
  tvgId: String?
  ordinal: Int

PlaylistParseResult
  format: PlaylistFormat
  channels: [ParsedChannel]
  issues: [CatalogIssue]
  contentHash: String                // stableKeyHash of exact decoded UTF-8 bytes
  inputBytes: Int
  truncated: Boolean

ChannelSourceRecord
  sourceId: String
  channelId: String                 // logical channel ID
  memberId: String
  playlistId: String
  providerNamespace: String
  label: String
  streamUrl: String                 // runtime value; empty when restored through streamSecretRef
  streamSecretRef: String?          // persisted secret reference; URL omitted from JSON when present
  protocolHint: String              // hls, dash, mp4, or unknown
  rendererCapability: RendererSupport = Not Yet Verified
  origin: SourceOrigin               // playlist-parsed or explicitly user-added
  priority: Int
  enabled: Boolean
  health: SourceHealth
  lastSuccessfulPlaybackAt: DateTime?
  lastFailedPlaybackAt: DateTime?
  lastErrorCode: String?

LogicalChannel
  channelId: String
  displayName: String
  normalizedName: String
  logoUrl: String?
  category: String?
  countryCode: String?
  languages: [String]
  memberIds: [String]               // first member is the preferred metadata/playlist owner
  sources: [ChannelSourceRecord]
  favorite: Boolean
  hidden: Boolean
  userOrder: Int?
  automaticFailoverEnabled: Boolean
  sourcePolicy: SourcePolicy
  lastSuccessfulSourceId: String?

SourcePolicy
  maxAutomaticAttempts: Int = 3
  sameSourceRetries: Int = 2
  connectTimeoutMs: Int = 15000
  backoffMs: [Int] = [500, 1500, 4000]
  failedCooldownSeconds: Int = 600
  bufferingThresholdMs: Int = 30000

LivePlaybackContext
  playlistId: String
  logicalChannelId: String
  sourceIds: [String]               // same order as enabled request-local sources
  automaticFailoverEnabled: Boolean
  sourcePolicy: SourcePolicy

PlaybackAttemptContext              // runtime only; never persisted or encoded
  requestGeneration: String         // unique per playback request/recovery chain
  playlistId: String
  logicalChannelId: String
  sourceId: String                  // stable ID of the current attempt
  attemptNumber: Int                // starts at 1; increments for every retry/advance
  stableMediaIdentity: String       // logicalChannelId for live TV; existing media identity otherwise

ChannelAssociation
  memberIds: [String]                // two or more members explicitly associated by the user

ChannelPreference
  channelId: String
  favorite: Boolean
  hidden: Boolean
  category: String?
  userOrder: Int?
  automaticFailoverEnabled: Boolean
  sourcePolicy: SourcePolicy
  lastSuccessfulSourceId: String?

ChannelWatchRecord
  channelId: String
  watchedAt: DateTime

CatalogIssue
  code: String                     // one of the CatalogIssueCode values
  line: Int?
  message: String                   // safe, non-sensitive diagnostic text

LiveCatalogState
  schemaVersion: Int = 1
  playlists: [PlaylistRecord]
  members: [ChannelMember]
  sources: [ChannelSourceRecord]
  associations: [ChannelAssociation]
  preferences: [ChannelPreference]
  recentWatches: [ChannelWatchRecord]
  logicalIdByMemberId: [String: String]

UnifiedCatalogSnapshot
  revision: Int
  generatedAt: DateTime
  playlists: [PlaylistRecord]
  channels: [LogicalChannel]
  issues: [CatalogIssue]
```

The audit's `PlaylistRecord.schemaVersion` is represented by the `LiveCatalogState.schemaVersion = 1` envelope; each record's `parsingVersion` tracks parser evolution. No redundant per-record schema version is persisted. `ChannelSourceRecord.rendererCapability` starts as `Not Yet Verified`. A real successful playback may set `Supported`; a definitive engine rejection such as `unsupportedMedia` may set `Unsupported` through `setRendererCapability`; transport/timeout/HTTP failures never change it. `Partially Supported` requires recorded evidence of the exact supported subset. Removing a source clears any `lastSuccessfulSourceId` preference that references it; disabling a source does not clear that historical preference. `locationRef` is a built-in key, a security-scoped bookmark/URI reference, or a secret-store reference. A credential-free remote URL may be used directly only on a platform whose repository explicitly permits it. `streamUrl` is never serialized when `streamSecretRef` is present. `LivePlaybackContext.playlistId` identifies the preferred logical member's playlist for diagnostics; every `ChannelSourceRecord` retains its actual playlist ownership. `UnifiedCatalogSnapshot.revision` is repository-instance state: it starts at 1 after load and increments once per successfully persisted state mutation; `generatedAt` is snapshot-build time in UTC, and `issues` contains only the current catalog/refresh issues.

### Identity rules

1. `memberId = "member:" + stableKeyHash(playlistId + "\nprovider\n" + providerNamespace + "\n" + providerChannelId)` when a nonempty provider channel ID exists.
2. Without a provider ID, `providerChannelId` is `"fallback:" + normalizedName + "|" + countryCode + "|" + group + "|" + logoUrl + "|" + occurrence`. `occurrence` is the zero-based first-seen index for that exact fallback tuple in that playlist.
3. `sourceId = "source:" + stableKeyHash(memberId + "\nurl\n" + canonicalStreamUrl)`.
4. A new logical channel uses its member ID. An explicit association uses the existing logical ID selected by the user as `preferredLogicalId`; it never derives identity from a stream URL.
5. Separating a member creates `"logical:" + stableKeyHash(memberId)` unless that member already has another persisted logical ID.
6. Name similarity creates a candidate only. It never changes `logicalIdByMemberId` automatically.
7. An exact namespaced provider ID plus compatible metadata may rank as an `exactProviderId` candidate, but Phase B still requires explicit user association; it never auto-associates. This deliberately chooses the spec's probabilistic/user-control interpretation and is stricter than the audit's optional automatic-association wording.
8. `stableKeyHash` is a deterministic 128-bit, non-cryptographic identifier hash: four FNV-1a 32-bit passes over UTF-8 bytes with seeds `0x811c9dc5`, `0x9e3779b9`, `0x85ebca6b`, and `0xc2b2ae35`, concatenated as eight lowercase hexadecimal digits each. It is not used for passwords or signatures. A detected collision raises `identityCollision` and prevents the merge.

### Input limits

- Playlist response/file: 10 MiB decoded UTF-8, 200,000 physical lines, 50,000 channel members, 100 stream URLs per member, 8,192 characters per URL.
- Subtitle file: 5 MiB, 20,000 cues, 8,192 characters per cue text.
- Authorized-root discovery listing: 20,000 entries and 16 directory levels per explicitly authorized root.
- XMLTV: 25 MiB and 100,000 programme elements per supplied file.
- These are resource-safety ceilings, not product quotas. Playlist payloads above 10 MiB produce `oversizedInput` and no catalog replacement; line/member/per-member-URL/URL-length ceilings produce `limitExceeded`, retain the permitted prefix, set `truncated`, and preserve the last good catalog if no valid channel remains. Subtitle limit violations fail the file visibly. XMLTV limit handling belongs to the separate EPG workstream.

## File-to-Responsibility Map

| File | Responsibility | Phase |
|---|---|---|
| `flutter_app/lib/core/live_contracts.dart` | Dart playlist/member/source/logical-channel contracts | B1 |
| `flutter_app/lib/core/live_catalog_codec.dart` | Dart schema-v1 codec and additive migration | B1 |
| `flutter_app/test/live_contracts_test.dart` | Dart contract/migration tests | B1 |
| `Sources/Core/LiveTVContracts.swift` | Swift canonical contracts | B1 |
| `Sources/Core/LiveTVCatalogCodec.swift` | Swift schema-v1 codec and additive migration | B1 |
| `Sources/Core/LiveTVM3UClient.swift` | Existing Swift M3U/name-normalization source; compiled in hosted tests without network calls | B2-B4 |
| `Sources/Core/LiveTVModels.swift` | Existing Swift channel model, runtime-only live context, and C2 request/attempt adapter | B3, B4-S, C2 |
| `Sources/Core/Models.swift` | Existing shared models/API errors required by hosted Live TV runners; C2 runtime-only live/attempt contexts | B2-B4, C2 |
| `Sources/Core/PersianNumber.swift` | Existing Persian-digit helper required by the hosted Live TV model runner | B2-B4 |
| `Tests/live-foundation/main.swift` | Swift pure foundation assertions | B1-B3 |
| `Tests/live-foundation/run.sh` | Hosted Swift foundation runner | B1 |
| `Tests/playlist-repository/main.swift` | Swift repository assertions with fake seams | B4 |
| `Tests/playlist-repository/run.sh` | Hosted Swift repository runner | B4 |
| `webos_app/app/js/playlist_contracts.js` | JavaScript canonical records/codec/migration | B1 |
| `webos_app/test/live_contracts.test.js` | Node contract/migration tests | B1 |
| `Tests/fixtures/multi-source/*.m3u*` | Shared deterministic playlist fixtures | B2 |
| `Tests/fixtures/migration/*` | Legacy and schema-v1 migration fixtures | B1 |
| `flutter_app/lib/core/playlist_parser.dart` | Dart M3U channel-list parser | B2 |
| `flutter_app/lib/core/source_registry.dart` | Dart URL validation, canonicalization, stable IDs | B2 |
| `flutter_app/lib/core/identity_hash.dart` | Dart shared identifier hash | B2 |
| `flutter_app/test/playlist_parser_test.dart` | Dart parser/registry tests | B2 |
| `Sources/Core/LiveTVPlaylistParser.swift` | Swift M3U channel-list parser | B2 |
| `Sources/Core/LiveTVSourceRegistry.swift` | Swift URL validation, canonicalization, stable IDs | B2 |
| `Sources/Core/LiveTVIdentityHash.swift` | Swift shared identifier hash | B2 |
| `webos_app/app/js/playlist_parser.js` | JavaScript M3U channel-list parser | B2 |
| `webos_app/app/js/source_registry.js` | JavaScript URL validation, canonicalization, stable IDs | B2 |
| `webos_app/app/js/identity_hash.js` | JavaScript shared identifier hash | B2 |
| `webos_app/test/playlist_parser.test.js` | Node parser/registry tests | B2 |
| `flutter_app/lib/core/channel_identity.dart` | Dart candidate detection and explicit association | B3 |
| `flutter_app/lib/core/unified_catalog.dart` | Dart logical catalog builder | B3 |
| `flutter_app/lib/core/builtin_catalog_adapter.dart` | Dart fixed built-in adapter | B3 |
| `flutter_app/test/channel_identity_test.dart` | Dart identity/catalog tests | B3 |
| `Sources/Core/LiveTVChannelIdentity.swift` | Swift candidate detection and explicit association | B3 |
| `Sources/Core/UnifiedLiveCatalog.swift` | Swift logical catalog builder | B3 |
| `Sources/Core/BuiltInLiveCatalogAdapter.swift` | Swift fixed built-in adapter | B3 |
| `webos_app/app/js/channel_identity.js` | JavaScript candidate detection and explicit association | B3 |
| `webos_app/app/js/unified_catalog.js` | JavaScript logical catalog builder and built-in/user composition | B3, B4 |
| `webos_app/app/js/builtin_catalog_adapter.js` | JavaScript fixed built-in adapter | B3 |
| `webos_app/test/channel_identity.test.js` | Node identity/catalog tests | B3 |
| `flutter_app/lib/core/playlist_repository.dart` | Dart playlist state, refresh, cache, secret references | B4 |
| `flutter_app/lib/core/playlist_secret_store.dart` | Dart secure-storage adapter contract | B4 |
| `flutter_app/lib/core/unified_live_catalog.dart` | Dart built-in/user catalog composition | B4 |
| `flutter_app/lib/screens/playlist_manager_screen.dart` | Flutter playlist management UI | B4 |
| `flutter_app/lib/screens/live_screen.dart` | Existing Live TV integration point | B4 |
| `flutter_app/lib/core/live_catalog.dart` | Preserve fixed Iran loader; expose unified adapter | B4 |
| `flutter_app/pubspec.yaml` | File-picker/secure-storage dependency gate | B4 |
| `flutter_app/pubspec.lock` | Reviewed resolved versions | B4 |
| `Sources/Core/PlaylistRepository.swift` | Swift playlist state/refresh/cache | B4 |
| `Sources/Core/LiveCatalogFileStore.swift` | Swift Application Support state file and atomic writes | B4 |
| `Sources/Core/PlaylistSecretStore.swift` | Keychain adapter | B4 |
| `Sources/Core/UnifiedLiveCatalogService.swift` | Swift built-in/user composition | B4 |
| `Sources/UI/Live/PlaylistManagerView.swift` | Swift playlist management sheet | B4 |
| `Sources/UI/Live/LiveTVView.swift` | Existing model/view integration | B4 |
| `Sources/Core/LiveTVCatalog.swift` | Preserve fixed built-in loader | B4 |
| `webos_app/app/js/playlist_repository.js` | webOS playlist state/refresh/cache | B4 |
| `webos_app/app/js/screens/playlists.js` | webOS playlist management screen | B4 |
| `webos_app/app/js/screens/live.js` | Existing Live TV integration | B4 |
| `webos_app/app/index.html` | Load new scripts before screens | B4 |
| `flutter_app/lib/core/source_resolution.dart` | Shared source policy/failure/cooldown logic | C1 |
| `flutter_app/lib/core/models.dart` | Existing Flutter channel model and runtime-only live context | B4-D, C3 |
| `flutter_app/lib/core/playback.dart` | Existing Flutter request/source-selection boundary | C3 |
| `Sources/Core/LiveTVSourceResolution.swift` | Swift source policy | C1 |
| `webos_app/app/js/source_resolution.js` | webOS source policy | C1 |
| `Sources/Player/PlaybackController.swift` | Existing Swift failover integration | C2 |
| `flutter_app/lib/screens/player_screen.dart` | Existing Flutter failover integration | C3 |
| `webos_app/app/js/player.js` | Existing webOS failover integration | C4 |
| `flutter_app/lib/core/subtitle_contracts.dart` | Subtitle track/preferences/capability contracts | D1 |
| `flutter_app/lib/core/subtitle_parser.dart` | SRT/WebVTT validation and cue parsing | D1 |
| `Sources/Core/SubtitleContracts.swift` | Swift subtitle contracts | D1 |
| `Sources/Core/SubtitleParser.swift` | SRT/WebVTT validation and cue parsing | D1 |
| `webos_app/app/js/subtitle_contracts.js` | webOS subtitle contracts | D1 |
| `webos_app/app/js/subtitle_parser.js` | SRT/WebVTT validation and cue parsing | D1 |
| `Sources/Player/SubtitleController.swift` | AVFoundation legible selection/external overlay | D2 |
| `Sources/Player/PlaybackController.swift` | Swift subtitle session boundary | D2 |
| `Sources/UI/Detail/PlayerScreen.swift` | Swift subtitle controls | D2, F2 |
| `Sources/UI/Detail/SubtitleSettingsView.swift` | Swift subtitle settings panel | D2, F2 |
| `flutter_app/lib/core/subtitle_controller.dart` | Fakeable subtitle-renderer seam and media_kit track/add-sub-file adapter | D3 |
| `flutter_app/lib/screens/player_screen.dart` | Flutter source/subtitle controls | C3, D3, F2 |
| `webos_app/app/js/subtitle_controller.js` | HTML5 text-track adapter or explicit not-verified rejection | D4 |
| `webos_app/app/js/player.js` | webOS source/subtitle controls with device gates | C4, D4, F2 |
| `flutter_app/lib/core/subtitle_discovery.dart` | Authorized-root filename matching/cache | E1 |
| `flutter_app/lib/core/subtitle_root_reader.dart` | Android SAF and Windows authorized-directory reader/picker seam | E1 |
| `flutter_app/android/app/src/main/kotlin/com/ccloud/ccloud/MainActivity.kt` | Android SAF permission, recursive `DocumentsContract` listing, and root-release method-channel handling; the picker UI remains in `file_picker` | E1 |
| `Sources/Core/SubtitleDiscoveryService.swift` | Authorized-root filename matching/cache | E1 |
| `Sources/Core/AuthorizedSubtitleRootReader.swift` | macOS directory bookmark, containment-checked recursive reader | E1 |
| `webos_app/app/js/subtitle_discovery.js` | webOS pure subtitle matcher; filesystem access excluded | E1 |
| `Tests/fixtures/subtitles/*` | Deterministic encoding/timing/RTL/discovery fixtures | D1, E1 |
| `Tests/player/*` | Hosted AVPlayerLayer playback/subtitle harness | C2, D2 |
| `flutter_app/lib/core/subtitle_preferences.dart` | Flutter versioned preferences | F1 |
| `Sources/Core/SubtitlePreferencesStore.swift` | Swift versioned preferences | F1 |
| `webos_app/app/js/subtitle_preferences.js` | webOS versioned preferences | F1 |
| `docs/architecture/MULTI_SOURCE_SUBTITLE_COMPATIBILITY.md` | Evidence-backed platform matrix | G1 |
| `docs/verification/2026-11-25-multi-source-subtitles.md` | Commit-scoped verification report | G1 |
| `SOURCES.md` | Append-only provenance/source evidence updates | G1 |
| `THIRD_PARTY_NOTICES.md` | Append-only dependency/license notice updates | G1 |
| `.github/workflows/ci.yml` | Hosted foundation, repository, integration, and device jobs | B1-S, B1-J, B4-S, G1 |

## Dependency Order and Ownership

```text
B1 contracts/migrations
  B1-D Dart + shared schema fixture
        → B1-S Swift + hosted Swift runner
        → B1-J JavaScript + hosted Node step
        ↓
B2 parser/source registry
  B2-D Dart + shared playlist fixtures
        ├─ B2-S Swift
        └─ B2-J JavaScript
        ↓
B3 identity/unified catalog
  ├─ B3-D Dart
  ├─ B3-S Swift
  └─ B3-J JavaScript
        ↓
B4 repository/playlist management/catalog integration
  ├─ B4-D Flutter
  ├─ B4-S Swift
  └─ B4-J webOS
        ↓
C1 shared source policy → C2 Swift / C3 Flutter / C4 webOS → C5 source UI/diagnostics
        ↓
D1 subtitle contracts/parsers → D2 macOS / D3 Flutter / D4 webOS proof-gated adapter
        ↓
E1 discovery → F1 versioned preferences/renderer mapping → F2 settings/timing/RTL proof → G1 cross-platform verification/release review → G2 device/emulator acceptance
```

B1-D precedes B1-S because it creates the shared schema fixture. B1-J follows B1-S because it adds the Node test step after the Swift runner is established. B2-D precedes B2-S/B2-J because it creates the shared playlist fixtures; B2-S and B2-J may then run in parallel. B3 platform tasks may run in parallel after all B2 tasks are green. B4 platform tasks may run in parallel after all B3 tasks are green. Later phases are sequential at the stage level.

## Shared Fixtures

Create these files during B1/B2, not during plan authoring.

### `Tests/fixtures/multi-source/valid.m3u`

```m3u
#EXTM3U
#EXTINF:-1 tvg-id="PressTV.ir" tvg-logo="https://img.example/press.png" group-title="News" tvg-language="eng",Press TV (720p)
https://cdn.example/press/master.m3u8
#EXTINF:-1 tvg-id="PressTV.ir" tvg-logo="https://img.example/press.png" group-title="News" tvg-language="eng",Press TV (1080p)
https://cdn.example/press/backup.m3u8
#EXTINF:-1 tvg-id="IRIB1.ir" group-title="General" tvg-language="fas",IRIB 1
https://cdn.example/irib/one.mpd
#EXTINF:-1 group-title="Culture",شبکهٔ يك
https://cdn.example/one.m3u8
```

### `Tests/fixtures/multi-source/duplicates.m3u`

```m3u
#EXTM3U
#EXTINF:-1 tvg-id="PressTV.ir" group-title="News",Press TV
https://cdn.example/press/a.m3u8
#EXTINF:-1 tvg-id="PressTV.ir" group-title="News",Press TV
https://CDN.example/press/a.m3u8#fragment
https://cdn.example/press/b.m3u8
#EXTINF:-1 tvg-id="Other.ir" group-title="News",Press TV
https://cdn.example/other.m3u8
```

### `Tests/fixtures/multi-source/malformed.m3u`

```m3u
#EXTM3U
#EXTINF:-1 tvg-id="Good.ir" group-title="News",Good TV
https://cdn.example/good.m3u8
#EXTINF:-1 tvg-id="NoUrl.ir",No URL
#EXTINF:-1 tvg-id="NoName.ir",
#EXTINF:broken line
https://cdn.example/orphan.m3u8
#EXTINF:-1 tvg-id="Bad.ir",Bad TV
file:///etc/passwd
#EXTINF:-1 tvg-id="Relative.ir",Relative TV
relative/stream.m3u8
```

### `Tests/fixtures/multi-source/hls-master.m3u8`

```m3u8
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=1280000,RESOLUTION=1280x720
video/720/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2560000,RESOLUTION=1920x1080
video/1080/index.m3u8
```

### `Tests/fixtures/multi-source/empty.m3u`

```m3u
#EXTM3U
```

### `Tests/fixtures/migration/macos-favorites.json`

```json
[{"kind":"movie","movie":{"id":7,"type":"movie","title":"Legacy Movie","description":"","year":2020,"imdb":7.1,"rating":7.1,"duration":null,"image":"https://img.example/poster.jpg","cover":"https://img.example/cover.jpg","genres":[],"sources":[],"country":[]},"series":null,"addedAt":"2026-01-02T03:04:05Z"}]
```

### `Tests/fixtures/migration/macos-history.json`

```json
[{"kind":"movie","movie":{"id":7,"type":"movie","title":"Legacy Movie","description":"","year":2020,"imdb":7.1,"rating":7.1,"duration":null,"image":"https://img.example/poster.jpg","cover":"https://img.example/cover.jpg","genres":[],"sources":[],"country":[]},"series":null,"lastWatchedAt":"2026-01-03T03:04:05Z","progress":0.5,"episodes":[],"position":120.0,"duration":240.0}]
```

### `Tests/fixtures/migration/flutter-legacy-prefs.json`

```json
{"ccloud.favorites":["{\"item\":{\"id\":7,\"title\":\"Legacy Movie\"},\"addedAt\":\"2026-01-02T03:04:05Z\"}"],"ccloud.history":["{\"item\":{\"id\":7,\"title\":\"Legacy Movie\"},\"lastWatchedAt\":\"2026-01-03T03:04:05Z\",\"progress\":0.5,\"episodes\":[]}"],"ccloud.appearance":"dark","ccloud.preferredQuality":"auto"}
```

### `Tests/fixtures/migration/webos-legacy-storage.json`

```json
{"ccloud.favorites":[{"item":{"id":7,"title":"Legacy Movie"},"addedAt":"2026-01-02T03:04:05Z"}],"ccloud.history":[{"item":{"id":7,"title":"Legacy Movie"},"lastWatchedAt":"2026-01-03T03:04:05Z","progress":0.5,"episodes":[]}],"ccloud.settings":{"appearance":"dark","preferredQuality":"auto"}}
```

### `Tests/fixtures/migration/catalog-v1.json`

```json
{"schemaVersion":1,"playlists":[{"playlistId":"builtin:live","name":"CCloud","sourceType":"builtIn","locationRef":"builtin:live","enabled":true,"createdAt":"2026-01-01T00:00:00Z","lastUpdatedAt":"2026-01-01T00:00:00Z","lastSuccessfulRefresh":"2026-01-01T00:00:00Z","refreshStatus":"ready","lastErrorCode":null,"channelCount":0,"parsingVersion":1}],"members":[],"sources":[],"associations":[],"preferences":[],"recentWatches":[],"logicalIdByMemberId":{}}
```

# Phase B — Multi-Source Foundation

Phase B is independently testable without playback, UI rendering, network access, or a device. Its deliverable is a working multi-playlist/multi-source foundation with additive persistence and fixed built-in catalog behavior.

## Task B1-D: Dart Contracts and Additive Migration

**Files:**
- Create: `flutter_app/lib/core/live_contracts.dart`
- Create: `flutter_app/lib/core/live_catalog_codec.dart`
- Test: `flutter_app/test/live_contracts_test.dart`
- Fixtures: `Tests/fixtures/migration/catalog-v1.json`, `Tests/fixtures/migration/flutter-legacy-prefs.json`

**Interfaces consumed:** none.

**Interfaces produced:**

```dart
enum PlaylistSourceType { builtIn, remoteUrl, localFile }
enum PlaylistRefreshStatus { idle, refreshing, ready, error }
enum SourceHealth { unverified, available, failed, disabled }
enum SourceOrigin { playlist, user }

class PlaylistRecord {
  const PlaylistRecord({
    required this.playlistId,
    required this.name,
    required this.sourceType,
    required this.locationRef,
    required this.enabled,
    required this.createdAt,
    this.lastUpdatedAt,
    this.lastSuccessfulRefresh,
    this.refreshStatus = PlaylistRefreshStatus.idle,
    this.lastErrorCode,
    this.channelCount = 0,
    this.parsingVersion = 1,
  });
  final String playlistId;
  final String name;
  final PlaylistSourceType sourceType;
  final String locationRef;
  final bool enabled;
  final DateTime createdAt;
  final DateTime? lastUpdatedAt;
  final DateTime? lastSuccessfulRefresh;
  final PlaylistRefreshStatus refreshStatus;
  final String? lastErrorCode;
  final int channelCount;
  final int parsingVersion;
}

class ChannelMember {
  const ChannelMember({
    required this.memberId,
    required this.playlistId,
    required this.providerNamespace,
    required this.providerChannelId,
    required this.displayName,
    required this.normalizedName,
    required this.ordinal,
    this.logoUrl,
    this.group,
    this.countryCode,
    this.languages = const [],
    this.tvgId,
  });
  final String memberId;
  final String playlistId;
  final String providerNamespace;
  final String providerChannelId;
  final String displayName;
  final String normalizedName;
  final int ordinal;
  final String? logoUrl;
  final String? group;
  final String? countryCode;
  final List<String> languages;
  final String? tvgId;
}

const List<String> rendererSupportValues = [
  'Supported',
  'Partially Supported',
  'Unsupported',
  'Not Yet Verified',
];

class ChannelSourceRecord {
  const ChannelSourceRecord({
    required this.sourceId,
    required this.channelId,
    required this.memberId,
    required this.playlistId,
    required this.providerNamespace,
    required this.label,
    required this.protocolHint,
    this.rendererCapability = 'Not Yet Verified',
    required this.origin,
    required this.priority,
    required this.enabled,
    required this.health,
    this.streamUrl = '',
    this.streamSecretRef,
    this.lastSuccessfulPlaybackAt,
    this.lastFailedPlaybackAt,
    this.lastErrorCode,
  });
  final String sourceId;
  final String channelId;
  final String memberId;
  final String playlistId;
  final String providerNamespace;
  final String label;
  final String streamUrl;
  final String? streamSecretRef;
  final String protocolHint;
  final String rendererCapability;
  final SourceOrigin origin;
  final int priority;
  final bool enabled;
  final SourceHealth health;
  final DateTime? lastSuccessfulPlaybackAt;
  final DateTime? lastFailedPlaybackAt;
  final String? lastErrorCode;
}

class SourcePolicy {
  const SourcePolicy({
    this.maxAutomaticAttempts = 3,
    this.sameSourceRetries = 2,
    this.connectTimeoutMs = 15000,
    this.backoffMs = const [500, 1500, 4000],
    this.failedCooldownSeconds = 600,
    this.bufferingThresholdMs = 30000,
  });
  final int maxAutomaticAttempts;
  final int sameSourceRetries;
  final int connectTimeoutMs;
  final List<int> backoffMs;
  final int failedCooldownSeconds;
  final int bufferingThresholdMs;
}

class LivePlaybackContext {
  const LivePlaybackContext({
    required this.playlistId,
    required this.logicalChannelId,
    required this.sourceIds,
    required this.automaticFailoverEnabled,
    required this.sourcePolicy,
  });
  final String playlistId;
  final String logicalChannelId;
  final List<String> sourceIds;
  final bool automaticFailoverEnabled;
  final SourcePolicy sourcePolicy;
}

class PlaybackAttemptContext {
  const PlaybackAttemptContext({
    required this.requestGeneration,
    required this.playlistId,
    required this.logicalChannelId,
    required this.sourceId,
    required this.attemptNumber,
    required this.stableMediaIdentity,
  });
  final String requestGeneration;
  final String playlistId;
  final String logicalChannelId;
  final String sourceId;
  final int attemptNumber;
  final String stableMediaIdentity;
}

class LogicalChannel {
  const LogicalChannel({
    required this.channelId,
    required this.displayName,
    required this.normalizedName,
    required this.memberIds,
    required this.sources,
    this.logoUrl,
    this.category,
    this.countryCode,
    this.languages = const [],
    this.favorite = false,
    this.hidden = false,
    this.userOrder,
    this.automaticFailoverEnabled = true,
    this.sourcePolicy = const SourcePolicy(),
    this.lastSuccessfulSourceId,
  });
  final String channelId;
  final String displayName;
  final String normalizedName;
  final String? logoUrl;
  final String? category;
  final String? countryCode;
  final List<String> languages;
  final List<String> memberIds;
  final List<ChannelSourceRecord> sources;
  final bool favorite;
  final bool hidden;
  final int? userOrder;
  final bool automaticFailoverEnabled;
  final SourcePolicy sourcePolicy;
  final String? lastSuccessfulSourceId;
}

class ChannelAssociation {
  const ChannelAssociation({required this.memberIds});
  final List<String> memberIds;
}

class ChannelPreference {
  const ChannelPreference({
    required this.channelId,
    this.favorite = false,
    this.hidden = false,
    this.category,
    this.userOrder,
    this.automaticFailoverEnabled = true,
    this.sourcePolicy = const SourcePolicy(),
    this.lastSuccessfulSourceId,
  });
  final String channelId;
  final bool favorite;
  final bool hidden;
  final String? category;
  final int? userOrder;
  final bool automaticFailoverEnabled;
  final SourcePolicy sourcePolicy;
  final String? lastSuccessfulSourceId;
}

class ChannelWatchRecord {
  const ChannelWatchRecord({required this.channelId, required this.watchedAt});
  final String channelId;
  final DateTime watchedAt;
}

class LiveCatalogState {
  const LiveCatalogState({
    this.schemaVersion = 1,
    this.playlists = const [],
    this.members = const [],
    this.sources = const [],
    this.associations = const [],
    this.preferences = const [],
    this.recentWatches = const [],
    this.logicalIdByMemberId = const {},
  });
  final int schemaVersion;
  final List<PlaylistRecord> playlists;
  final List<ChannelMember> members;
  final List<ChannelSourceRecord> sources;
  final List<ChannelAssociation> associations;
  final List<ChannelPreference> preferences;
  final List<ChannelWatchRecord> recentWatches;
  final Map<String, String> logicalIdByMemberId;
}

class CatalogIssue {
  const CatalogIssue({required this.code, required this.message, this.line});
  final String code;
  final String message;
  final int? line;
}

class UnifiedCatalogSnapshot {
  const UnifiedCatalogSnapshot({
    required this.revision,
    required this.generatedAt,
    required this.playlists,
    required this.channels,
    required this.issues,
  });
  final int revision;
  final DateTime generatedAt;
  final List<PlaylistRecord> playlists;
  final List<LogicalChannel> channels;
  final List<CatalogIssue> issues;
}

class LiveCatalogMigration {
  static LiveCatalogState migrate(String? raw) {
    if (raw == null || raw.isEmpty) return const LiveCatalogState();
    return LiveCatalogStateCodec.decode(raw);
  }

  static String encode(LiveCatalogState state) =>
      LiveCatalogStateCodec.encode(state);
}
```

`LiveCatalogStateCodec` exposes:

```dart
class LiveCatalogStateCodec {
  static LiveCatalogState decode(String raw);
  static String encode(LiveCatalogState state);
}
```

Decoding rules: preflight `schemaVersion` before decoding records; require `schemaVersion == 1`; reject unknown future versions with `FormatException('Unsupported live catalog schema')`; reject malformed JSON or invalid field types; decode a missing `recentWatches` array as empty, a missing `sourcePolicy` as the standard policy, and a missing source `rendererCapability` as `Not Yet Verified` for additive v1 compatibility; accept only the four `RendererSupport` values for `rendererCapability`; decode a missing `streamUrl` as empty only when `streamSecretRef` is non-null and reject it otherwise; never return a silently cleared state for corrupt existing data. Encoding omits `streamUrl` whenever `streamSecretRef` is non-null.

- [ ] **Step 1: Create the fixtures and failing test.**

```dart
import 'dart:convert';
import 'dart:io';

import 'package:ccloud/core/live_catalog_codec.dart';
import 'package:ccloud/core/live_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('absent state migrates to an empty v1 state', () {
    final state = LiveCatalogMigration.migrate(null);
    expect(state.schemaVersion, 1);
    expect(state.playlists, isEmpty);
    expect(state.members, isEmpty);
    expect(state.sources, isEmpty);
  });

  test('v1 fixture round-trips and secret URLs are not serialized', () {
    final raw = File('../Tests/fixtures/migration/catalog-v1.json')
        .readAsStringSync();
    final state = LiveCatalogMigration.migrate(raw);
    final withSecret = LiveCatalogState(
      playlists: state.playlists,
      sources: const [
        ChannelSourceRecord(
          sourceId: 'source:test',
          channelId: 'member:test',
          memberId: 'member:test',
          playlistId: 'builtin:live',
          providerNamespace: 'builtin:ccloud',
          label: 'منبع تست',
          streamSecretRef: 'secret:test',
          protocolHint: 'hls',
          origin: SourceOrigin.playlist,
          priority: 0,
          enabled: true,
          health: SourceHealth.unverified,
        ),
      ],
    );
    final encoded = LiveCatalogMigration.encode(withSecret);
    expect(jsonDecode(encoded)['schemaVersion'], 1);
    expect(encoded, isNot(contains('https://')));
    expect(encoded, isNot(contains('streamUrl')));
    final decoded = LiveCatalogMigration.migrate(encoded);
    expect(decoded.sources.single.streamSecretRef, 'secret:test');
    expect(decoded.sources.single.streamUrl, isEmpty);
    expect(decoded.sources.single.rendererCapability, 'Not Yet Verified');
    final invalidCapability = jsonDecode(encoded) as Map<String, dynamic>;
    (invalidCapability['sources'] as List).first['rendererCapability'] = 'maybe';
    expect(
      () => LiveCatalogMigration.migrate(jsonEncode(invalidCapability)),
      throwsFormatException,
    );
  });

  test('additive v1 preference defaults to the standard source policy', () {
    final raw = '{"schemaVersion":1,"playlists":[],"members":[],"sources":[],"associations":[],"preferences":[{"channelId":"member:test"}],"logicalIdByMemberId":{}}';
    final policy = LiveCatalogMigration.migrate(raw).preferences.single.sourcePolicy;
    expect(policy.maxAutomaticAttempts, 3);
    expect(policy.sameSourceRetries, 2);
    expect(policy.connectTimeoutMs, 15000);
    expect(policy.backoffMs, [500, 1500, 4000]);
    expect(policy.failedCooldownSeconds, 600);
    expect(policy.bufferingThresholdMs, 30000);
  });

  test('future and corrupt states fail closed', () {
    expect(
      () => LiveCatalogMigration.migrate('{"schemaVersion":2}'),
      throwsFormatException,
    );
    expect(
      () => LiveCatalogMigration.migrate('{not-json'),
      throwsFormatException,
    );
  });

  test('legacy preference keys are not rewritten by migration', () {
    final raw = File('../Tests/fixtures/migration/flutter-legacy-prefs.json')
        .readAsStringSync();
    final before = jsonDecode(raw) as Map<String, dynamic>;
    LiveCatalogMigration.migrate(null);
    final after = jsonDecode(raw) as Map<String, dynamic>;
    expect(after, before);
    expect(after.keys, containsAll([
      'ccloud.favorites',
      'ccloud.history',
      'ccloud.appearance',
      'ccloud.preferredQuality',
    ]));
  });
}
```

- [ ] **Step 2: Run the hosted RED check.** In the GitHub `flutter` job, run `flutter test test/live_contracts_test.dart -r expanded`. Expected: compilation fails because `live_contracts.dart` and `live_catalog_codec.dart` do not exist.
- [ ] **Step 3: Implement the contracts and codec exactly as declared.** Serialize enum names, UTC dates, nullable fields, arrays, and `logicalIdByMemberId`; add the secret-reference omission rule.
- [ ] **Step 4: Run the hosted GREEN check.** Run `flutter test test/live_contracts_test.dart -r expanded`, then `flutter analyze`, then the full `flutter test` suite. Expected: all five new tests pass; existing favorites/history/link-health tests remain green.
- [ ] **Step 5: Commit.** `git add flutter_app/lib/core/live_contracts.dart flutter_app/lib/core/live_catalog_codec.dart flutter_app/test/live_contracts_test.dart Tests/fixtures/migration/catalog-v1.json Tests/fixtures/migration/flutter-legacy-prefs.json` and commit `feat: add Dart live catalog contracts`.

## Task B1-S: Swift Contracts, Additive Migration, and Hosted Runner

> **Read the Addendum 2026-11-28 at the end of this document first.** Items 1-5 there supersede parts
> of this task: the canonical timestamp form and Swift's date strategy, `supportedSchemaVersion` as a
> stated member, the `xcrun swiftc -sdk/-target` runner convention, the fixture-path anchor, and the
> countable-proof requirement for the new Swift step.

**Files:**
- Create: `Sources/Core/LiveTVContracts.swift`
- Create: `Sources/Core/LiveTVCatalogCodec.swift`
- Create: `Tests/live-foundation/main.swift`
- Create: `Tests/live-foundation/run.sh`
- Modify: `.github/workflows/ci.yml` only in the `macos-typecheck` job
- Create fixtures: `Tests/fixtures/migration/macos-favorites.json`, `Tests/fixtures/migration/macos-history.json`
- Consume fixture: `Tests/fixtures/migration/catalog-v1.json` from B1-D

**Interfaces consumed:** none.

**Interfaces produced:**

```swift
enum PlaylistSourceType: String, Codable, Sendable {
    case builtIn, remoteUrl, localFile
}

enum PlaylistRefreshStatus: String, Codable, Sendable {
    case idle, refreshing, ready, error
}

enum SourceHealth: String, Codable, Sendable {
    case unverified, available, failed, disabled
}

enum SourceOrigin: String, Codable, Sendable {
    case playlist, user
}

enum RendererSupport: String, Codable, Sendable {
    case supported = "Supported"
    case partiallySupported = "Partially Supported"
    case unsupported = "Unsupported"
    case notYetVerified = "Not Yet Verified"
}

struct PlaylistRecord: Codable, Hashable, Sendable {
    var playlistId: String
    var name: String
    var sourceType: PlaylistSourceType
    var locationRef: String
    var enabled: Bool
    var createdAt: Date
    var lastUpdatedAt: Date?
    var lastSuccessfulRefresh: Date?
    var refreshStatus: PlaylistRefreshStatus
    var lastErrorCode: String?
    var channelCount: Int
    var parsingVersion: Int
}

struct ChannelMember: Codable, Hashable, Sendable {
    var memberId: String
    var playlistId: String
    var providerNamespace: String
    var providerChannelId: String
    var displayName: String
    var normalizedName: String
    var logoUrl: String?
    var group: String?
    var countryCode: String?
    var languages: [String]
    var tvgId: String?
    var ordinal: Int
}

struct ChannelSourceRecord: Codable, Hashable, Sendable {
    var sourceId: String
    var channelId: String
    var memberId: String
    var playlistId: String
    var providerNamespace: String
    var label: String
    var streamUrl: String
    var streamSecretRef: String?
    var protocolHint: String
    var rendererCapability: RendererSupport = .notYetVerified
    var origin: SourceOrigin
    var priority: Int
    var enabled: Bool
    var health: SourceHealth
    var lastSuccessfulPlaybackAt: Date?
    var lastFailedPlaybackAt: Date?
    var lastErrorCode: String?
}

struct SourcePolicy: Codable, Hashable, Sendable {
    var maxAutomaticAttempts: Int
    var sameSourceRetries: Int
    var connectTimeoutMs: Int
    var backoffMs: [Int]
    var failedCooldownSeconds: Int
    var bufferingThresholdMs: Int

    static let standard = SourcePolicy(
        maxAutomaticAttempts: 3,
        sameSourceRetries: 2,
        connectTimeoutMs: 15000,
        backoffMs: [500, 1500, 4000],
        failedCooldownSeconds: 600,
        bufferingThresholdMs: 30000
    )
}

struct LivePlaybackContext: Codable, Hashable, Sendable {
    var playlistId: String
    var logicalChannelId: String
    var sourceIds: [String]
    var automaticFailoverEnabled: Bool
    var sourcePolicy: SourcePolicy
}

struct PlaybackAttemptContext: Hashable, Sendable {
    var requestGeneration: String
    var playlistId: String
    var logicalChannelId: String
    var sourceId: String
    var attemptNumber: Int
    var stableMediaIdentity: String
}

struct LogicalChannel: Codable, Hashable, Sendable {
    var channelId: String
    var displayName: String
    var normalizedName: String
    var logoUrl: String?
    var category: String?
    var countryCode: String?
    var languages: [String]
    var memberIds: [String]
    var sources: [ChannelSourceRecord]
    var favorite: Bool
    var hidden: Bool
    var userOrder: Int?
    var automaticFailoverEnabled: Bool
    var sourcePolicy: SourcePolicy
    var lastSuccessfulSourceId: String?
}

struct ChannelAssociation: Codable, Hashable, Sendable {
    var memberIds: [String]
}

struct ChannelPreference: Codable, Hashable, Sendable {
    var channelId: String
    var favorite: Bool
    var hidden: Bool
    var category: String?
    var userOrder: Int?
    var automaticFailoverEnabled: Bool
    var sourcePolicy: SourcePolicy
    var lastSuccessfulSourceId: String?
}

struct ChannelWatchRecord: Codable, Hashable, Sendable {
    var channelId: String
    var watchedAt: Date
}

struct LiveCatalogState: Codable, Hashable, Sendable {
    var schemaVersion: Int
    var playlists: [PlaylistRecord]
    var members: [ChannelMember]
    var sources: [ChannelSourceRecord]
    var associations: [ChannelAssociation]
    var preferences: [ChannelPreference]
    var recentWatches: [ChannelWatchRecord]
    var logicalIdByMemberId: [String: String]

    static let empty = LiveCatalogState(
        schemaVersion: 1,
        playlists: [],
        members: [],
        sources: [],
        associations: [],
        preferences: [],
        recentWatches: [],
        logicalIdByMemberId: [:]
    )
}

struct CatalogIssue: Codable, Hashable, Sendable {
    var code: String
    var message: String
    var line: Int?
}

struct UnifiedCatalogSnapshot: Codable, Hashable, Sendable {
    var revision: Int
    var generatedAt: Date
    var playlists: [PlaylistRecord]
    var channels: [LogicalChannel]
    var issues: [CatalogIssue]
}

enum LiveCatalogSchemaError: Error {
    case unsupportedVersion
}

enum LiveCatalogMigration {
    static func migrate(_ data: Data?) throws -> LiveCatalogState {
        guard let data else { return .empty }
        return try LiveCatalogStateCodec.decode(data)
    }

    static func encode(_ state: LiveCatalogState) throws -> Data {
        try LiveCatalogStateCodec.encode(state)
    }
}

enum LiveCatalogStateCodec {
    static func decode(_ data: Data) throws -> LiveCatalogState
    static func encode(_ state: LiveCatalogState) throws -> Data
}
```

Use `JSONEncoder.dateEncodingStrategy = .iso8601` and the matching decoder. Preflight `schemaVersion` before decoding records and require version 1. Throw `DecodingError.dataCorrupted` for malformed data and a dedicated `LiveCatalogSchemaError.unsupportedVersion` for future versions. Before typed decoding, normalize only the additive v1 omissions in a copied JSON object: insert `recentWatches: []` when absent, insert `sourcePolicy: SourcePolicy.standard` for every preference whose `sourcePolicy` key is absent, and insert `rendererCapability: "Not Yet Verified"` for every source whose key is absent; reject present values with invalid types or values outside the four `RendererSupport` cases instead of replacing them. Implement `ChannelSourceRecord.init(from:)` and `encode(to:)` in an extension, preserving the memberwise initializer: decode a missing `streamUrl` as empty only when `streamSecretRef` is non-null and throw `dataCorrupted` otherwise; omit the `streamUrl` coding key when `streamSecretRef` exists.

- [ ] **Step 1: Create fixtures, test runner, and failing assertions.** `Tests/live-foundation/run.sh` must contain:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT
swiftc -swift-version 5 -module-name CCloudLiveFoundationTests \
  "$ROOT/Sources/Core/LiveTVContracts.swift" \
  "$ROOT/Sources/Core/LiveTVCatalogCodec.swift" \
  "$ROOT/Tests/live-foundation/main.swift" \
  -o "$BUILD/live-foundation-tests"
"$BUILD/live-foundation-tests"
```

The first `main.swift` assertions must verify: absent data returns `.empty`; the v1 fixture decodes; a preference missing `sourcePolicy` receives `.standard`; a source missing `rendererCapability` receives `.notYetVerified` and an invalid capability value throws; encode/decode preserves all records; a source with `streamSecretRef` encodes without `streamUrl`; schema 2 and malformed data throw; the legacy favorites/history fixture bytes remain unchanged after migration because the migrator never opens or rewrites them.

- [ ] **Step 2: Add the hosted runner to `.github/workflows/ci.yml`.** Add a step named `Run Live TV foundation tests` after `Typecheck Swift sources`, running `chmod +x Tests/live-foundation/run.sh && ./Tests/live-foundation/run.sh`. Expected RED: Swift compilation fails because the two new core files do not exist.
- [ ] **Step 3: Implement the contracts and codec.** Add no playback or UI dependency.
- [ ] **Step 4: Run hosted GREEN checks.** Run `./scripts/typecheck.sh`, `./Tests/live-foundation/run.sh`, and `python3 scripts/version.py check`. Expected: all pass and version identity remains 2.0.0/22.
- [ ] **Step 5: Commit.** Stage only the Swift contract/codec, test runner, fixtures, and workflow; commit `feat: add Swift live catalog contracts`.

## Task B1-J: JavaScript Contracts, Additive Migration, and Hosted Node Tests

> **Read the Addendum 2026-11-28 at the end of this document first.** Items 1-3 and 6 there supersede
> parts of this task: the canonical timestamp form with lenient parsing, `supportedSchemaVersion` as a
> stated member, and the test location `Tests/webos/live_contracts.test.js` driven by the existing
> `node --test Tests/webos/*.test.js` step instead of `webos_app/test/`.

**Files:**
- Create: `webos_app/app/js/playlist_contracts.js`
- Test: `webos_app/test/live_contracts.test.js`
- Modify: `.github/workflows/ci.yml` only in the `webos-static` job
- Create fixture: `Tests/fixtures/migration/webos-legacy-storage.json`
- Consume fixture: `Tests/fixtures/migration/catalog-v1.json` from B1-D

**Interfaces consumed:** none.

**Interfaces produced:**

```javascript
CC.playlistContracts = {
  rendererSupportValues: ['Supported', 'Partially Supported', 'Unsupported', 'Not Yet Verified'],
  emptyState: function () { /* returns the canonical empty v1 object */ },
  decodeState: function (raw) { /* returns LiveCatalogState or throws Error */ },
  encodeState: function (state) { /* returns JSON text or throws Error */ },
  migrate: function (raw) { /* null/empty -> emptyState; otherwise decodeState */ },
  standardSourcePolicy: function () { /* returns the canonical default SourcePolicy */ },
  liveContext: function (playlistId, logicalChannelId, sourceIds, automaticFailoverEnabled, sourcePolicy) {
    /* returns LivePlaybackContext */
  },
  attemptContext: function (requestGeneration, playlistId, logicalChannelId, sourceId, attemptNumber, stableMediaIdentity) {
    /* returns runtime-only PlaybackAttemptContext */
  },
  issue: function (code, message, line) { /* returns CatalogIssue */ },
  snapshot: function (revision, generatedAt, playlists, channels, issues) {
    /* returns UnifiedCatalogSnapshot */
  }
};
```

`standardSourcePolicy()` returns exactly `{maxAutomaticAttempts: 3, sameSourceRetries: 2, connectTimeoutMs: 15000, backoffMs: [500, 1500, 4000], failedCooldownSeconds: 600, bufferingThresholdMs: 30000}`. `emptyState()` returns exactly `{schemaVersion: 1, playlists: [], members: [], sources: [], associations: [], preferences: [], recentWatches: [], logicalIdByMemberId: {}}`. The `liveContext` factory returns the five named fields with a copied `sourceIds` array and copied policy fields. The `attemptContext` factory returns exactly `{requestGeneration, playlistId, logicalChannelId, sourceId, attemptNumber, stableMediaIdentity}` and is never passed to `encodeState`. `issue(code, message, line)` returns `{code: code, message: message, line: line === undefined ? null : line}`. The `snapshot` factory returns those five fields with `generatedAt` as an RFC 3339 UTC string.

The module attaches to `window.CC` without using `let`, `const`, optional chaining, nullish coalescing, or other syntax newer than ES2017. It does not access `localStorage`. `decodeState` preflights schema version 1 and throws on malformed/future data. `encodeState` omits a source's `streamUrl` key and retains `streamSecretRef` when the reference exists. Missing `recentWatches` in an otherwise valid v1 record decodes as an empty array, missing `sourcePolicy` as the standard policy, and missing source `rendererCapability` as `Not Yet Verified` for additive v1 compatibility; new writes always include all three. Accept only `Supported`, `Partially Supported`, `Unsupported`, and `Not Yet Verified` for `rendererCapability`. A missing `streamUrl` decodes as empty only when `streamSecretRef` exists and throws otherwise.

- [ ] **Step 1: Write the failing Node test.** Load the script in a VM with `window: {}` and `console`; assert `migrate(null)` returns schema 1 with seven empty collections/maps as declared above; the v1 fixture round-trips; `attemptContext` returns exactly the six runtime fields and is absent from encoded state; a preference without `sourcePolicy` receives attempts 3, retries 2, timeout 15000, backoff `[500, 1500, 4000]`, cooldown 600, and buffering threshold 30000; a source without `rendererCapability` receives `Not Yet Verified` and an invalid capability throws; a secret-backed source encodes without `streamUrl` and decodes it as `''`; schema 2, malformed JSON, and a missing URL without a secret reference throw; legacy fixture keys remain byte-for-byte unchanged because migration does not write them.
- [ ] **Step 2: Add `node --test webos_app/test/*.test.js` to the hosted `webos-static` job after JavaScript syntax validation.** Expected RED: the new test cannot load `playlist_contracts.js`.
- [ ] **Step 3: Implement the ES2017 module.** Use `JSON.parse`/`JSON.stringify`; do not silently catch parse errors.
- [ ] **Step 4: Run hosted GREEN checks.** Run the Node test step, existing `node --check` validation, webOS JSON/service assertions, and version assertions. Expected: all pass.
- [ ] **Step 5: Commit.** Stage the module, test, fixtures, and workflow; commit `feat: add webOS live catalog contracts`.

## Task B2-D: Dart M3U Parser and Source Registry

**Files:**
- Create: `flutter_app/lib/core/identity_hash.dart`
- Create: `flutter_app/lib/core/playlist_parser.dart`
- Create: `flutter_app/lib/core/source_registry.dart`
- Test: `flutter_app/test/playlist_parser_test.dart`
- Fixtures: all `Tests/fixtures/multi-source/*.m3u*`

**Interfaces consumed:** `LiveCatalogState`, `ChannelMember`, `ChannelSourceRecord`, `SourceHealth`, `SourceOrigin`, `rendererSupportValues`, and `CatalogIssue` from B1-D.

**Interfaces produced:**

```dart
String stableKeyHash(String value);

enum PlaylistFormat { m3uChannelList, hlsMediaManifest, empty, invalid }

class ParsedChannel {
  const ParsedChannel({
    required this.providerChannelId,
    required this.displayName,
    required this.streamUrls,
    required this.line,
    this.logoUrl,
    this.group,
    this.countryCode,
    this.languages = const [],
    this.tvgId,
  });
  final String providerChannelId;
  final String displayName;
  final List<String> streamUrls;
  final int line;
  final String? logoUrl;
  final String? group;
  final String? countryCode;
  final List<String> languages;
  final String? tvgId;
}

class PlaylistParseResult {
  const PlaylistParseResult({
    required this.format,
    required this.channels,
    required this.issues,
    required this.contentHash,
    required this.inputBytes,
    required this.truncated,
  });
  final PlaylistFormat format;
  final List<ParsedChannel> channels;
  final List<CatalogIssue> issues;
  final String contentHash;
  final int inputBytes;
  final bool truncated;
}

PlaylistParseResult parsePlaylist({
  required String playlistId,
  required String text,
  Uri? baseUri,
});

Future<PlaylistParseResult> parsePlaylistAsync({
  required String playlistId,
  required String text,
  Uri? baseUri,
});

class SourceRegistryResult {
  const SourceRegistryResult({
    required this.members,
    required this.sources,
    required this.issues,
  });
  final List<ChannelMember> members;
  final List<ChannelSourceRecord> sources;
  final List<CatalogIssue> issues;
}

SourceRegistryResult registerParsedPlaylist({
  required PlaylistParseResult parsed,
  required String playlistId,
  required String providerNamespace,
});

String? canonicalStreamUrl(String rawUrl);
bool isSensitiveUrl(String rawUrl);
```

Parser behavior: set `contentHash = stableKeyHash(text)` over the exact decoded UTF-8 string bytes and `inputBytes = utf8.encode(text).length`; require `#EXTM3U`; classify `#EXT-X-STREAM-INF` without channel `#EXTINF` as `hlsMediaManifest`; classify header-only input as `empty`; parse `tvg-id`, `tvg-logo`, `group-title`, `tvg-language`, and the final comma-delimited display name; strip a country suffix from provider IDs exactly as the existing parser does; merge repeated nonempty provider IDs in first-seen order; keep missing-ID entries separate; retain original provider ID in `tvgId`; apply all input limits. Resolve relative stream URLs only when `baseUri` is HTTP(S); otherwise emit `invalidUrl`.

Registry behavior: validate HTTP(S), reject fragments from canonical URLs, lowercase only scheme/host, remove default ports, preserve path/query case, infer `protocolHint` from the canonical path extension (`.m3u8` → `hls`, `.mpd` → `dash`, `.mp4` → `mp4`, otherwise `unknown`), deduplicate canonical URLs within a member, assign priority by first-seen order, set each new source's `channelId` to its `memberId` and `origin` to `playlist`, label the first source `منبع اصلی` and later sources `منبع N` with Persian digits, mark all new sources `unverified` with `rendererCapability = Not Yet Verified` and no success/failure timestamps, and never mark a source online or renderer-supported without playback/renderer evidence. Detect sensitive userinfo and query keys `token`, `key`, `password`, `signature`, `auth`, and `credential` case-insensitively.

- [ ] **Step 1: Write failing tests.** The test must load the shared fixtures and assert the values below. Add an async test asserting that `await parsePlaylistAsync(playlistId: 'playlist:valid', text: validText)` has the same format, channel fields, issues, `contentHash`, `inputBytes`, and `truncated` value as `parsePlaylist` for `validText`:

```dart
final validText = File('../Tests/fixtures/multi-source/valid.m3u').readAsStringSync();
final valid = parsePlaylist(
  playlistId: 'playlist:valid',
  text: validText,
);
expect(valid.contentHash, stableKeyHash(validText));
expect(valid.inputBytes, utf8.encode(validText).length);
expect(valid.format, PlaylistFormat.m3uChannelList);
expect(valid.channels.length, 3);
expect(valid.channels.first.providerChannelId, 'PressTV');
expect(valid.channels.first.countryCode, 'IR');
expect(valid.channels.first.streamUrls.length, 2);
expect(valid.channels.first.logoUrl, 'https://img.example/press.png');
expect(valid.channels.last.languages, isEmpty);

final empty = parsePlaylist(
  playlistId: 'playlist:empty',
  text: File('../Tests/fixtures/multi-source/empty.m3u').readAsStringSync(),
);
expect(empty.format, PlaylistFormat.empty);
expect(empty.channels, isEmpty);
expect(empty.issues, isEmpty);

final hls = parsePlaylist(
  playlistId: 'playlist:hls',
  text: File('../Tests/fixtures/multi-source/hls-master.m3u8').readAsStringSync(),
);
expect(hls.format, PlaylistFormat.hlsMediaManifest);
expect(hls.issues.single.code, 'unsupportedMediaManifest');

final malformed = parsePlaylist(
  playlistId: 'playlist:malformed',
  text: File('../Tests/fixtures/multi-source/malformed.m3u').readAsStringSync(),
);
expect(malformed.channels.single.displayName, 'Good TV');
expect(malformed.issues.map((i) => i.code), containsAll([
  'missingName', 'missingStream', 'malformedEntry', 'invalidUrl',
]));

final registry = registerParsedPlaylist(
  parsed: parsePlaylist(
    playlistId: 'playlist:duplicates',
    text: File('../Tests/fixtures/multi-source/duplicates.m3u').readAsStringSync(),
  ),
  playlistId: 'playlist:duplicates',
  providerNamespace: 'fixture:provider',
);
expect(registry.members.length, 2);
expect(registry.sources.length, 3);
expect(registry.sources.map((s) => s.priority), [0, 1, 0]);
expect(registry.sources.every((s) => s.health == SourceHealth.unverified), isTrue);
expect(registry.sources.every((s) => s.rendererCapability == 'Not Yet Verified'), isTrue);
expect(registry.sources.every((s) => !s.sourceId.contains('https://')), isTrue);
expect(stableKeyHash('same'), stableKeyHash('same'));
expect(stableKeyHash('same') == stableKeyHash('different'), isFalse);
expect(stableKeyHash('same'), matches(RegExp(r'^[0-9a-f]{32}$')));

final oversized = '#EXTM3U\n' + List.generate(50001, (i) =>
  '#EXTINF:-1 tvg-id="C$i.ir",Channel $i\nhttps://cdn.example/$i.m3u8\n'
).join();
final limited = parsePlaylist(playlistId: 'playlist:large', text: oversized);
expect(limited.channels.length, 50000);
expect(limited.truncated, isTrue);
expect(limited.issues.any((i) => i.code == 'limitExceeded'), isTrue);
```

- [ ] **Step 2: Run hosted RED.** Run `flutter test test/playlist_parser_test.dart -r expanded`. Expected: missing imports/undefined functions.
- [ ] **Step 3: Implement parser, hash, and registry.** Reuse `liveNameKey` and `m3uDisplayName` from `live_catalog.dart`; do not duplicate their normalization behavior. Implement `parsePlaylistAsync` as a top-level `compute` adapter over the same synchronous parser so playlist decoding/parsing never runs on the UI isolate; both entry points must return equal results for identical input.
- [ ] **Step 4: Run hosted GREEN.** Run the targeted test, `flutter analyze`, and full `flutter test`. Expected: valid/malformed/HLS/duplicate assertions pass; existing `live_catalog_test.dart` remains green.
- [ ] **Step 5: Commit.** Stage only B2-D files; commit `feat: add Dart playlist parser and source registry`.

## Task B2-S: Swift M3U Parser and Source Registry

**Files:**
- Create: `Sources/Core/LiveTVIdentityHash.swift`
- Create: `Sources/Core/LiveTVPlaylistParser.swift`
- Create: `Sources/Core/LiveTVSourceRegistry.swift`
- Modify: `Tests/live-foundation/main.swift`
- Modify: `Tests/live-foundation/run.sh`
- Consume fixtures: `Tests/fixtures/multi-source/*.m3u*` from B2-D

**Interfaces consumed:** B1-S contracts.

**Interfaces produced:**

```swift
func stableKeyHash(_ value: String) -> String

enum PlaylistFormat: String, Codable, Sendable {
    case m3uChannelList, hlsMediaManifest, empty, invalid
}

struct ParsedChannel: Sendable {
    var providerChannelId: String
    var displayName: String
    var streamUrls: [String]
    var line: Int
    var logoUrl: String?
    var group: String?
    var countryCode: String?
    var languages: [String]
    var tvgId: String?
}

struct PlaylistParseResult: Sendable {
    var format: PlaylistFormat
    var channels: [ParsedChannel]
    var issues: [CatalogIssue]
    var contentHash: String
    var inputBytes: Int
    var truncated: Bool
}

func parsePlaylist(
    playlistId: String,
    text: String,
    baseUri: URL? = nil
) -> PlaylistParseResult

struct SourceRegistryResult: Sendable {
    var members: [ChannelMember]
    var sources: [ChannelSourceRecord]
    var issues: [CatalogIssue]
}

func registerParsedPlaylist(
    parsed: PlaylistParseResult,
    playlistId: String,
    providerNamespace: String
) -> SourceRegistryResult

func canonicalStreamURL(_ rawUrl: String) -> String?
func isSensitiveURL(_ rawUrl: String) -> Bool
```

- [ ] **Step 1: Extend the hosted foundation test with these exact assertions:** `valid.m3u` is `m3uChannelList` with 3 channels, `contentHash == stableKeyHash(validText)`, and `inputBytes == Data(validText.utf8).count`; first ID `PressTV`, country `IR`, 2 URLs, and the expected logo; last channel has no languages. `empty.m3u` is `empty` with no channels or issues. `hls-master.m3u8` is `hlsMediaManifest` with one `unsupportedMediaManifest` issue. `malformed.m3u` retains only `Good TV` and includes `missingName`, `missingStream`, `malformedEntry`, and `invalidUrl`. `duplicates.m3u` produces 2 members/3 sources with priorities `[0, 1, 0]`, all unverified with `.notYetVerified` renderer capability. The hash is deterministic, differs for `same`/`different`, and matches 32 lowercase hex characters. A generated 50,001-entry playlist retains 50,000 channels, sets `truncated`, and emits `limitExceeded`. Add the three new Swift files, `Sources/Core/LiveTVM3UClient.swift`, `Sources/Core/LiveTVModels.swift`, `Sources/Core/Models.swift`, and `Sources/Core/PersianNumber.swift` to `run.sh`; the client/model sources supply `LiveTVNameKey` and `LiveTVChannel`, their shared models supply `APIError`/`MediaSource`/`PlaybackRequest`, and no network or playback method is invoked. Expected RED: missing symbols.
- [ ] **Step 2: Implement the parser and registry.** Reuse `LiveTVNameKey.key`; preserve the existing built-in parser untouched.
- [ ] **Step 3: Run hosted GREEN.** Run `./scripts/typecheck.sh` and `./Tests/live-foundation/run.sh`. Expected: all B1-S and B2-S assertions pass.
- [ ] **Step 4: Commit.** Stage only B2-S files; commit `feat: add Swift playlist parser and source registry`.

## Task B2-J: JavaScript M3U Parser and Source Registry

**Files:**
- Create: `webos_app/app/js/identity_hash.js`
- Create: `webos_app/app/js/playlist_parser.js`
- Create: `webos_app/app/js/source_registry.js`
- Test: `webos_app/test/playlist_parser.test.js`
- Consume fixtures: `Tests/fixtures/multi-source/*.m3u*` from B2-D

**Interfaces consumed:** `CC.playlistContracts` from B1-J.

**Interfaces produced:**

```javascript
CC.identityHash = function (value) { /* 32 lowercase hex characters */ };

CC.playlistParser = {
  parse: function (text, options) {
    // options = { playlistId: String, baseUri: String|null }
    // returns { format, channels, issues, contentHash, inputBytes, truncated }
  },
  parseAsync: function (text, options) {
    // Same options/result as parse; returns Promise<result>.
    // Yield to the event loop after every 2,000 processed lines.
  }
};

CC.sourceRegistry = {
  register: function (parsed, options) {
    // options = { playlistId: String, providerNamespace: String }
    // returns { members, sources, issues }
  },
  canonicalUrl: function (rawUrl) { /* String|null */ },
  isSensitiveUrl: function (rawUrl) { /* Boolean */ }
};
```

- [ ] **Step 1: Add Node fixture tests asserting the exact B2-S values: valid 3-channel parse and metadata with `contentHash == CC.identityHash(validText)` and `inputBytes == new TextEncoder().encode(validText).length`; `parseAsync(validText, {playlistId: 'playlist:valid', baseUri: null})` resolves to the same result as `parse`; empty fixture yields `empty` with no channels/issues; one HLS-manifest issue; malformed fixture retains only `Good TV` with all four expected issue codes; duplicates yield 2 members/3 sources with priorities `[0, 1, 0]`, unverified health, and `Not Yet Verified` renderer capability; deterministic 32-hex hash; and the 50,001-entry truncation to 50,000 with `limitExceeded`.** Expected RED: modules are absent.
- [ ] **Step 2: Implement ES2017 parser/registry modules.** Do not use `URL` if its webOS behavior would reject a valid HTTP(S) playlist URL; use a small explicit parser and the same canonicalization rules as Dart/Swift. `parse` and `parseAsync` share the same per-line parser and result assembly; `parseAsync` uses a timer yield every 2,000 processed lines so a permitted 10 MiB input does not monopolize the webOS UI thread, and both entry points return equal results for identical input.
- [ ] **Step 3: Run hosted GREEN.** Run `node --test webos_app/test/*.test.js`, all `node --check` checks, and webOS manifest assertions. Expected: all pass.
- [ ] **Step 4: Commit.** Stage only B2-J files; commit `feat: add webOS playlist parser and source registry`.

## Task B3-D: Dart Channel Identity and Unified Catalog

**Files:**
- Create: `flutter_app/lib/core/channel_identity.dart`
- Create: `flutter_app/lib/core/unified_catalog.dart`
- Create: `flutter_app/lib/core/builtin_catalog_adapter.dart`
- Test: `flutter_app/test/channel_identity_test.dart`

**Interfaces consumed:** B1-D and B2-D.

**Interfaces produced:**

```dart
enum MatchEvidence {
  exactProviderId,
  exactNameCountryLogo,
  exactNameCountry,
  exactNameLogo,
  exactNameOnly,
}

enum ChannelIdentityErrorCode {
  fewerThanTwoMembers,
  unknownMember,
  duplicateMember,
  memberAssociatedElsewhere,
  unknownPreferredLogicalChannel,
}

class ChannelMatchCandidate {
  const ChannelMatchCandidate({
    required this.leftMemberId,
    required this.rightMemberId,
    required this.score,
    required this.evidence,
    required this.ambiguous,
  });
  final String leftMemberId;
  final String rightMemberId;
  final int score;
  final MatchEvidence evidence;
  final bool ambiguous;
}

ChannelMatchCandidate? findChannelCandidate(
  ChannelMember left,
  ChannelMember right,
);

LiveCatalogState associateChannels({
  required LiveCatalogState state,
  required List<String> memberIds,
  required String preferredLogicalId,
});

LiveCatalogState separateChannel({
  required LiveCatalogState state,
  required String memberId,
});

List<LogicalChannel> buildUnifiedChannels(LiveCatalogState state);

RegisteredBuiltInCatalog registerBuiltInChannels({
  required List<LiveTvChannel> channels,
  required String playlistId,
  required String providerNamespace,
});

class RegisteredBuiltInCatalog {
  const RegisteredBuiltInCatalog({
    required this.members,
    required this.sources,
    required this.channels,
  });
  final List<ChannelMember> members;
  final List<ChannelSourceRecord> sources;
  final List<LiveTvChannel> channels;
}
```

Candidate scores: exact provider ID plus matching country = 95; exact provider ID alone = 90; provider-ID equality requires both `providerNamespace` and `providerChannelId` to match, so equal raw IDs from different namespaces are not exact-provider evidence; exact normalized name/country/logo = 85; name/country = 75; name/logo = 70; name only = 50. A missing provider ID never produces an exact-provider candidate. Any candidate below 85 or with conflicting provider IDs/countries is ambiguous. Candidates are returned for UI only; `buildUnifiedChannels` never applies them. Invalid association input throws `ArgumentError('ChannelIdentityError.<code>')` using the declared codes: fewer than two distinct IDs, an unknown member, a duplicate member, a member already associated outside the selected logical channel, or a preferred logical ID absent from `logicalIdByMemberId`. Validation completes before any state mutation.

`associateChannels` requires at least two existing distinct members, rejects members already associated outside the selected logical channel, moves their sources to `preferredLogicalId`, keeps the preferred channel's existing member first and appends newly associated members in user-supplied order, records one explicit association, and preserves the preferred channel's favorite/hidden/category/order/automatic-failover/source-policy/last-successful-source preferences. `separateChannel` removes one member from its association and assigns the separated branch the canonical logical ID. `buildUnifiedChannels` includes only enabled playlists, retains disabled source records so they can be managed and re-enabled, applies hidden/favorite/category/order/automatic-failover/source-policy/last-successful-source preferences, and sorts sources by priority then `sourceId`. Playback adapters consume only sources whose `enabled` value is true.

The built-in adapter must not add channels or alter the input list. It assigns every existing channel/member to the supplied built-in playlist and every existing URL to a source with `origin = playlist`, `health = unverified`, and `rendererCapability = Not Yet Verified`. It does not invent per-URL Famelack/iptv-org provenance that the current model does not retain.

- [ ] **Step 1: Write failing identity tests.** Assertions must include:
  - identical namespaced provider IDs in different playlists remain two logical channels, and equal raw IDs in different namespaces are not exact-provider evidence;
  - identical names without provider IDs produce a candidate but remain separate;
  - conflicting provider IDs produce an ambiguous candidate and never merge;
  - explicit association preserves source IDs and priority and changes only logical ownership;
  - separation produces two logical channels and no source ID changes;
  - changing a stream URL creates a new source ID while the member/logical ID remains stable;
  - the fixed Iran adapter returns exactly the Famelack rows supplied and never an iptv-org-only row;
  - disabled playlists are omitted, while a disabled source remains manageable but is never eligible for playback;
  - persisted last-successful-source preference is copied to its logical channel;
  - each invalid association code throws before mutation;
  - no function automatically mutates associations from `findChannelCandidate`.
- [ ] **Step 2: Run hosted RED.** Run `flutter test test/channel_identity_test.dart -r expanded`. Expected: missing modules.
- [ ] **Step 3: Implement identity and catalog logic.** Keep all functions pure; no network, UI, or storage access.
- [ ] **Step 4: Run hosted GREEN.** Run the targeted test, `flutter analyze`, and full `flutter test`. Expected: all pass, including the existing Iran merge suite.
- [ ] **Step 5: Commit.** Stage only B3-D files; commit `feat: add Dart logical channel resolution`.

## Task B3-S: Swift Channel Identity and Unified Catalog

**Files:**
- Create: `Sources/Core/LiveTVChannelIdentity.swift`
- Create: `Sources/Core/UnifiedLiveCatalog.swift`
- Create: `Sources/Core/BuiltInLiveCatalogAdapter.swift`
- Modify: `Tests/live-foundation/main.swift`
- Modify: `Tests/live-foundation/run.sh`

**Interfaces consumed:** B1-S and B2-S.

**Interfaces produced:**

```swift
enum MatchEvidence: String, Sendable {
    case exactProviderId, exactNameCountryLogo, exactNameCountry, exactNameLogo, exactNameOnly
}

enum ChannelIdentityError: Error {
    case fewerThanTwoMembers
    case unknownMember
    case duplicateMember
    case memberAssociatedElsewhere
    case unknownPreferredLogicalChannel
}

struct ChannelMatchCandidate: Sendable {
    var leftMemberId: String
    var rightMemberId: String
    var score: Int
    var evidence: MatchEvidence
    var ambiguous: Bool
}

func findChannelCandidate(
    _ left: ChannelMember,
    _ right: ChannelMember
) -> ChannelMatchCandidate?

func associateChannels(
    _ state: LiveCatalogState,
    memberIds: [String],
    preferredLogicalId: String
) throws -> LiveCatalogState

func separateChannel(
    _ state: LiveCatalogState,
    memberId: String
) throws -> LiveCatalogState

func buildUnifiedChannels(_ state: LiveCatalogState) -> [LogicalChannel]

struct RegisteredBuiltInCatalog: Sendable {
    var members: [ChannelMember]
    var sources: [ChannelSourceRecord]
    var channels: [LiveTVChannel]
}

func registerBuiltInChannels(
    _ channels: [LiveTVChannel],
    playlistId: String,
    providerNamespace: String
) -> RegisteredBuiltInCatalog
```

- [ ] **Step 1: Add these exact Swift assertions:** identical namespaced provider IDs across playlists stay separate and equal raw IDs in different namespaces are not exact evidence; identical missing-ID names yield a candidate but stay separate; conflicting provider IDs yield an ambiguous candidate and never merge; explicit association preserves source IDs/priorities and changes logical ownership; separation yields two channels without source-ID changes; a URL change changes only the source ID; the fixed adapter returns exactly the supplied Famelack rows and no iptv-org-only row; disabled playlists are omitted and disabled sources remain manageable but ineligible for playback; the last-successful-source preference is preserved; each declared `ChannelIdentityError` is thrown before mutation; candidate lookup never mutates associations. Add the three new files to `run.sh` and retain the B2-S `LiveTVM3UClient.swift`, `LiveTVModels.swift`, `Models.swift`, and `PersianNumber.swift` dependencies. Expected RED: missing symbols.
- [ ] **Step 2: Implement pure Swift identity/catalog functions.** Validate the complete member set and preferred logical ID before mutation, throw the matching declared `ChannelIdentityError`, and never auto-associate.
- [ ] **Step 3: Run hosted GREEN.** Run `./scripts/typecheck.sh` and `./Tests/live-foundation/run.sh`. Expected: all foundation assertions pass.
- [ ] **Step 4: Commit.** Stage only B3-S files; commit `feat: add Swift logical channel resolution`.

## Task B3-J: JavaScript Channel Identity and Unified Catalog

**Files:**
- Create: `webos_app/app/js/channel_identity.js`
- Create: `webos_app/app/js/unified_catalog.js`
- Create: `webos_app/app/js/builtin_catalog_adapter.js`
- Test: `webos_app/test/channel_identity.test.js`

**Interfaces consumed:** B1-J and B2-J.

**Interfaces produced:**

```javascript
CC.channelIdentity = {
  findCandidate: function (left, right) { /* ChannelMatchCandidate|null */ },
  associate: function (state, memberIds, preferredLogicalId) { /* LiveCatalogState */ },
  separate: function (state, memberId) { /* LiveCatalogState */ }
};

CC.unifiedCatalog = {
  build: function (state) { /* [LogicalChannel] */ },
  registerBuiltIn: function (channels, options) {
    // options = { playlistId, providerNamespace }
    // returns { members, sources, channels }
  }
};
```

- [ ] **Step 1: Add Node assertions for all eleven B3-S cases: cross-playlist namespaced-provider-ID separation and cross-namespace non-equality, missing-ID candidate without merge, conflicting-ID ambiguity, association ownership-only change, separation without source-ID changes, URL-only source-ID change, exact fixed-adapter rows, disabled playlist omission with disabled-source management/playback exclusion, last-successful-source preference preservation, all five invalid-association error codes before mutation, and candidate lookup purity.** Expected RED: modules absent.
- [ ] **Step 2: Implement pure ES2017 functions.** `associate` throws `Error('ChannelIdentityError.<code>')` for the five declared cases after validating the complete input and before mutation; it never merges from a candidate.
- [ ] **Step 3: Run hosted GREEN.** Run `node --test webos_app/test/*.test.js`, syntax checks, and manifest checks.
- [ ] **Step 4: Commit.** Stage only B3-J files; commit `feat: add webOS logical channel resolution`.

## Task B4-D: Flutter Playlist Repository and Live TV Integration

**Files:**
- Create: `flutter_app/lib/core/playlist_secret_store.dart`
- Create: `flutter_app/lib/core/playlist_repository.dart`
- Create: `flutter_app/lib/core/unified_live_catalog.dart`
- Create: `flutter_app/lib/screens/playlist_manager_screen.dart`
- Modify: `flutter_app/lib/screens/live_screen.dart`
- Modify: `flutter_app/lib/core/models.dart`
- Modify: `flutter_app/lib/core/live_catalog.dart`
- Modify: `flutter_app/pubspec.yaml`
- Modify: `flutter_app/pubspec.lock`
- Test: `flutter_app/test/playlist_repository_test.dart`
- Test: `flutter_app/test/playlist_manager_screen_test.dart`

**Interfaces consumed:** all B1-D/B2-D/B3-D interfaces; existing `LiveCatalog`, `LiveTvCountry`, `LiveTvChannel`, and `PlayerArgs.forChannel`.

**Interfaces produced:**

```dart
class PlaylistPayload {
  const PlaylistPayload({
    required this.text,
    this.etag,
    this.lastModified,
    this.notModified = false,
  });
  final String text;
  final String? etag;
  final String? lastModified;
  final bool notModified;
}

abstract class PlaylistLoader {
  Future<PlaylistPayload> load(
    PlaylistRecord record, {
    String? etag,
    String? lastModified,
  });
}

abstract class PlaylistSecretStore {
  Future<String> put(String value);
  Future<String?> get(String ref);
  Future<void> delete(String ref);
}

abstract class BuiltInCatalogLoading {
  Future<List<LiveTvCountry>> countries({bool force = false});
  Future<List<LiveTvChannel>> channels(
    LiveTvCountry country, {
    bool force = false,
  });
}

class LiveCatalogBuiltInAdapter implements BuiltInCatalogLoading {
  LiveCatalogBuiltInAdapter(this.catalog);
  final LiveCatalog catalog;

  @override
  Future<List<LiveTvCountry>> countries({bool force = false}) =>
      catalog.countries(force: force);

  @override
  Future<List<LiveTvChannel>> channels(
    LiveTvCountry country, {
    bool force = false,
  }) => catalog.channels(country, force: force);
}

class PlaylistRepository {
  PlaylistRepository({
    required this.stateStore,
    required this.secretStore,
    required this.loader,
    required this.builtInCatalog,
  });
  final LiveCatalogStateStore stateStore;
  final PlaylistSecretStore secretStore;
  final PlaylistLoader loader;
  final BuiltInCatalogLoading builtInCatalog;

  Future<List<PlaylistRecord>> records();
  Future<PlaylistRecord> addRemote({required String name, required String url});
  Future<PlaylistRecord> importLocal({
    required String name,
    required String text,
    required String locationRef,
  });
  Future<void> rename({required String playlistId, required String name});
  Future<void> setEnabled({required String playlistId, required bool enabled});
  Future<PlaylistRefreshResult> refresh(String playlistId, {bool force = false});
  Future<ChannelSourceRecord> addUserSource({
    required String channelId,
    required String memberId,
    required String label,
    required String url,
  });
  Future<void> reorderSources({
    required String channelId,
    required List<String> sourceIds,
  });
  Future<void> setSourceEnabled({
    required String sourceId,
    required bool enabled,
  });
  Future<void> setAutomaticFailover({
    required String channelId,
    required bool enabled,
  });
  Future<void> setSourcePolicy({
    required String channelId,
    required SourcePolicy policy,
  });
  Future<void> associateChannels({
    required List<String> memberIds,
    required String preferredLogicalId,
  });
  Future<void> separateChannel(String memberId);
  Future<void> setFavorite({required String channelId, required bool favorite});
  Future<void> setHidden({required String channelId, required bool hidden});
  Future<void> setCategory({required String channelId, String? category});
  Future<void> setUserOrder({required String channelId, int? order});
  Future<void> recordSourceSuccess(String sourceId, DateTime at);
  Future<void> setRendererCapability({
    required String sourceId,
    required String capability,
  });
  Future<void> recordSourceFailure({
    required String sourceId,
    required DateTime at,
    required String errorCode,
  });
  Future<void> recordChannelWatch(String channelId, DateTime at);
  Future<void> remove(String playlistId);
  Future<List<LiveTvChannel>> channelsForCountry(
    LiveTvCountry country, {
    bool force = false,
  });
  Future<UnifiedCatalogSnapshot> snapshot({bool force = false});
}

class PlaylistRefreshResult {
  const PlaylistRefreshResult({
    required this.record,
    required this.issues,
    required this.usedCachedSnapshot,
  });
  final PlaylistRecord record;
  final List<CatalogIssue> issues;
  final bool usedCachedSnapshot;
}

abstract class LiveCatalogStateStore {
  Future<LiveCatalogState?> load();
  Future<void> save(LiveCatalogState state);
}

class UnifiedLiveCatalog {
  UnifiedLiveCatalog(this.repository);
  final PlaylistRepository repository;
  Future<LiveTvCountry> importedCountry();
  Future<List<LiveTvChannel>> channelsForImportedCountry();
  Future<List<LiveTvChannel>> channelsForCountry(
    LiveTvCountry country, {
    bool force = false,
  });
}
```

Implementation requirements:

- Add `file_picker` and `flutter_secure_storage` only after a GitHub-hosted dependency/license check records the resolved versions and transitive licenses, confirms Android, Android TV, and Windows compatibility, and records the resolved `flutter` test/analyze result. This plan targets the confirmed current `file_picker` 13.4.1 static API. The dependency task must declare `file_picker: ^13.4.1` only if that hosted gate confirms the exact resolved version and the calls below; a resolver/API mismatch stops B4-D before implementation and requires an explicit plan revision, not an invented substitute.
- Use the following exact `file_picker` calls. `pickFiles` returns `Future<List<PlatformFile>>`; an empty list means cancellation, and the selected file's bytes come from `await pickedFile.readAsBytes()`. `pickDirectory` returns `Future<Uri?>`. Decode playlist bytes as UTF-8 strictly before `importLocal`. Never request broad storage permission. If Android TV exposes no usable picker, show `localAccessUnavailable` and do not simulate selection.

```dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

final List<PlatformFile> playlistFiles = await FilePicker.pickFiles(
  type: FileType.custom,
  allowedExtensions: ['m3u', 'm3u8'],
  dialogTitle: 'انتخاب فهرست پخش',
);
if (playlistFiles.isNotEmpty) {
  final PlatformFile pickedFile = playlistFiles.first;
  final Uint8List bytes = await pickedFile.readAsBytes();
  final String text = utf8.decode(bytes);
}

final Uri? subtitleDirectory = await FilePicker.pickDirectory(
  dialogTitle: 'انتخاب پوشهٔ زیرنویس',
);
```

Official references checked on 2026-11-25: <https://pub.dev/packages/file_picker/versions/13.4.1>, <https://pub.dev/documentation/file_picker/latest/file_picker/FilePicker/pickFiles.html>, and <https://pub.dev/documentation/file_picker/latest/file_picker/FilePicker/pickDirectory.html>. These establish the proposed API, not an installed dependency; the hosted resolver gate remains authoritative.

- Implement `FlutterPlaylistSecretStore` over `flutter_secure_storage`; references are random opaque IDs. Reject credential-bearing remote URLs when secure storage is unavailable.
- Store state in a private app-support file through `path_provider`, using the B1 codec and atomic replacement. Keep the legacy SharedPreferences keys untouched.
- Remote loader uses HTTP(S), a 25-second timeout, strict UTF-8 decoding without replacement characters, and the repository's cached ETag/Last-Modified validators through the declared loader arguments. A 304 response returns `PlaylistPayload(text: '', etag: cachedEtag, lastModified: cachedLastModified, notModified: true)`; the repository reuses its last good parsed snapshot and returns `usedCachedSnapshot = true`. A 304 without a cached snapshot is a `staleRefresh` failure that retains any last good state. Use a 15-minute freshness window and one in-flight future per playlist. Cache parse results by `playlistId`, parsed `contentHash`, and `parsingVersion`; on a hash/version match compare the exact decoded text with the in-memory snapshot before reuse, and reparse on any mismatch so a non-cryptographic hash collision cannot reuse the wrong parse. Decode and parse every uncached remote/local payload through `parsePlaylistAsync`, keeping this work off the UI isolate. A refresh whose playlist generation changed while it was in flight is discarded with `staleRefresh`. The loader never probes stream URLs.
- `addRemote` creates the record, stores the URL securely when sensitive, and performs the first refresh. `importLocal` persists only the picker/bookmark reference and parsed catalog, and keeps the imported text as an in-memory parse-cache snapshot for that repository instance; a later refresh reuses that snapshot unless a newly authorized file read is available, while access loss retains the last good catalog with `localAccessUnavailable`.
- Refresh sets `refreshStatus = refreshing` before loading and `lastUpdatedAt` on every completed attempt. A valid `empty` playlist is a successful zero-channel refresh: it sets `ready`, clears `lastErrorCode`, updates `lastSuccessfulRefresh`/`channelCount = 0`, clears that playlist's members and all sources attached to them, deletes their secret references, and dissolves associations that become single-member. A successful partial parse sets `ready`, clears `lastErrorCode`, updates `lastSuccessfulRefresh`, updates valid members, and records issues. An `invalid` parse or nonempty malformed playlist with zero valid channels is a failure: it retains the last good members/count, sets `error`, stores `lastErrorCode`, and surfaces the error. On a successful nonempty refresh, reconcile by `sourceId`: update metadata for unchanged IDs, append new IDs in first-seen order after the member's current maximum priority (reusing an existing user-origin source on an exact canonical URL match instead of creating a duplicate), and remove missing `origin = playlist` sources together with their secret references; never remove `origin = user` sources. Refreshing never resets priorities, enabled flags, favorites, hidden state, associations, or source health for unchanged source IDs.
- `addUserSource` validates the URL, assigns `"source:" + stableKeyHash(memberId + "\nuser\n" + canonicalStreamUrl)`, sets `origin = user`, `health = unverified`, and `rendererCapability = Not Yet Verified`, stores sensitive URLs through the secret store, appends the source, and preserves existing priorities. An exact canonical URL already present for that member is returned with its existing source ID/label rather than duplicated. `reorderSources` requires the complete current source-ID set exactly once and rewrites priorities from zero. `setSourceEnabled` sets `enabled = false` and `health = disabled` when false; re-enabling sets `enabled = true` and `health = unverified` while retaining historical success/failure timestamps. `setAutomaticFailover`, `setSourcePolicy`, `setFavorite`, `setHidden`, `setCategory`, and `setUserOrder` update only that logical channel's preference. `setSourcePolicy` accepts only 1–10 automatic attempts, 0–5 same-source retries, a 1,000–60,000 ms connection timeout, 1–5 nonnegative backoff values no greater than 30,000 ms, a 0–86,400-second cooldown, and a 1,000–120,000 ms buffering threshold; invalid values throw without changing state. `associateChannels`/`separateChannel` delegate to the B3 pure functions and atomically persist the result. `recordChannelWatch` keeps the newest 50 distinct channel IDs ordered by time.
- `setRendererCapability` requires an existing enabled source and one of the four exact `RendererSupport` strings, updates only `rendererCapability`, and persists atomically; callers must supply actual playback/renderer evidence. `recordSourceSuccess` requires an existing enabled source, sets `available`/`rendererCapability = Supported`/`lastSuccessfulPlaybackAt`, clears failure time/code, and sets its logical channel preference's `lastSuccessfulSourceId`. `recordSourceFailure` requires an existing enabled source and a URL-free safe error code, sets `failed`/`lastFailedPlaybackAt`/`lastErrorCode`, and never changes priority, ownership, or the historical `lastSuccessfulSourceId`. Late results for removed or disabled sources are ignored.
- Ensure the `builtin:live` playlist record exists exactly once before the first country load or snapshot. `channelsForCountry(country, force:)` loads only the requested country through `builtInCatalog.channels`, registers it through the unchanged B3 built-in adapter, and returns the adapted unified logical rows that have a `builtin:live` member from that country, ordered by the first such member's `ordinal`; it does not enumerate unrelated countries. A disabled `builtin:live` record returns an empty list. A load failure with a previous successful country cache returns those cached adapted rows and records safe `catalogUnavailable` metadata; without a cache it throws the existing safe catalog error. When `builtin:live` is enabled, snapshot loading calls `builtInCatalog.countries(force: force)`, then loads each country's channels with concurrency capped at four, registers them through the same adapter, and caches successful per-country results. A country failure records safe `catalogUnavailable` metadata, retains that country's previous cache when present, and never drops imported channels or the fixed Iran rows; the Iran loader still adds no iptv-org-only channel. The record's channel count is the total registered built-in logical-channel count. The manager permits refresh/enable-disable but disables rename, removal, and source/location editing for `builtin:live`; repository rename/remove calls also reject that ID. `refresh('builtin:live')` runs the built-in load with `force = true` rather than the M3U parser, becomes `ready` when at least one country loads, and otherwise becomes `error` while retaining any previous built-in cache and last-success timestamp. Define `LiveCatalogBuiltInAdapter` in `unified_live_catalog.dart` and construct the production repository with `LiveCatalogBuiltInAdapter(LiveCatalog.instance)`; repository tests inject a fake `BuiltInCatalogLoading` and never invoke the network-backed catalog.
- Removal deletes only that playlist's members/sources and their secret references. Associations that become single-member are removed; preferences for remaining logical channels are retained.
- `channelsForCountry` treats code `USER` as the imported-country view and returns enabled logical channels that have at least one non-`builtin:live` member; `channelsForImportedCountry()` delegates to that path. `importedCountry()` returns `LiveTvCountry(code: 'USER', englishName: 'Imported', channelCount: n)`; the Live TV screen appends that country only when `channelsForImportedCountry()` is nonempty. `_ChannelsPaneState._load` calls `UnifiedLiveCatalog.channelsForCountry(widget.country, force: force)` for every selected country, including `IR`; this keeps the existing `LiveCatalog`/Famelack/iptv-org loader and fixed Iran composition unchanged inside the adapter while attaching runtime context before playback. Empty-query browsing retains the existing country selection/order, with imported-only logical rows confined to `USER`.
- Extend the existing Live TV search field rather than adding a second search UI: for a nonempty query, search enabled logical channels from the unified snapshot across built-in and imported playlists, deduplicate by `channelId`, and open the selected logical channel through the existing playback boundary. With an empty query, preserve the current country list exactly.
- Add a playlist-manager action to the existing Live TV screen. Manage add URL/import file/rename/enable/disable/refresh/remove, last success/error/count/status, and explicit merge/split.
- Add a runtime-only nullable `LivePlaybackContext liveContext` field to `LiveTvChannel`; `fromJson` leaves it null and `copyWithStreams` preserves it, so API/cache JSON and public identifiers remain unchanged. The unified adapter orders enabled sources by priority/`sourceId`, uses those same URLs for `LiveTvChannel.streams`, and attaches a context whose `playlistId` comes from `memberIds.first` and whose `sourceIds` has exactly the same length/order. Imported rows use the logical `channelId` as `nanoid`; built-in rows preserve their existing `nanoid` and API/cache JSON, with the context carrying the logical ID. Convert sources to request-local `MediaSource` values only in Phase C; B4 leaves existing playback behavior unchanged. Call `recordChannelWatch` with `liveContext?.logicalChannelId ?? nanoid` when the user opens a channel, before the existing player call.

- [ ] **Step 1: Write failing repository tests with an in-memory state store, fake secret store, deterministic fake loader, and fake `BuiltInCatalogLoading` that supplies deterministic countries/channels and never accesses the network.** Assert two playlists coexist; enable/disable isolation; rename; refresh deduplication; unchanged `contentHash`/`parsingVersion` parse reuse with exact decoded-text comparison on a hash match; 304 with and without a cached snapshot, error, and stale-refresh behavior; `refreshing` is visible before loading, `lastUpdatedAt` changes on every completed attempt, `lastSuccessfulRefresh` changes only on success, successful status is `ready` with `lastErrorCode = null`, and failure is `error` without replacing the last-success timestamp; partial parse updates valid rows and retains issues; a valid `empty` playlist succeeds as `ready` with zero channels, clears that playlist's members and every attached source/secret, and dissolves associations left with one member; an invalid or nonempty malformed zero-valid refresh retains the last good members/count and surfaces `error`; successful nonempty refresh removes stale parsed sources, reuses an exact-URL user source, and retains other user sources and their secret references; removal isolation; association/separation persistence; favorite/hidden/category/order/source-policy/last-successful-source persistence and invalid-policy rejection including buffering-threshold bounds; user-source add/deduplication/reorder/disable/re-enable-to-unverified; per-channel failover preference; source success/failure transitions, success setting renderer capability to `Supported`, explicit evidence-based capability updates with invalid-value rejection, remembered successful source, and removed/disabled-source late-result handling; recent-watch ordering/cap; exactly one built-in playlist record and unchanged Iran rows; per-country unified loading preserves built-in `nanoid`, stream/context order, and member ordinal without enumerating another country, returns no rows when built-in is disabled, and falls back to cached adapted rows with `catalogUnavailable` after a reload failure; unified search deduplication, empty-query country preservation, and adapter stream/context count-order alignment; sensitive URL absent from serialized state/log messages.
- [ ] **Step 2: Write a failing widget test for the manager.** Assert add-URL, import-file, rename, enable, refresh, remove, error, and empty controls exist; assert Android TV focus traversal reaches every destructive action only after a confirmation dialog.
- [ ] **Step 3: Run hosted RED.** Run `flutter test test/playlist_repository_test.dart test/playlist_manager_screen_test.dart -r expanded`. Expected: missing classes/screens.
- [ ] **Step 4: Implement repository, secure storage, file picker, unified adapter, and manager UI.** Preserve `live_catalog.dart`'s fixed `_loadIran` and `mergeIranChannels` behavior.
- [ ] **Step 5: Run hosted GREEN.** Run targeted tests, `dart format --output=none --set-exit-if-changed` on the task's Dart files, `flutter analyze`, and full `flutter test` on GitHub. Expected: all pass; legacy favorites/history/link-health tests remain green.
- [ ] **Step 6: Commit.** Stage only B4-D files; commit `feat: integrate Flutter playlist management`.

## Task B4-S: Swift Playlist Repository and Live TV Integration

**Files:**
- Create: `Sources/Core/PlaylistSecretStore.swift`
- Create: `Sources/Core/PlaylistRepository.swift`
- Create: `Sources/Core/LiveCatalogFileStore.swift`
- Create: `Sources/Core/UnifiedLiveCatalogService.swift`
- Create: `Sources/UI/Live/PlaylistManagerView.swift`
- Modify: `Sources/UI/Live/LiveTVView.swift`
- Modify: `Sources/Core/LiveTVModels.swift`
- Modify: `Sources/Core/LiveTVCatalog.swift`
- Create: `Tests/playlist-repository/main.swift`
- Create: `Tests/playlist-repository/run.sh`
- Modify: `.github/workflows/ci.yml` only in the `macos-typecheck` job

**Interfaces consumed:** B1-S/B2-S/B3-S and existing `LiveTVCatalog`.

**Interfaces produced:**

```swift
struct PlaylistPayload: Sendable {
    var text: String
    var etag: String?
    var lastModified: String?
    var notModified: Bool
}

protocol PlaylistLoading: Sendable {
    func load(
        _ record: PlaylistRecord,
        etag: String?,
        lastModified: String?
    ) async throws -> PlaylistPayload
}

protocol PlaylistSecretStoring: Sendable {
    func put(_ value: String) async throws -> String
    func get(_ ref: String) async throws -> String?
    func delete(_ ref: String) async throws
}

@MainActor
final class PlaylistRepository {
    init(
        stateStore: LiveCatalogStateStoring,
        secretStore: PlaylistSecretStoring,
        loader: PlaylistLoading,
        builtInCatalog: BuiltInCatalogLoading
    )

    func records() async -> [PlaylistRecord]
    func addRemote(name: String, url: String) async throws -> PlaylistRecord
    func importLocal(name: String, text: String, locationRef: String) async throws -> PlaylistRecord
    func rename(playlistId: String, name: String) async throws
    func setEnabled(playlistId: String, enabled: Bool) async throws
    func refresh(_ playlistId: String, force: Bool = false) async throws -> PlaylistRefreshResult
    func addUserSource(channelId: String, memberId: String, label: String, url: String) async throws -> ChannelSourceRecord
    func reorderSources(channelId: String, sourceIds: [String]) async throws
    func setSourceEnabled(sourceId: String, enabled: Bool) async throws
    func setAutomaticFailover(channelId: String, enabled: Bool) async throws
    func setSourcePolicy(channelId: String, policy: SourcePolicy) async throws
    func associateChannels(memberIds: [String], preferredLogicalId: String) async throws
    func separateChannel(memberId: String) async throws
    func setFavorite(channelId: String, favorite: Bool) async throws
    func setHidden(channelId: String, hidden: Bool) async throws
    func setCategory(channelId: String, category: String?) async throws
    func setUserOrder(channelId: String, order: Int?) async throws
    func recordSourceSuccess(sourceId: String, at: Date) async throws
    func setRendererCapability(sourceId: String, capability: RendererSupport) async throws
    func recordSourceFailure(sourceId: String, at: Date, errorCode: String) async throws
    func recordChannelWatch(channelId: String, at: Date) async throws
    func remove(_ playlistId: String) async throws
    func channels(
        for country: LiveTVCountry,
        force: Bool = false
    ) async throws -> [LiveTVChannel]
    func snapshot(force: Bool = false) async throws -> UnifiedCatalogSnapshot
}

struct PlaylistRefreshResult: Sendable {
    var record: PlaylistRecord
    var issues: [CatalogIssue]
    var usedCachedSnapshot: Bool
}

protocol LiveCatalogStateStoring: Sendable {
    func load() async throws -> LiveCatalogState?
    func save(_ state: LiveCatalogState) async throws
}

@MainActor
protocol BuiltInCatalogLoading {
    func countries(force: Bool) async throws -> [LiveTVCountry]
    func channels(
        for country: LiveTVCountry,
        force: Bool
    ) async throws -> [LiveTVChannel]
}

@MainActor
final class UnifiedLiveCatalogService {
    init(_ repository: PlaylistRepository)
    func importedCountry() async -> LiveTVCountry
    func channelsForImportedCountry() async throws -> [LiveTVChannel]
    func channels(
        for country: LiveTVCountry,
        force: Bool = false
    ) async throws -> [LiveTVChannel]
}
```

Implement `LiveCatalogFileStore` at Application Support `CCloudMac/live-catalog-v1.json` with atomic replacement and the B1 codec. Remote loading uses a 25-second timeout, strict UTF-8, and the cached ETag/Last-Modified arguments. A 304 returns `PlaylistPayload(text: "", etag: cachedEtag, lastModified: cachedLastModified, notModified: true)` and reuses the last good parsed snapshot with `usedCachedSnapshot = true`; a 304 without a cached snapshot is a `staleRefresh` failure that retains any last good state. Use a 15-minute freshness window, one in-flight task per playlist, parse reuse for unchanged parsed `contentHash`/`parsingVersion`, and `staleRefresh` for changed generations. Execute every uncached decode/parse in `Task.detached` using the synchronous parser, compare exact decoded text before parse-cache reuse, and return to the main actor before mutating or persisting state. Refresh marks `refreshing`, stamps `lastUpdatedAt` on completion, and treats a valid empty playlist as a successful zero-channel reconciliation that sets `ready`, clears `lastErrorCode`, updates `lastSuccessfulRefresh`/`channelCount = 0`, clears its members/sources/secrets, and dissolves associations left with one member; partial refreshes set `ready`, clear `lastErrorCode`, update `lastSuccessfulRefresh`, and update valid rows with issues, while invalid or nonempty zero-valid refreshes retain the last good members/count, set `error`/`lastErrorCode`, and leave `lastSuccessfulRefresh` unchanged. Successful nonempty refreshes reconcile by `sourceId`, append new IDs in first-seen order after the member's current maximum priority while reusing an existing user-origin source on an exact canonical URL match, remove missing playlist-origin sources/secrets, retain user-origin sources, and preserve unchanged IDs' priorities/enabled/association/preference/health state. User-source IDs use the `memberId + "\nuser\n" + canonical URL` hash, deduplicate exact URLs, and use `origin = user` with `rendererCapability = Not Yet Verified`; reorder requires the complete ID set; disable sets `disabled`; re-enable sets `unverified` without clearing timestamps. Persist association and all channel preferences including `SourcePolicy` validated with the exact B4-D ranges and `lastSuccessfulSourceId`; `setRendererCapability` requires an existing enabled source and a valid `RendererSupport` value, updates only that field atomically, and is called only with playback/renderer evidence; success also sets `Supported`, while transport/timeout/HTTP failures leave capability unchanged and removed/disabled-source late results are ignored. Keep the newest 50 distinct watches and exactly one `builtin:live` adapter record. `channels(for:force:)` loads only the requested country through `builtInCatalog.channels`, registers it through the B3 adapter, and returns adapted unified logical rows with a `builtin:live` member from that country ordered by the first such member's `ordinal`; it does not enumerate unrelated countries. A disabled `builtin:live` record returns an empty array. A load failure with a previous successful country cache returns those cached adapted rows and records safe `catalogUnavailable` metadata; without a cache it throws the existing safe catalog error. When `builtin:live` is enabled, snapshot loading calls `countries(force:)`, loads each country's channels with concurrency capped at four, registers them through the same adapter, and caches successful per-country results; a country failure records safe `catalogUnavailable` metadata, retains its previous cache when present, and never drops imported channels or fixed Iran rows. The manager disables rename/removal/source-location editing for `builtin:live`, and repository rename/remove calls reject that ID. `refresh("builtin:live")` runs the built-in load with `force = true` rather than the M3U parser, becomes `ready` when at least one country loads, and otherwise becomes `error` while retaining any previous built-in cache and last-success timestamp. Conform `LiveTVCatalog` to `BuiltInCatalogLoading`: add `force: Bool = false` to its existing `channels(for:)` method, call `clearCache()` first when `force` is true, then retain the existing Iran/other-country branch; add `countries(force: Bool)` that calls `LiveTVClient.shared.clearCache()` when `force` is true and then `LiveTVClient.shared.countries()`. `LiveTVCatalog.load` and `LiveTVIranList.build` remain unchanged. Implement `KeychainPlaylistSecretStore` with a dedicated Keychain service and accessible-after-authentication policy appropriate to the app. Use `NSOpenPanel` for local M3U/M3U8 selection, parse the initially supplied text, create a security-scoped bookmark, and persist only its reference rather than a plaintext playlist copy. Refresh uses `startAccessingSecurityScopedResource`/`stopAccessingSecurityScopedResource`; loss of access produces `localAccessUnavailable` and retains the last good snapshot. Do not scan Downloads or any other directory.

Add a runtime-only nullable `liveContext` property to `LiveTVChannel`, exclude it from `CodingKeys`, default it to nil in the existing initializer/decoder, and preserve it in `replacingStreams`; API/cache JSON and existing identifiers remain unchanged. `UnifiedLiveCatalogService` orders enabled sources by priority/`sourceId`, builds `sources.streams` in that order, uses logical `channelId` as a new imported channel's `nanoid`, preserves existing built-in `nanoid` values, and attaches `LivePlaybackContext` with `playlistId` from `memberIds.first` and equally ordered `sourceIds`. Treat code `USER` as the imported-country view and return enabled logical channels with at least one non-`builtin:live` member; `channelsForImportedCountry()` delegates to that path. Add a synthetic imported country with code `USER` only when imported channels exist. `LiveTVModel.loadChannels(for:)` routes every selected country, including `IR`, through `UnifiedLiveCatalogService.channels(for:force:)`; the service delegates built-in countries to the existing `LiveTVCatalog` loader inside the adapter, so `LiveTVCatalog.load` and `LiveTVIranList.build` remain unchanged while returned rows carry runtime context. Empty-query browsing retains the existing country selection/order, with imported-only logical rows confined to `USER`. Extend the existing search field so a nonempty query searches enabled unified logical channels across built-in/imported playlists, deduplicates by `channelId`, and uses the existing playback call; an empty query preserves the current country list. Add a playlist-manager sheet to `LiveTVView`; preserve `filteredChannels`, remote focus behavior, QA search hook, and existing playback call. Record `liveContext?.logicalChannelId ?? nanoid` when the user opens a channel, before the existing player call.

- [ ] **Step 1: Add `Tests/playlist-repository/main.swift` and `run.sh` with fake state/secret/loader/built-in seams.** Assert playlist coexistence/isolation, rename, refresh deduplication, unchanged `contentHash`/`parsingVersion` parse reuse with exact decoded-text comparison on a hash match, 304 with and without a cached snapshot, error, and stale-refresh behavior, `refreshing` before loading, `lastUpdatedAt` on every completion, `lastSuccessfulRefresh` only on success, `ready`/cleared error on success and `error`/retained last-success on failure, partial refresh, a valid `empty` refresh as successful zero-channel cleanup of members/all attached sources/secrets with single-member associations dissolved, and invalid or nonempty zero-valid refresh retaining the last good members/count; stale parsed-source removal with exact-URL user-source reuse and user-source/secret retention, removal isolation, association/separation and channel-preference/source-policy/last-successful-source persistence with invalid-policy rejection including buffering-threshold bounds, user-source deduplication/reorder/disable/re-enable, per-channel failover, source success/failure timestamp transitions, success setting renderer capability to `.supported`, evidence-based capability updates with invalid-value rejection, remembered successful source, removed/disabled-source late-result handling, recent-watch cap, unified-search deduplication/empty-query preservation, adapter stream/context count-order alignment, one built-in record with unchanged Iran rows, per-country unified loading preserving built-in `nanoid`, stream/context order, and member ordinal without enumerating another country, disabled built-in returning no rows, and cached-adapted-row fallback with `catalogUnavailable` after reload failure, and sensitive-URL omission from state/logs. The runner compiles the B1-B3 sources, `LiveTVM3UClient.swift`, `LiveTVModels.swift`, `Models.swift`, `PersianNumber.swift`, `PlaylistRepository.swift`, and `UnifiedLiveCatalogService.swift`; no network method is invoked. It does not compile `LiveTVCatalog`, AppKit UI, or the Keychain adapter, and the test supplies a fake `BuiltInCatalogLoading`. Add a `Run playlist repository tests` step to the hosted macOS job. Expected RED: missing Swift types.
- [ ] **Step 2: Implement repository, file store, Keychain store, unified service, and manager sheet.** Conform `LiveTVCatalog` to `BuiltInCatalogLoading`; keep `LiveTVCatalog.load` and `LiveTVIranList.build` semantics unchanged.
- [ ] **Step 3: Run hosted GREEN.** Run `./scripts/typecheck.sh`, `./Tests/live-foundation/run.sh`, `./Tests/playlist-repository/run.sh`, and version checks. UI rendering remains `Not Yet Verified` until a hosted macOS snapshot/UI harness is added in Phase G.
- [ ] **Step 4: Commit.** Stage only B4-S files; commit `feat: integrate Swift playlist management`.

## Task B4-J: webOS Playlist Repository and Live TV Integration

**Files:**
- Create: `webos_app/app/js/playlist_repository.js`
- Modify: `webos_app/app/js/unified_catalog.js`
- Create: `webos_app/app/js/screens/playlists.js`
- Modify: `webos_app/app/js/screens/live.js`
- Modify: `webos_app/app/index.html`
- Test: `webos_app/test/playlist_repository.test.js`

**Interfaces consumed:** B1-J/B2-J/B3-J and existing `CC.live`, `CC.store`, `CC.nav`, `CC.ui`.

**Interfaces produced:**

```javascript
CC.playlists = {
  create: function (options) {
    // options = {
    //   stateStore: {
    //     load(): Promise<LiveCatalogState|null>,
    //     save(state): Promise<void>,
    //     remove(): Promise<void>
    //   },
    //   secretStore: {
    //     put(value): Promise<String>,
    //     get(ref): Promise<String|null>,
    //     delete(ref): Promise<void>
    //   },
    //   loader: {
    //     load(record, validators): Promise<{text: String, etag: String|null, lastModified: String|null, notModified: Boolean}>
    //     // validators = {etag: String|null, lastModified: String|null}
    //   },
    //   builtInApi: {
    //     countries(force: Boolean): Promise<[country]>,
    //     channels(code: String, force: Boolean): Promise<[channel]>
    //   }
    //   // force is optional; production passes CC.live
    // }
    // returns repository instance
  }
};

// Repository instance methods, all returning Promises:
// records(), addRemote({name, url}), importLocal({name, text, locationRef}),
// rename({playlistId, name}), setEnabled({playlistId, enabled}),
// refresh(playlistId, force), addUserSource({channelId, memberId, label, url}),
// reorderSources({channelId, sourceIds}), setSourceEnabled({sourceId, enabled}),
// setAutomaticFailover({channelId, enabled}), setSourcePolicy({channelId, policy}),
// associateChannels({memberIds, preferredLogicalId}), separateChannel(memberId),
// setFavorite({channelId, favorite}), setHidden({channelId, hidden}),
// setCategory({channelId, category}), setUserOrder({channelId, order}),
// recordSourceSuccess(sourceId, at), setRendererCapability({sourceId, capability}),
// recordSourceFailure({sourceId, at, errorCode}), recordChannelWatch(channelId, at),
// remove(playlistId), channelsForCountry(code, force), snapshot(force)
```

Implement a 25-second remote timeout, strict UTF-8, and cached ETag/Last-Modified validators passed to the loader. A 304 returns `{text: '', etag: cachedEtag, lastModified: cachedLastModified, notModified: true}` and reuses the last good parsed snapshot with `usedCachedSnapshot = true`; a 304 without a cached snapshot is a `staleRefresh` failure that retains any last good state. Use a 15-minute freshness window, one in-flight request per playlist, unchanged `contentHash`/`parsingVersion` parse reuse with exact decoded-text comparison on a hash match, and `staleRefresh` for changed generations. Every uncached parse uses `CC.playlistParser.parseAsync` so its 2,000-line timer yields preserve remote input responsiveness. Refresh sets `refreshing` before loading and stamps `lastUpdatedAt` on every completed attempt. A valid `empty` playlist succeeds as `ready`, updates `lastSuccessfulRefresh`/`channelCount = 0`, clears that playlist's members and all attached sources/secrets, clears `lastErrorCode`, and dissolves associations left with one member. A partial refresh updates valid rows and records issues; an invalid or nonempty malformed zero-valid refresh retains last good members/count, sets `error`/`lastErrorCode`, and leaves `lastSuccessfulRefresh` unchanged. Successful nonempty refreshes reconcile by `sourceId`, append new IDs in first-seen order after the member's current maximum priority while reusing an existing user-origin source on an exact canonical URL match, remove missing playlist-origin sources/secrets, retain user-origin sources, and preserve unchanged IDs' priority/enabled/association/preference/health state. User-source IDs hash `memberId + "\nuser\n" + canonical URL`, deduplicate exact URLs, and use `origin = user` with `rendererCapability = Not Yet Verified`; reorder requires the complete ID set; disable sets `disabled`; re-enable sets `unverified` without clearing timestamps. Persist association and all channel preferences including `SourcePolicy` validated with the exact B4-D ranges and `lastSuccessfulSourceId`; `setRendererCapability` requires an existing enabled source and a valid `RendererSupport` value, updates only that field atomically, and is called only with playback/renderer evidence; success also sets `Supported`, while transport/timeout/HTTP failures leave capability unchanged and removed/disabled-source late results are ignored. Keep the newest 50 distinct watches and exactly one `builtin:live` adapter record. `channelsForCountry(code, force)` loads only the requested country through `builtInApi.channels(code, force)`, registers it through the B3 adapter, and returns adapted unified logical rows with a `builtin:live` member from that country ordered by the first such member's `ordinal`; it does not enumerate unrelated countries. A disabled `builtin:live` record returns an empty array. A load failure with a previous successful country cache returns those cached adapted rows and records safe `catalogUnavailable` metadata; without a cache it rejects with the existing safe catalog error. When `builtin:live` is enabled, snapshot loading calls `builtInApi.countries(force)`, loads each country's channels with concurrency capped at four, registers them through the same adapter, and caches successful per-country results; a country failure records safe `catalogUnavailable` metadata, retains its previous cache when present, and never drops imported channels or fixed Iran rows. The manager disables rename/removal/source-location editing for `builtin:live`, and repository rename/remove calls reject that ID. `refresh('builtin:live')` runs the built-in load with `force = true` rather than the M3U parser, becomes `ready` when at least one country loads, and otherwise becomes `error` while retaining any previous built-in cache and last-success timestamp. `stateStore` exposes `load()`, `save(state)`, and `remove()` and must throw on storage failure; do not reuse the silent `CC.store.set` behavior for the new state. `secretStore` exposes `put(value)`, `get(ref)`, and `delete(ref)`. Because no hardware-backed webOS secret store is verified, the production secret adapter throws `secretStorageUnavailable`; `addRemote` rejects URLs classified as sensitive. Credential-free URLs may be persisted as `locationRef`. Local-file playlist import remains `Unsupported` until a webOS device proves an authorized picker/read route; its manager control is disabled with that limitation.

The unified adapter attaches a runtime `liveContext` to each unified channel copy, orders enabled sources by priority/`sourceId`, derives `liveContext.playlistId` from the first member, and keeps `streams` and `liveContext.sourceIds` in identical order; imported copies use logical `channelId` as `nanoid`, while built-in copies preserve their existing `nanoid`; existing `primaryStream` selection and the single-source playback call remain unchanged in Phase B; Phase C starts context-aware playback at `context.sourceIds[0]`. Existing API channel objects remain unchanged. Treat code `USER` as the imported-country view and return enabled logical channels with at least one non-`builtin:live` member. Add a remote-accessible playlist-manager entry to the existing Live TV screen. Append a synthetic `USER` country only when imported channels exist. Existing `CC.live.countries/channels` and the current Iran-first picker remain unchanged as the underlying built-in loader. The screen's country-row load calls `channelsForCountry(code, force)` for every selected country, including `IR`, so returned rows carry runtime context without changing the fixed Iran loader. Empty-query browsing retains the current country selection/order, with imported-only logical rows confined to `USER`. Extend `live-search` so a nonempty query searches enabled unified logical channels across built-in/imported playlists, deduplicates by `channelId`, and uses the existing playback call; an empty query preserves the country list. Preserve `.focusable`, arrow/enter/back behavior, and the existing single-`primaryStream` playback call until Phase C. Record `liveContext?.logicalChannelId ?? nanoid` when the user opens a channel, before the existing player call.

- [ ] **Step 1: Write failing Node repository tests with localStorage-like fakes and deterministic loader responses.** Assert: two playlists coexist and enable/disable/rename/remove isolate their records; concurrent refresh calls share one loader invocation; unchanged payload bytes reuse one parse; 304 reuses the last good snapshot while a 304 without cached payload produces `staleRefresh`; `refreshing` is visible before loading, `lastUpdatedAt` changes on every completion, `lastSuccessfulRefresh` changes only on success, success clears `lastErrorCode`, and failure retains the last-success timestamp; a valid `empty` refresh succeeds as `ready` with zero channels, removes that playlist's members and every attached source/secret, and dissolves associations left with one member; malformed or nonempty zero-valid refresh sets `error`, retains old members/count, and records a safe error code; partial refresh keeps valid members and issues; a generation change discards an in-flight result with `staleRefresh`; successful nonempty refresh removes missing `origin = playlist` sources and their secrets, reuses an exact-URL `origin = user` source instead of duplicating it, and retains user sources/secrets; association/separation and favorite/hidden/category/order/failover/source-policy/last-successful-source preferences round-trip; invalid policy values, including buffering thresholds 999 and 120001 ms, reject without mutation; user-source URL deduplication returns the existing ID; complete-set reorder writes priorities from zero; disable sets `disabled`; re-enable sets `unverified` and retains timestamps; success sets `available`, renderer capability `Supported`, success time, clears failure fields, and remembers the source; explicit capability updates round-trip and invalid values reject; failure sets `failed`, failure time, and safe code without clearing the remembered source; late results for removed/disabled sources are ignored; recent watches keep the newest 50 distinct IDs; exactly one `builtin:live` record exists and no iptv-org-only channel is created; per-country unified loading preserves built-in `nanoid`, stream/context order, and member ordinal without invoking another country's loader, disabled built-in returns no rows, and a failed reload returns cached adapted rows with `catalogUnavailable`; unified search deduplicates logical IDs while an empty query preserves country results; adapter streams and context source IDs have equal counts/order; sensitive URLs never enter state; state-store errors reject; sensitive remote URLs reject with `secretStorageUnavailable`; a credential-free URL round-trips; local import rejects with `localAccessUnavailable`. Expected RED: repository module absent.
- [ ] **Step 2: Implement the ES2017 repository and screen.** Load `identity_hash.js`, `playlist_contracts.js`, `playlist_parser.js`, `source_registry.js`, `channel_identity.js`, `unified_catalog.js`, and `playlist_repository.js` before screen scripts in `index.html`.
- [ ] **Step 3: Run hosted GREEN.** Run `node --test webos_app/test/*.test.js`, syntax checks, JSON/service assertions, and version checks. Device UI/local-file behavior remains `Not Yet Verified`.
- [ ] **Step 4: Commit.** Stage only B4-J files; commit `feat: integrate webOS playlist management`.

## Phase B Exit Gate

Phase B is complete only when all of the following are attached to the exact commit:

- Hosted Dart, Swift, and Node foundation suites are green.
- Existing Flutter tests, Swift typecheck, webOS static checks, and canonical version checks are green.
- Multiple independent playlists coexist and retain independent identities.
- One logical channel can contain multiple sources; a source URL change does not change channel identity.
- Manual association/separation works; name similarity never auto-merges.
- Fixed Iran composition tests prove Famelack rows are preserved and iptv-org-only rows are absent.
- Additive migration tests prove fresh install, schema-v1 restore, corrupt/future-version fail-closed behavior, and untouched legacy favorites/history/settings.
- Sensitive URL persistence/redaction tests pass on platforms with a verified secret store; unsupported platforms reject credential-bearing URLs explicitly.
- No playback behavior changed in Phase B. Existing single-source playback remains the Phase B integration contract.
- Local runtime remains **NOT VERIFIED**. Any UI/device claim is separately labeled.

# Phase C — Intelligent Source Resolution

Phase C extends existing playback recovery. It does not add background stream probing.

## Task C1: Shared Source Policy, Failure Taxonomy, and Diagnostics

**Files:**
- Create: `flutter_app/lib/core/source_resolution.dart`
- Create: `Sources/Core/LiveTVSourceResolution.swift`
- Create: `webos_app/app/js/source_resolution.js`
- Test: `flutter_app/test/source_resolution_test.dart`
- Modify: `Tests/live-foundation/main.swift`
- Modify: `Tests/live-foundation/run.sh`
- Test: `webos_app/test/source_resolution.test.js`

**Interfaces consumed:** `ChannelSourceRecord`, `SourceHealth`, `LogicalChannel`, and the persisted `SourcePolicy` from B1.

**Interfaces produced:**

```dart
enum SourceFailureKind {
  transport, timeout, http, unsupportedMedia, demux, decoder,
  temporaryBuffering, cancelled, unknown,
}

class SourceAttemptResult {
  const SourceAttemptResult({
    required this.sourceId,
    required this.kind,
    required this.at,
    this.httpStatus,
  });
  final String sourceId;
  final SourceFailureKind kind;
  final DateTime at;
  final int? httpStatus;
}

class SourceDecision {
  const SourceDecision({
    required this.action,
    this.sourceId,
    this.delay,
    this.userMessage,
  });
  final String action; // retrySame, advance, cooldown, exhausted, cancelled, none
  final String? sourceId;
  final Duration? delay;
  final String? userMessage;
}

SourceDecision decideAfterFailure({
  required List<ChannelSourceRecord> eligibleSources,
  required SourceAttemptResult result,
  required int automaticAttempts,
  required int sameSourceRetryCount,
  required SourcePolicy policy,
  required DateTime now,
  required bool userLeftChannel,
  required bool automaticFailoverEnabled,
});
```

Swift exposes `SourcePolicy`, `SourceAttemptResult`, `SourceDecision`, `SourceFailureKind`, and `decideAfterFailure(eligibleSources:result:automaticAttempts:sameSourceRetryCount:policy:now:userLeftChannel:automaticFailoverEnabled:)` with identical semantics. JavaScript exposes `CC.sourceResolution.decideAfterFailure(input)`, where `input` has exactly the Dart named arguments above, and `CC.sourceResolution.redactUrl(url)`.

Rules: leaving the channel returns `cancelled` before any retry. When `automaticFailoverEnabled` is false, the initial attempt may finish but the decision is `exhausted`; manual selection remains available. Temporary buffering returns `retrySame` only while `sameSourceRetryCount < policy.sameSourceRetries` and then `exhausted`; it never advances. Cancellation never advances or retries. A sustained-buffering detector may submit `transport` only after `policy.bufferingThresholdMs`; before that threshold it submits `temporaryBuffering`. DNS failures classify as `transport`. Transport/timeout/http/unsupportedMedia/demux/decoder return `retrySame` while `sameSourceRetryCount < policy.sameSourceRetries` and may advance after that cap. `unknown` retries only to the same-source cap and then exhausts without advancing. `sameSourceRetryCount` resets to zero only when advancing to a different source, never when retrying the current source. The caller orders automatic attempts with enabled sources by user priority then `sourceId`; the remembered `lastSuccessfulSourceId` is displayed and offered for manual selection but never overrides explicit priority. Manual selection bypasses automatic order. Disabled sources are skipped. A failed source is skipped only while `now - lastFailedPlaybackAt < Duration(seconds: policy.failedCooldownSeconds)`; an unverified source with no failure timestamp remains eligible. Only one recovery chain may run per logical channel; starting another allocates a new `PlaybackAttemptContext.requestGeneration` and cancels the prior chain before any retry or advance. Every asynchronous callback carries its captured generation, stable source ID, and attempt number; advancing or retrying within the same automatic recovery chain keeps the generation, replaces the source ID only when advancing, and increments `attemptNumber`, while the active chain accepts a result only when all three captured values still match. Attempts never exceed `maxAutomaticAttempts`; after one-based attempt number `automaticAttempts`, use zero-based backoff index `min(max(automaticAttempts - 1, 0), backoffCount - 1)`, so the first failure uses the first configured delay and later failures reuse the final delay after the array is exhausted. If no source can run now but a failed source's cooldown has a future expiry, return `cooldown` with that shortest remaining delay; otherwise return `exhausted` with a Persian user message and no URLs. Actual playback readiness sets `health = available`, `lastSuccessfulPlaybackAt`, and clears `lastFailedPlaybackAt`; a classified failure sets `health = failed`, `lastFailedPlaybackAt`, and a safe `lastErrorCode`. Diagnostics store source ID, provider namespace, failure kind, time, and redacted HTTP status—never raw sensitive URLs.

- [ ] **Step 1: Write failing policy tests.** Cover every failure kind, DNS classification, buffering-threshold boundary and temporary-versus-sustained buffering, retry cap, timestamp-based cooldown boundary, unverified-source eligibility, priority ordering independent of the remembered source, exhausted list, disabled sources, automatic-failover disabled, cancellation precedence, deterministic backoff, health/timestamp transitions, and URL redaction. Expected RED: missing modules.
- [ ] **Step 2: Implement the pure policy in all three platforms.** Add `Sources/Core/LiveTVSourceResolution.swift` to `Tests/live-foundation/run.sh`; the Swift tests exercise only pure functions and never construct a player.
- [ ] **Step 3: Run hosted GREEN suites.** Expected: all policy tests pass.
- [ ] **Step 4: Commit.** Stage only C1 files; commit `feat: add deterministic source recovery policy`.

## Task C2: Swift Playback Integration

**Files:**
- Modify: `Sources/Player/PlaybackController.swift`
- Modify: `Sources/Core/LiveTVModels.swift`
- Modify: `Sources/Core/Models.swift`
- Test: `Tests/player/main.swift`
- Test: `Tests/player/run.sh`

**Boundary:** `PlaybackRequest` gains optional stable live context plus a request-local attempt context carrying the generation token; `PlaybackController.orderedAttempts`, `advanceAfterFailure`, readiness/failure handlers, and manual source selection consume the policy and ignore callbacks from superseded generations. Pass `liveContext.automaticFailoverEnabled` and `liveContext.sourcePolicy` into every policy decision and persist `lastFailedPlaybackAt` on classified failures. Direct AVPlayer, remux fallback, reconnect, and link health remain.

**Interfaces consumed:** B1 `LivePlaybackContext`, B1 `PlaybackAttemptContext`, and the runtime-only `LiveTVChannel.liveContext` attached by B4-S.

**Produced interface:**

```swift
// Add to PlaybackRequest in Sources/Core/Models.swift:
let liveContext: LivePlaybackContext?
let attemptContext: PlaybackAttemptContext?

init(
    title: String,
    subtitle: String? = nil,
    posterURL: String? = nil,
    sources: [MediaSource],
    preferredSourceID: Int? = nil,
    media: PlaybackInfo? = nil,
    upcomingEpisodes: [PlaybackEpisode] = [],
    startAt: Double = 0,
    liveContext: LivePlaybackContext? = nil,
    attemptContext: PlaybackAttemptContext? = nil
)

// Extend the existing LiveTVChannel method without changing its call shape:
func playbackRequest(
    countryName: String,
    streamOverride: String? = nil
) -> PlaybackRequest?
```

Replace synthesized `Codable` with an explicit `CodingKeys` enum containing `id`, `title`, `subtitle`, `posterURL`, `sources`, `preferredSourceID`, `media`, `upcomingEpisodes`, and `startAt`, but not the runtime-only `liveContext` or `attemptContext`. Implement explicit `init(from:)`/`encode(to:)` in an extension: decode every listed key with the existing required/optional semantics, assign both runtime contexts to nil, and encode every listed key while omitting both; existing request JSON remains unchanged. `advancingToNextEpisode()` forwards the in-memory `liveContext` unchanged and sets `attemptContext = nil` because the next episode is a new request generation, and all existing non-live callers retain both `nil` defaults.

- [ ] **Step 1: Extend the existing AVPlayerLayer hosted harness with controlled transport failure, timeout, decoder failure, temporary/sustained buffering, automatic-failover-disabled behavior, manual selection, all-sources-failed, cancellation, and stale-callback fixtures.** Expected RED: stable context/policy not wired.
- [ ] **Step 2: Build `LiveTVChannel.playbackRequest` from the B4-attached `liveContext`; require `sourceIds.count == streams.count`, preserve the adapter's user-priority order with `sourceId` tie-breaking, and map persistent ID at index `i` to request-local `MediaSource` at index `i` without changing public `MediaSource.id`.** Pass `liveContext` into `PlaybackRequest` and create `PlaybackAttemptContext(requestGeneration: UUID().uuidString, playlistId: liveContext.playlistId, logicalChannelId: liveContext.logicalChannelId, sourceId: selectedStableSourceId, attemptNumber: 1, stableMediaIdentity: liveContext.logicalChannelId)`; for `streamOverride`, find its index in `streams` and pass a context copy whose `sourceIds` contains only that index's stable ID, or pass nil contexts when the override is not one of the channel's sources.
- [ ] **Step 3: Integrate policy decisions into existing failure handlers.** Permit one recovery chain per logical channel; manual selection or opening another channel allocates a new `requestGeneration` and cancels prior attempts; every readiness/failure callback compares its captured generation, stable source ID, and attempt number with the active attempt before mutating state, and stale callbacks are ignored; leaving the channel cancels retries; success persists the source's available health/success timestamp, clears its failure timestamp, and remembers its source ID; failure persists failed health/failure timestamp/safe error code, a definitive `unsupportedMedia` result calls `setRendererCapability(sourceId: selectedStableSourceId, capability: .unsupported)`, other failures leave capability unchanged, and diagnostics contain only redacted stable IDs/status.
- [ ] **Step 4: Run hosted GREEN.** Run Swift typecheck and the real AVPlayerLayer harness. Expected: failover occurs only for eligible failures, no retry loop, manual selection wins, and temporary buffering does not switch.
- [ ] **Step 5: Commit.** Stage only C2 files; commit `feat: integrate Swift source failover`.

## Task C3: Flutter Playback Integration

**Files:**
- Modify: `flutter_app/lib/core/playback.dart`
- Modify: `flutter_app/lib/screens/player_screen.dart`
- Test: `flutter_app/test/playback_source_test.dart`
- Test: `flutter_app/test/player_failover_test.dart`

**Boundary:** `PlayerArgs` gains optional stable live context and request-local attempt context; existing `_applyTracks`, same-link reloads, software-decoder fallback, source rotation, link health, and auto-next remain. Pass `liveContext.automaticFailoverEnabled` and `liveContext.sourcePolicy` into every policy decision and persist `lastFailedPlaybackAt` on classified failures.

**Interfaces consumed:** B1 `LivePlaybackContext`, B1 `PlaybackAttemptContext`, and the runtime-only `LiveTvChannel.liveContext` attached by B4-D.

**Produced interface:**

```dart
String newPlaybackRequestGeneration();

factory PlayerArgs.forChannel(
  LiveTvChannel channel,
  String countryName, {
  String? streamOverride,
  LivePlaybackContext? liveContext,
  PlaybackAttemptContext? attemptContext,
}) {
  // liveContext defaults to channel.liveContext.
  // A streamOverride must match channel.streams or the context is nil.
}
```

Add `LivePlaybackContext? liveContext` and `PlaybackAttemptContext? attemptContext` to `PlayerArgs`, preserve `liveContext` in `advance()`, clear `attemptContext` for the next episode's new request generation, and use the factory above. Existing callers continue compiling. For a matching override at index `i`, pass a live-context copy with `sourceIds: [context.sourceIds[i]]`; for an unknown override or a source/context length mismatch, pass nil contexts and retain the existing single-source behavior. When live context exists and no attempt context is supplied, the factory creates one with a fresh generation token, the selected stable source ID, `attemptNumber = 1`, and `stableMediaIdentity = logicalChannelId`. `newPlaybackRequestGeneration()` returns 32 lowercase hexadecimal characters from 16 `Random.secure()` bytes and is used only for runtime correlation, never persistence or authentication.

- [ ] **Step 1: Add failing unit/widget tests for policy integration, temporary/sustained buffering, automatic-failover-disabled behavior, manual precedence, cancellation, stale callbacks, auto-next preservation, and link-health preservation.** Expected RED.
- [ ] **Step 2: Build channel requests from `channel.liveContext`; require equal source/context counts, preserve the adapter's user-priority order with `sourceId` tie-breaking, and map stable ID at index `i` to request-local `MediaSource.id` at index `i` without replacing the public integer ID. Permit one recovery chain per logical channel, allocate a new `requestGeneration` for manual selection or a newly opened channel, compare captured generation/source ID/attempt number in every callback and ignore stale results, integrate the policy into existing recovery branches, and persist C1 health/timestamp/last-successful-source transitions through the repository; actual success sets renderer capability `Supported`, while only a definitive `unsupportedMedia` result calls `setRendererCapability` with `Unsupported`.**
- [ ] **Step 3: Run hosted GREEN.** Run targeted tests, `dart format --output=none --set-exit-if-changed`, `flutter analyze`, and full `flutter test`.
- [ ] **Step 4: Commit.** Stage only C3 files; commit `feat: integrate Flutter source failover`.

## Task C4: webOS Playback Integration

**Files:**
- Modify: `webos_app/app/js/player.js`
- Modify: `webos_app/app/js/screens/live.js`
- Test: `webos_app/test/player_failover.test.js`

**Boundary:** existing `<video>` error/stall/timeout handlers and manual source menu. Add no player engine.

- [ ] **Step 1: Add failing tests with a fake video element and fake timers.** Cover eligible failure, temporary/sustained buffering, automatic-failover-disabled behavior, manual source precedence, retry cap, cooldown, all-sources-failed, channel exit, and stale callbacks.
- [ ] **Step 2: Read the B4-attached `channel.liveContext` in `screens/live.js`, require its `sourceIds` count to equal the normalized enabled source count, and pass its stable `playlistId/logicalChannelId/sourceIds/automaticFailoverEnabled/sourcePolicy` plus a runtime `PlaybackAttemptContext` containing a fresh `requestGeneration`, `attemptNumber = 1`, the active `sourceId`, and `stableMediaIdentity = logicalChannelId` through existing `CC.player.open` options. Set the active source ID to `context.sourceIds[0]` when context exists; otherwise retain the legacy `primaryStream` path with nil stable context. Generate the token as `Date.now().toString(36) + ':' + moduleCounter.toString(36)` with a monotonically increasing module counter; it is runtime-only. Preserve user-priority order with `sourceId` tie-breaking; the remembered source does not override priority. Permit one recovery chain per channel, allocate a new generation for manual selection or a newly opened channel, ignore callbacks whose captured generation/source ID/attempt number is stale, invoke the shared policy, and persist failure timestamps plus successful-source memory through the repository; actual success sets renderer capability `Supported`, while only a definitive `unsupportedMedia` result calls `setRendererCapability` with `Unsupported`.**
- [ ] **Step 3: Run hosted GREEN Node/syntax checks.** Actual webOS playback remains `Not Yet Verified` until Task G2 device evidence.
- [ ] **Step 4: Commit.** Stage only C4 files; commit `feat: integrate webOS source failover`.

## Task C5: Source Management, Favorites, and Diagnostics UI

**Files:**
- Create: `flutter_app/lib/screens/channel_sources_screen.dart`
- Modify: `flutter_app/lib/screens/live_screen.dart`
- Create: `Sources/UI/Live/ChannelSourcesView.swift`
- Modify: `Sources/UI/Live/LiveTVView.swift`
- Create: `webos_app/app/js/screens/channel_sources.js`
- Modify: `webos_app/app/js/screens/live.js`
- Test: `flutter_app/test/channel_sources_screen_test.dart`

**Required behavior:** show channel name, active source label, remembered last-successful source, priority, last successful playback, safe source-specific error, honest health state, renderer capability/evidence status, manual selection, automatic-failover toggle, enable/disable, and reorder. Advanced controls expose the B4 `SourcePolicy` retry counts, connection timeout, backoff, cooldown, and buffering threshold with the exact validated ranges; invalid input is not persisted. A policy property the current engine cannot honor is disabled with a visible limitation and remains `Not Yet Verified` until probed. Never display a raw sensitive URL. Live TV favorites remain separate from media favorites. Hidden channels, custom category, user order, recently watched channels, and explicit merge/split use the Phase B preference/association stores.

- [ ] **Step 1: Write failing UI tests for remote/keyboard focus, reorder, disable, manual selection, automatic-failover toggle, source-policy controls/range rejection, safe source-error and renderer-capability display, confirmation, and favorites separation.**
- [ ] **Step 2: Implement contextual source controls in the existing Live TV/player experience.**
- [ ] **Step 3: Run hosted GREEN checks.** Device remote behavior is separately verified in G2.
- [ ] **Step 4: Commit.** Stage only C5 files; commit `feat: add channel source management`.

## Phase C Exit Gate

- Genuine playback failures trigger bounded failover; temporary buffering does not.
- Manual source selection always wins and cancels previous attempts; only one recovery chain runs per channel, and stale generation/source/attempt callbacks cannot mutate health or preferences.
- The last successfully played source is remembered and offered for manual selection; automatic order still follows explicit user priority.
- Retry/backoff/cooldown/exhaustion/cancellation tests pass, including the buffering threshold.
- Source health and renderer capability come only from playback/renderer results; no background probing exists.
- Existing same-source retries, link health, remux/software fallback, Continue Watching, and auto-next remain intact.
- Source diagnostics contain stable IDs and redacted failures only.
- Engine-specific timeout/backoff controls are honored only where runtime evidence exists; unsupported controls are visibly disabled.
- webOS automatic failover is not labeled Supported until device evidence exists.

# Phase D — Subtitle Foundation

Phase D introduces application-level subtitle contracts and integrates each existing renderer. Format support is evidence-based per platform.

## Task D1: Subtitle Contracts, Safe Parsing, and Capability Records

**Files:**
- Create: `flutter_app/lib/core/subtitle_contracts.dart`
- Create: `flutter_app/lib/core/subtitle_parser.dart`
- Create: `Sources/Core/SubtitleContracts.swift`
- Create: `Sources/Core/SubtitleParser.swift`
- Create: `webos_app/app/js/subtitle_contracts.js`
- Create: `webos_app/app/js/subtitle_parser.js`
- Test: `flutter_app/test/subtitle_parser_test.dart`
- Modify: `Tests/live-foundation/main.swift`
- Modify: `Tests/live-foundation/run.sh`
- Test: `webos_app/test/subtitle_parser.test.js`
- Fixtures: `Tests/fixtures/subtitles/valid.srt`, `valid.vtt`, `bom.srt`, `utf16le.srt`, `utf16be.srt`, `malformed.srt`, `persian-rtl.vtt`, `oversized.srt`, `invalid-utf8.srt`, `sample.ass`, `sample.ssa`

**Produced Dart interface:**

```dart
enum SubtitleOrigin { embedded, externalFile, discoveredFile }
enum SubtitleFormat { srt, webvtt, ass, ssa, embeddedUnknown }

class SubtitleStyle {
  const SubtitleStyle({
    this.fontSize = 1.0,
    this.fontFamily,
    this.fontWeight = 'normal',
    this.textColor = '#FFFFFFFF',
    this.backgroundColor = '#000000FF',
    this.textOpacity = 1.0,
    this.backgroundOpacity = 0.5,
    this.outlineColor = '#000000FF',
    this.outlineThickness = 2.0,
    this.shadow = false,
    this.horizontalAlignment = 'center',
    this.verticalPosition = 0.9,
  });
  final double fontSize;
  final String? fontFamily;
  final String fontWeight;
  final String textColor;
  final String backgroundColor;
  final double textOpacity;
  final double backgroundOpacity;
  final String outlineColor;
  final double outlineThickness;
  final bool shadow;
  final String horizontalAlignment;
  final double verticalPosition;
}

class SubtitleCue {
  const SubtitleCue({
    required this.start,
    required this.end,
    required this.text,
    required this.index,
  });
  final Duration start;
  final Duration end;
  final String text;
  final int index;
}

class SubtitleTrack {
  const SubtitleTrack({
    required this.trackId,
    required this.label,
    required this.origin,
    required this.format,
    this.language,
    this.title,
    this.engineTrackId,
    this.fileRef,
    this.rendererSupport = 'Not Yet Verified',
  });
  final String trackId;
  final String label;
  final SubtitleOrigin origin;
  final SubtitleFormat format;
  final String? language;
  final String? title;
  final String? engineTrackId;
  final String? fileRef;
  final String rendererSupport;
}

class SubtitleParseResult {
  const SubtitleParseResult({
    required this.format,
    required this.cues,
    required this.issues,
    required this.encoding,
  });
  final SubtitleFormat format;
  final List<SubtitleCue> cues;
  final List<String> issues;
  final String encoding;
}

SubtitleParseResult parseSubtitleBytes(List<int> bytes, String filename);
```

Swift exposes `SubtitleOrigin`, `SubtitleFormat`, `SubtitleStyle`, `SubtitleCue`, `SubtitleTrack`, `SubtitleParseResult`, and `parseSubtitleBytes(_:filename:)`, and reuses the B1 `RendererSupport` enum rather than defining a duplicate. `SubtitleStyle` mirrors every Dart field and default declared above and conforms to `Codable`, `Hashable`, and `Sendable`; its memberwise initializer supplies those defaults. JavaScript exposes the equivalent `SubtitleStyle` record, `CC.subtitleParser.parse(text, filename)` after strict UTF-8 decoding by the caller, and `CC.subtitleContracts.createTrack(trackId, label, origin, format, options)`, where `options` may contain `language`, `title`, `engineTrackId`, `fileRef`, and `rendererSupport`.

Parser rules: detect UTF-8 BOM; accept UTF-8 and UTF-16LE/BE only when a BOM explicitly identifies the encoding; reject invalid sequences without replacement-character loss; do not guess legacy encodings, and record them as `Unsupported` unless a reviewed decoder is added; SRT and WebVTT only in the application parser; validate monotonic nonnegative cue times and `end > start`; strip WebVTT headers safely; preserve Unicode text exactly; never reverse RTL strings; enforce 5 MiB/20,000-cue/8,192-character limits. ASS/SSA bytes are not converted or stylized by this parser; they are passed only to a renderer proven to support them. The parser records `Unsupported` rather than claiming renderer support. Canonical runtime track IDs are `embedded:<engineTrackId>` for engine tracks and `external:<stableKeyHash(canonicalFileRef)>` for external/discovered files (`CC.identityHash` in JavaScript); the same file reached by manual selection and discovery therefore has one ID and is not duplicated. `engineTrackId`, language, title, and original format metadata remain unchanged on the track.

Fixtures must include Persian/Arabic/Kurdish, diacritics, mixed `CCloud 2.0.0` inside RTL dialogue, numbers, punctuation, long lines, missing language metadata, malformed timing, BOM, and invalid UTF-8. Create their exact contents as follows:

```text
Tests/fixtures/subtitles/valid.srt
1
00:00:01,000 --> 00:00:03,500
Hello CCloud

2
00:00:04,000 --> 00:00:05,250
سلام دنیا
```

```text
Tests/fixtures/subtitles/valid.vtt
WEBVTT

intro-1
00:00.000 --> 00:00:02.000
CCloud 2.0.0
```

`bom.srt` is the exact UTF-8 bytes of `valid.srt` prefixed with `EF BB BF`. `utf16le.srt` and `utf16be.srt` are the exact UTF-16LE/UTF-16BE encodings of `valid.srt`, prefixed respectively with `FF FE` and `FE FF`; both must decode to the same two cues as `valid.srt`. `invalid-utf8.srt` is the exact byte sequence `31 0A 30 30 3A 30 30 3A 30 30 2C 30 30 30 20 2D 2D 3E 20 30 30 3A 30 30 3A 30 31 2C 30 30 30 0A FF FE 41 0A`, which contains an invalid standalone UTF-8 sequence and must be rejected without replacement. `oversized.srt` is generated as `"1\n00:00:00,000 --> 00:00:01,000\n" + "x".repeat(5 * 1024 * 1024)`, so it exceeds the 5 MiB file limit before cue parsing.

```text
Tests/fixtures/subtitles/malformed.srt
1
00:00:00,000 --> 00:00:01,000
Good cue

2
00:00:03,000 --> 00:00:02,000
Bad timing
```

```text
Tests/fixtures/subtitles/persian-rtl.vtt
WEBVTT

rtl-1
00:00.000 --> 00:00:04.000
فارسی، العَرَبِيَّةُ، کردیی؛ CCloud 2.0.0 و 123!
```

```text
Tests/fixtures/subtitles/sample.ass
[Script Info]
ScriptType: v4.00+
PlayResX: 1280
PlayResY: 720

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Arial,48,&H00FFFFFF,&H000000FF,&H00000000,&H80000000,0,0,0,0,100,100,0,0,1,2,0,2,10,10,20,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:00.00,0:00:02.00,Default,,0,0,0,,سلام CCloud
```

```text
Tests/fixtures/subtitles/sample.ssa
[Script Info]
ScriptType: v4.00

[V4 Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, TertiaryColour, BackColour, Bold, Italic, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, AlphaLevel, Encoding
Style: Default,Arial,48,&H00FFFFFF,&H000000FF,&H00000000,&H80000000,0,0,1,2,0,2,10,10,20,0,1

[Events]
Format: Marked, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: Marked=0,0:00:00.00,0:00:02.00,Default,,0,0,0,,سلام CCloud
```

The long-line test appends `" متن طولانی برای آزمون"` twelve times to the `rtl-1` cue in memory; the missing-language test creates a `SubtitleTrack` from `valid.vtt` with `language: null` and `title: null` and asserts both remain null.

- [ ] **Step 1: Write failing parser/capability tests.** Assert cue counts/times/text, UTF-8/UTF-16 BOM handling, invalid UTF-8 rejection, explicit unsupported-legacy-encoding status, malformed cue isolation, limit enforcement, no string reversal, and ASS/SSA `Not Yet Verified` until renderer evidence.
- [ ] **Step 2: Implement contracts/parsers in all three platforms.** Add `Sources/Core/SubtitleContracts.swift` and `Sources/Core/SubtitleParser.swift` to `Tests/live-foundation/run.sh`; no AVFoundation import belongs in the pure parser runner.
- [ ] **Step 3: Run hosted GREEN suites.**
- [ ] **Step 4: Commit.** Stage only D1 files; commit `feat: add subtitle contracts and safe parsers`.

## Task D2: macOS Embedded and External Subtitles

**Files:**
- Create: `Sources/Player/SubtitleController.swift`
- Modify: `Sources/Player/PlaybackController.swift`
- Create: `Sources/UI/Detail/SubtitleSettingsView.swift`
- Modify: `Sources/UI/Detail/PlayerScreen.swift`
- Test: `Tests/player/main.swift`
- Test: `Tests/player/run.sh`

**Produced interface:**

```swift
@MainActor
final class SubtitleController {
    init(player: AVPlayer)
    func refreshEmbeddedTracks() async -> [SubtitleTrack]
    func select(track: SubtitleTrack?) async throws
    func loadExternal(url: URL) async throws -> SubtitleTrack
    func setDelay(milliseconds: Int) async
    func applyStyle(_ style: SubtitleStyle) async
    func dispose() async
}
```

Integration rules: enumerate `AVMediaSelectionGroup` for `.legible`; preserve engine track ID, language, title, and format metadata; selecting Off clears the legible selection; direct AVPlayer embedded support is verified through the hosted AVPlayerLayer harness. External SRT/WebVTT uses a CCloud cue overlay with timed rendering; external ASS/SSA is `Unsupported` on this path unless a later renderer proves support. `AVMediaSelectionOption.textStyleRules` is used only for WebVTT-compatible styling and is not described as universal embedded styling. FFmpeg remux continues to map video/audio only in this task; remux embedded subtitles remain explicitly unsupported rather than silently discarded without notice.

Use `NSOpenPanel` for manual file selection and security-scoped access. Validate bytes before display. Subtitle changes must not restart playback. Do not scan media directories in Phase D.

- [ ] **Step 1: Extend the hosted AVPlayerLayer harness with embedded legible selection, Off, external SRT/WebVTT load, switching during playback, delay, malformed rejection, and teardown.** Expected RED.
- [ ] **Step 2: Implement `SubtitleController` and contextual controls.**
- [ ] **Step 3: Run hosted GREEN.** Capture rendered frames proving cue appearance, Off, switching, Persian shaping, mixed RTL/LTR, and no duplicate tracks. macOS ASS/SSA/remux-subtitle claims remain unsupported unless separately proven.
- [ ] **Step 4: Commit.** Stage only D2 files; commit `feat: add macOS subtitle selection and external loading`.

## Task D3: Flutter Embedded and External Subtitles

**Files:**
- Create: `flutter_app/lib/core/subtitle_controller.dart`
- Modify: `flutter_app/lib/screens/player_screen.dart`
- Test: `flutter_app/test/subtitle_controller_test.dart`
- Test: `flutter_app/test/player_subtitle_test.dart`

**Produced interface:**

```dart
abstract class SubtitleRenderer {
  Future<List<SubtitleTrack>> embeddedTracks();
  Future<void> selectEngineTrack(String? engineTrackId);
  Future<SubtitleTrack> loadExternalFile(String fileRef);
  Future<void> setDelay(int milliseconds);
  Future<void> applyStyle(SubtitleStyle style);
  Future<void> dispose();
}

class MediaKitSubtitleRenderer implements SubtitleRenderer {
  MediaKitSubtitleRenderer(this.player);
  final Player player;
  // Implements SubtitleRenderer against the resolved media_kit API.
}

class SubtitleController {
  SubtitleController(this.renderer);
  final SubtitleRenderer renderer;

  Future<List<SubtitleTrack>> embeddedTracks();
  Future<void> select(SubtitleTrack? track);
  Future<SubtitleTrack> loadExternalFile(String fileRef);
  Future<void> setDelay(int milliseconds);
  Future<void> applyStyle(SubtitleStyle style);
  Future<void> dispose();
}
```

Use media_kit/libmpv track enumeration and selection APIs confirmed against the resolved media_kit version; use the libmpv add-subtitle-file route for external files only after Android/Windows hosted runtime proof. Keep the existing audio-only `_applyTracks` behavior intact and add a separate subtitle path. Android uses SAF/platform picker with persistable read permission where available; Windows uses a native picker; Android TV must expose remote-operable selection or an honest fallback. ASS/SSA support is recorded per resolved libmpv build and platform, not inferred from the wrapper license.

- [ ] **Step 1: Write failing controller tests with a fake `SubtitleRenderer` and player integration tests around `MediaKitSubtitleRenderer`; replay real track payloads at the renderer boundary without inventing media_kit method signatures.** Assert embedded enumeration, language/title preservation, Off, external load, switching, delay, malformed rejection, duplicate suppression, and disposal.
- [ ] **Step 2: Implement `MediaKitSubtitleRenderer` and the controls against the resolved API; `player_screen.dart` constructs `SubtitleController(MediaKitSubtitleRenderer(player))`, while tests inject a fake `SubtitleRenderer`. Gate each external-file route on its platform capability record; without Android/Windows runtime proof, report `Not Yet Verified` and do not invoke the unproven route.**
- [ ] **Step 3: Run hosted GREEN unit/widget tests and hosted Android/Windows runtime probes.** Record actual libmpv version and rendered screenshots. Any unprobed platform/format remains `Not Yet Verified`.
- [ ] **Step 4: Commit.** Stage only D3 files; commit `feat: add Flutter subtitle selection and external loading`.

## Task D4: webOS Subtitle Adapter Behind a Device Gate

**Files:**
- Create: `webos_app/app/js/subtitle_controller.js`
- Modify: `webos_app/app/js/player.js`
- Test: `webos_app/test/subtitle_controller.test.js`

**Produced interface:**

```javascript
CC.subtitleController = {
  // capabilities = { vtt: RendererSupport, cors: RendererSupport, styling: RendererSupport }
  create: function (video, capabilities) {
    // Returns {
    //   tracks(): Promise<[SubtitleTrack]>,
    //   select(track: SubtitleTrack|null): Promise<void>,
    //   loadExternalVtt(blobOrUrl: Blob|String): Promise<SubtitleTrack>,
    //   off(): Promise<void>,
    //   setDelay(milliseconds: Number): Promise<void>,
    //   applyStyle(style: SubtitleStyle): Promise<void>,
    //   dispose(): Promise<void>
    // }
  }
};
```

- [ ] **Step 1: Add failing fake-DOM tests for capability-gated rejection, text-track enumeration, Off, VTT load/switch, duplicate suppression, delay, malformed rejection, and disposal.**
- [ ] **Step 2: If a hosted webOS emulator/device has proved VTT loading, styling limits, and CORS behavior, implement the adapter using HTML5 text tracks. If that proof is absent, implement the same factory with methods that reject `Error('webOS subtitle rendering Not Yet Verified')`, keep the controls disabled, and attach the missing probe to G2; do not ship a pretend adapter.** Local-file selection remains unsupported unless the device exposes an authorized route. ASS/SSA remains unsupported unless actual renderer evidence says otherwise.
- [ ] **Step 3: Run hosted GREEN Node tests and record webOS device evidence.** Do not mark Supported from Node alone.
- [ ] **Step 4: Commit.** Stage only D4 files; commit `feat: add evidence-gated webOS subtitle adapter`.

## Phase D Exit Gate

- Embedded track enumeration/selection/Off works only on platforms with renderer evidence.
- External SRT/WebVTT loading and switching works on proven paths without restarting playback.
- Manual pickers use native authorized access; Android TV/webOS limitations are explicit.
- Malformed/oversized/invalid-UTF-8 files fail visibly and do not crash.
- ASS/SSA, HLS subtitles, MKV/MP4 embedded subtitles, remux subtitles, and webOS local files each have a per-platform evidence status.
- No duplicate embedded/external track appears for the same engine track/file.

# Phase E — Automatic Subtitle Discovery

## Task E1: Authorized-Root Discovery, Matching, and Cache

**Files:**
- Create: `flutter_app/lib/core/subtitle_discovery.dart`
- Create: `flutter_app/lib/core/subtitle_root_reader.dart`
- Modify: `flutter_app/android/app/src/main/kotlin/com/ccloud/ccloud/MainActivity.kt`
- Create: `Sources/Core/SubtitleDiscoveryService.swift`
- Create: `Sources/Core/AuthorizedSubtitleRootReader.swift`
- Create: `webos_app/app/js/subtitle_discovery.js` for the pure matcher only; no webOS filesystem adapter
- Test: `flutter_app/test/subtitle_discovery_test.dart`
- Modify: `Tests/live-foundation/main.swift`
- Modify: `Tests/live-foundation/run.sh`
- Test: `webos_app/test/subtitle_discovery.test.js` only for the pure matcher
- Fixtures: `Tests/fixtures/subtitles/discovery/movie/`, `Tests/fixtures/subtitles/discovery/series/`

**Produced interface:**

```dart
enum SubtitleDiscoveryErrorCode {
  unauthorizedRoot, accessLost, pathEscape, limitExceeded,
}

class AuthorizedSubtitleRoot {
  const AuthorizedSubtitleRoot({required this.ref, required this.displayName});
  final String ref;
  final String displayName;
}

class AuthorizedSubtitleFile {
  const AuthorizedSubtitleFile({
    required this.ref,
    required this.basename,
    required this.size,
    required this.modifiedAt,
  });
  final String ref;
  final String basename;
  final int size;
  final DateTime modifiedAt;
}

abstract class AuthorizedRootReader {
  Future<List<AuthorizedSubtitleFile>> list(AuthorizedSubtitleRoot root);
}

abstract class SubtitleRootPicker {
  Future<AuthorizedSubtitleRoot?> pick();
}

class DeviceSubtitleRootReader implements AuthorizedRootReader, SubtitleRootPicker {
  DeviceSubtitleRootReader();
  @override
  Future<AuthorizedSubtitleRoot?> pick();
  @override
  Future<List<AuthorizedSubtitleFile>> list(AuthorizedSubtitleRoot root);
}

class SubtitleMatch {
  const SubtitleMatch({
    required this.fileRef,
    required this.mediaRef,
    required this.language,
    required this.confidence,
    required this.ambiguous,
  });
  final String fileRef;
  final String mediaRef;
  final String? language;
  final int confidence;
  final bool ambiguous;
}

class SubtitleDiscoveryService {
  SubtitleDiscoveryService(this.rootReader);
  final AuthorizedRootReader rootReader;
  Future<List<SubtitleMatch>> discover({
    required AuthorizedSubtitleRoot root,
    required String mediaRef,
    required String mediaBasename,
    String? episodeId,
  });
  void invalidate(String rootRef);
}
```

Swift exposes `AuthorizedSubtitleRoot`, `AuthorizedSubtitleFile`, `SubtitleMatch`, and `SubtitleDiscoveryService`, plus `protocol AuthorizedRootReading: Sendable { func list(_ root: AuthorizedSubtitleRoot) async throws -> [AuthorizedSubtitleFile] }`. Its exact service and native reader interfaces are:

```swift
enum SubtitleDiscoveryError: Error {
    case unauthorizedRoot, accessLost, pathEscape, limitExceeded
}

struct AuthorizedSubtitleRoot: Sendable {
    var ref: String
    var displayName: String
}

struct AuthorizedSubtitleFile: Sendable {
    var ref: String
    var basename: String
    var size: Int
    var modifiedAt: Date
}

struct SubtitleMatch: Sendable {
    var fileRef: String
    var mediaRef: String
    var language: String?
    var confidence: Int
    var ambiguous: Bool
}

protocol AuthorizedRootReading: Sendable {
    func list(_ root: AuthorizedSubtitleRoot) async throws -> [AuthorizedSubtitleFile]
}

final class SubtitleDiscoveryService {
    init(_ reader: AuthorizedRootReading)
    func discover(
        root: AuthorizedSubtitleRoot,
        mediaRef: String,
        mediaBasename: String,
        episodeId: String?
    ) async throws -> [SubtitleMatch]
    func invalidate(_ rootRef: String)
}

final class AuthorizedSubtitleRootReader: AuthorizedRootReading {
    func pick() async throws -> AuthorizedSubtitleRoot?
    func list(_ root: AuthorizedSubtitleRoot) async throws -> [AuthorizedSubtitleFile]
    func release(_ root: AuthorizedSubtitleRoot)
}
```

JavaScript exposes `CC.subtitleDiscovery.match(mediaBasename, subtitleBasename, episodeId)` as a pure function returning `{score: Int, language: String|null, episodeNumber: Int|null}` or `null`; `discover` combines those results into the canonical `SubtitleMatch` fields. No webOS filesystem enumeration is implemented in this phase.

Matching order: exact basename = 100; basename plus recognized language suffix = 95; exact episode identifier plus language = 90; recognized release pattern plus episode identifier = 80; all other same-directory files = no match. A score below 80 is never offered automatically. Multiple candidates at the same top score are ambiguous and require user choice. F2 presents discovered candidates with language, confidence, and ambiguity in the existing subtitle list and allows the user to choose a different candidate or ignore discovery; discovery never attaches a file by itself. Language codes are parsed only from a terminal suffix separated by `.`, `_`, or `-`: `fa/fas`, `en/eng`, `ar/ara`, `ku/kur`, `de/deu`, and `fr/fra`. Episode identifiers match `E<digits>`, `Episode <digits>`, or `S<digits>E<digits>` case-insensitively with ASCII/Persian/Arabic digits normalized; a supplied `episodeId` is normalized to a decimal episode number and must equal the captured episode number. A release-pattern match requires the complete normalized media basename, a recognized episode identifier, and a subtitle extension, with no unrelated same-directory fallback. Cache keys include root reference, media reference, file name, size, and modification time; changed files invalidate the entry.

Discovery enumerates only files returned by the authorized-root reader, including existing subdirectories such as `Season 01`. Before opening a candidate, the native reader/service resolves its canonical path and verifies containment in the authorized root; escaping paths and links outside that root are rejected. It does not scan arbitrary parents, Downloads, network shares, or IPTV URL neighbors. Listings are capped at 20,000 entries and 16 directory levels; exceeding either ceiling throws `SubtitleDiscoveryError.limitExceeded` without attaching candidates.

`DeviceSubtitleRootReader.pick()` calls the static `FilePicker.pickDirectory(dialogTitle: 'انتخاب پوشهٔ زیرنویس')` API from the B4-targeted `file_picker` 13.4.1; the B4 dependency gate must confirm the exact resolved version and pass Android/Android TV/Windows compatibility review. A null `Uri?` result means cancellation. On Android the returned `content://` tree URI is stored as `ref`; on Windows `uri.toFilePath()` is canonicalized and stored as `ref`; `displayName` is the final nonempty path segment. The exact Flutter method channel `ccloud.subtitle_roots` then exposes `listRoot({ref})`, returning an array of `{ref: String, basename: String, size: int, modifiedAt: int}` where `modifiedAt` is UTC milliseconds since epoch, and `releaseRoot({ref})`. On Android, `MainActivity.kt` handles those two methods, takes persistable read permission for the supplied tree URI, enumerates children with `DocumentsContract`, and releases permission on explicit root removal; it recursively returns files only, skips directories as candidates, and rejects tree URIs outside the picked root. On Windows, `list` recursively enumerates with `dart:io`; every file is canonicalized and rejected unless it remains under the selected path. Android TV with no usable directory picker returns null and exposes the existing honest fallback. The macOS reader uses `NSOpenPanel` with `canChooseDirectories = true`, stores a security-scoped bookmark as `ref`, starts/stops scoped access around recursive enumeration, canonicalizes each file, and rejects links whose resolved path escapes the bookmark root. `release` destroys the bookmark only after explicit user removal of the authorized root.

Create the exact discovery fixture tree below. Media files are zero-byte metadata fixtures; each `.srt` file contains only `1\n00:00:00,000 --> 00:00:01,000\n<its own basename>\n`, so matcher tests never depend on media decoding.

```text
Tests/fixtures/subtitles/discovery/movie/CCloud.Movie.2026.mkv
Tests/fixtures/subtitles/discovery/movie/CCloud.Movie.2026.srt
Tests/fixtures/subtitles/discovery/movie/CCloud.Movie.2026.fa.srt
Tests/fixtures/subtitles/discovery/movie/CCloud.Movie.2026.en.srt
Tests/fixtures/subtitles/discovery/movie/Unrelated.News.srt
Tests/fixtures/subtitles/discovery/series/Season 01/CCloud.Show.S01E02.mkv
Tests/fixtures/subtitles/discovery/series/Season 01/CCloud.Show.S01E02.fa.srt
Tests/fixtures/subtitles/discovery/series/Season 01/CCloud.Show.S01E02.en.srt
Tests/fixtures/subtitles/discovery/series/Season 01/CCloud.Show.S01E03.fa.srt
Tests/fixtures/subtitles/discovery/series/Season 01/Other.Show.S01E02.fa.srt
```

For `mediaBasename = "CCloud.Movie.2026"`, the no-suffix file scores 100, `.fa`/`.en` files score 95, and `Unrelated.News` returns null. For `mediaBasename = "CCloud.Show.S01E02"` and `episodeId = "2"`, the `.fa` and `.en` files both score 90 and are mutually ambiguous; `S01E03` and `Other.Show.S01E02` return null. Changing a fixture file's size or modification time must produce a new cache key and rematch; an injected reader throwing `unauthorizedRoot`, `accessLost`, `pathEscape`, or `limitExceeded` must propagate without cached candidates being returned.

- [ ] **Step 1: Create deterministic movie/series fixture trees and failing matcher/cache tests.** Cover exact, language, episode, unrelated rejection, ambiguity, changed-file invalidation, and unauthorized-root refusal.
- [ ] **Step 2: Implement native authorized-root readers and the pure matcher.** Add `Sources/Core/SubtitleDiscoveryService.swift` to `Tests/live-foundation/run.sh`; pure matcher/cache tests inject a fake `AuthorizedRootReading` implementation and perform no filesystem scan. Implement `DeviceSubtitleRootReader`, the Android `MainActivity.kt` method-channel handlers, and `AuthorizedSubtitleRootReader` with the exact contracts above. macOS uses a user-selected directory bookmark; Android uses a user-selected SAF tree; Windows uses a user-selected directory; webOS remains unsupported without proof. F2 owns the UI that calls `pick()` and presents candidates; E1 owns only reader/service behavior.
- [ ] **Step 3: Run hosted GREEN tests and platform file-access probes.**
- [ ] **Step 4: Commit.** Stage only E1 files; commit `feat: add authorized subtitle discovery`.

## Phase E Exit Gate

- Exact and language/episode matches work; unrelated files are rejected.
- Ambiguous matches require manual choice.
- Discovery cannot access a root without explicit authorization.
- Cache revalidates changed files.
- webOS discovery is `Unsupported` unless an authorized file-listing route is proven.

# Phase F — Subtitle Customization, Timing, RTL, and Preferences

## Task F1: Versioned Preferences and Renderer Mapping

**Files:**
- Create: `flutter_app/lib/core/subtitle_preferences.dart`
- Create: `Sources/Core/SubtitlePreferencesStore.swift`
- Create: `webos_app/app/js/subtitle_preferences.js`
- Test: `flutter_app/test/subtitle_preferences_test.dart`
- Modify: `Tests/live-foundation/main.swift`
- Modify: `Tests/live-foundation/run.sh`
- Test: `webos_app/test/subtitle_preferences.test.js`

**Interfaces consumed:** `SubtitleStyle` and `SubtitleTrack` from D1.

**Produced interface:**

```dart
class SubtitlePreferences {
  const SubtitlePreferences({
    this.enabledByDefault = false,
    this.preferredLanguage,
    this.delayMs = 0,
    this.style = const SubtitleStyle(),
    this.rememberManualSelection = true,
  });
  final bool enabledByDefault;
  final String? preferredLanguage;
  final int delayMs;
  final SubtitleStyle style;
  final bool rememberManualSelection;
}

class SubtitleSelectionRecord {
  const SubtitleSelectionRecord({
    required this.mediaKey,
    required this.selectedAt,
    this.trackId,
    this.fileRef,
  });
  final String mediaKey;
  final DateTime selectedAt;
  final String? trackId;
  final String? fileRef;
}

abstract class SubtitlePreferenceStore {
  Future<SubtitlePreferences> load();
  Future<void> save(SubtitlePreferences preferences);
  Future<SubtitleSelectionRecord?> selectionFor(String mediaKey);
  Future<void> rememberSelection(SubtitleSelectionRecord selection);
  Future<void> clearSelection(String mediaKey);
}

class SharedPreferencesSubtitlePreferenceStore implements SubtitlePreferenceStore {
  SharedPreferencesSubtitlePreferenceStore(this.preferences);
  final SharedPreferences preferences;
  @override
  Future<SubtitlePreferences> load();
  @override
  Future<void> save(SubtitlePreferences preferences);
  @override
  Future<SubtitleSelectionRecord?> selectionFor(String mediaKey);
  @override
  Future<void> rememberSelection(SubtitleSelectionRecord selection);
  @override
  Future<void> clearSelection(String mediaKey);
}
```

Swift and JavaScript use the same field names and validation rules. Swift defines the consumed records and a fakeable store protocol, then provides the exact `UserDefaults` implementation:

```swift
struct SubtitlePreferences: Codable, Hashable, Sendable {
    var enabledByDefault: Bool
    var preferredLanguage: String?
    var delayMs: Int
    var style: SubtitleStyle
    var rememberManualSelection: Bool

    static let standard = SubtitlePreferences(
        enabledByDefault: false,
        preferredLanguage: nil,
        delayMs: 0,
        style: SubtitleStyle(),
        rememberManualSelection: true
    )
}

struct SubtitleSelectionRecord: Codable, Hashable, Sendable {
    var mediaKey: String
    var selectedAt: Date
    var trackId: String?
    var fileRef: String?
}

protocol SubtitlePreferenceStoring {
    func load() throws -> SubtitlePreferences
    func save(_ preferences: SubtitlePreferences) throws
    func selectionFor(_ mediaKey: String) throws -> SubtitleSelectionRecord?
    func rememberSelection(_ selection: SubtitleSelectionRecord) throws
    func clearSelection(_ mediaKey: String) throws
}

final class SubtitlePreferencesStore: SubtitlePreferenceStoring {
    init(defaults: UserDefaults = .standard)
    func load() throws -> SubtitlePreferences
    func save(_ preferences: SubtitlePreferences) throws
    func selectionFor(_ mediaKey: String) throws -> SubtitleSelectionRecord?
    func rememberSelection(_ selection: SubtitleSelectionRecord) throws
    func clearSelection(_ mediaKey: String) throws
}
```

```javascript
CC.subtitlePreferences = {
  create: function (storage) {
    // storage exposes getItem(key): String|null and setItem(key, value): void.
    // Returns {
    //   load(): Promise<SubtitlePreferences>,
    //   save(preferences): Promise<void>,
    //   selectionFor(mediaKey): Promise<SubtitleSelectionRecord|null>,
    //   rememberSelection(selection): Promise<void>,
    //   clearSelection(mediaKey): Promise<void>
    // }
  }
};
```

Media keys are `movie:<id>`, `episode:<seriesId>:<episodeId>`, and `local:<authorizedFileRef>`; they never contain a stream URL. Persist under a new versioned key/file only. The exact Flutter keys are `ccloud.subtitle.preferences.v1` and `ccloud.subtitle.selections.v1`; the exact macOS `UserDefaults` keys and webOS `localStorage` keys have the same strings. Each value is a JSON object with `schemaVersion: 1`; selections are an object map keyed by media key. Missing new keys return defaults/no selection, malformed or future-version values throw without overwriting the prior value, and legacy keys are never read or written by this store. A selection with both `trackId` and `fileRef` null means Off; a record with both non-null is rejected. Stored colors always use `#RRGGBBAA`; renderer adapters compute effective alpha as `(stored alpha / 255) * opacity`, clamped to 0–1, so `backgroundOpacity` and `textOpacity` are multipliers rather than replacements for the color alpha. Validate/clamp `fontSize` to 0.5–2.0, `fontWeight` to `normal` or `bold`, colors to `#RRGGBBAA`, text/background opacity to 0–1, `outlineThickness` to 0.0–8.0, `horizontalAlignment` to `center`, `left`, or `right`, `verticalPosition` to 0–1, and delay to ±60,000 ms; trim `fontFamily` to 128 characters and use platform fallback when unavailable. A renderer may further narrow a range only with a visible `Partially Supported` limitation. Preferred language selects only a matching track for the current media; it never attaches an unrelated subtitle. If no matching track exists, subtitles remain Off and the unavailable language is shown rather than silently selecting another language. A manual selection is not overridden on the next play when `rememberManualSelection` is true.

- [ ] **Step 1: Write failing migration/default/clamp/reset/manual-selection tests.** Include fresh install, old settings untouched, corrupt new preferences fail closed, round-trip, media-key isolation, remembered selection, and explicit selection clearing.
- [ ] **Step 2: Implement stores and defaults.** Add `Sources/Core/SubtitlePreferencesStore.swift` to `Tests/live-foundation/run.sh`; Swift tests inject a fake `SubtitlePreferenceStoring` implementation and do not access the user's preferences file.
- [ ] **Step 3: Run hosted GREEN checks.** From `flutter_app/`, run `flutter test test/subtitle_preferences_test.dart -r expanded`, `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, and full `flutter test`. From the repository root, run `./scripts/typecheck.sh`, `./Tests/live-foundation/run.sh`, `node --test webos_app/test/*.test.js`, webOS syntax checks, and version checks. Expected: all pass and legacy settings remain unchanged.
- [ ] **Step 4: Commit.** Stage only F1 files; commit `feat: persist subtitle preferences and selections`.

## Task F2: Player Settings UI, Timing, and RTL Proof

**Files:**
- Modify: `Sources/UI/Detail/SubtitleSettingsView.swift`
- Modify: `Sources/UI/Detail/PlayerScreen.swift`
- Modify: `flutter_app/lib/screens/player_screen.dart`
- Modify: `webos_app/app/js/player.js`
- Test: `flutter_app/test/subtitle_settings_test.dart`

**Required controls:** Off, embedded/external track list, load file where supported, font size/family/weight where supported, text/background/outline colors, opacities, outline, shadow, alignment, vertical position, ± delay, ±100 ms fine adjustment, reset synchronization (`delayMs = 0`), restore defaults, and live preview. Unsupported renderer properties are disabled with a visible limitation, not silently ignored.

- [ ] **Step 1: Write failing settings tests for every control, range clamp, reset, delayed application, and unsupported-property labeling.**
- [ ] **Step 2: Integrate controls with each platform's renderer adapter and the D1/F1 stores. Manual track/file selection writes `SubtitleSelectionRecord`; preferred language is consulted only when no remembered manual selection exists. Show E1 discovered candidates with language/confidence/ambiguity and allow manual correction or dismissal without automatic attachment.**
- [ ] **Step 3: Capture hosted/device frames for Persian, Arabic, Kurdish, diacritics, mixed RTL/LTR, numbers, punctuation, English words in Persian dialogue, long lines, and font fallback.** No manual string reversal is permitted. Use platform text shaping/bidi.
- [ ] **Step 4: Run hosted GREEN checks and record unsupported style properties per renderer.**
- [ ] **Step 5: Commit.** Stage only F2 files; commit `feat: add subtitle customization and RTL validation`.

## Phase F Exit Gate

- Preferences persist and restore without touching legacy stores.
- Positive/negative delay works on proven renderers.
- Manual subtitle selection is not unexpectedly overridden.
- Persian/Arabic/Kurdish/mixed RTL evidence exists per supported platform.
- Styling support and limitations are documented per renderer; bitmap/unsupported styling is not promised.

# Phase G — Integration, Verification, and Release Readiness

## Task G1: Cross-Platform Hosted Verification and Documentation

**Files:**
- Create: `docs/architecture/MULTI_SOURCE_SUBTITLE_COMPATIBILITY.md`
- Create: `docs/verification/2026-11-25-multi-source-subtitles.md`
- Modify: `.github/workflows/ci.yml` only for newly required hosted integration/device jobs
- Modify: `SOURCES.md`
- Modify: `THIRD_PARTY_NOTICES.md`

**Required hosted commands:**

```bash
python3 scripts/version.py check
./scripts/typecheck.sh
./Tests/live-foundation/run.sh
./Tests/playlist-repository/run.sh
./Tests/player/run.sh
node --test webos_app/test/*.test.js
```

From `flutter_app/`:

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

Also run the repository's existing Android APK/AAB, Windows, macOS, webOS, packaging, license, security, and installer/startup jobs where available. Do not weaken production signing or release gates to obtain green status.

The compatibility document must contain one row for every specification feature and columns Android phone, Android TV, Windows, macOS, and webOS. Each cell includes status, renderer/engine version, evidence link, limitation, and verification date. The verification report must identify the exact commit, workflow run URLs, job names, fixture/test names, device/emulator identity, artifacts/screenshots, failures, unresolved blockers, and local-runtime `NOT VERIFIED` statement.

- [ ] **Step 1: Run the full hosted suite and platform builds on the candidate commit.** Record failures without bypassing gates.
- [ ] **Step 2: Execute regression scenarios:** repeated channel/source switching, disconnected stream, network interruption, unsupported codec, external subtitle load during playback, track switching, long-duration playback, Continue Watching, auto-next, Live TV search, favorites, migration, and EPG no-data.
- [ ] **Step 3: Update the evidence-backed compatibility matrix and verification report.** Do not mark a feature Supported without runtime evidence. Add dated rows to `SOURCES.md` and `THIRD_PARTY_NOTICES.md`; never rewrite historical provenance or notice claims.
- [ ] **Step 4: Review dependency licenses/notices and secret/redaction behavior.** Resolve or explicitly retain native-media release blockers.
- [ ] **Step 5: Commit.** Stage only G1 files; commit `docs: record multi-source subtitle verification`.

## Task G2: Device and Emulator Acceptance

**Files:**
- Modify: `docs/architecture/MULTI_SOURCE_SUBTITLE_COMPATIBILITY.md` after G1 creates it
- Modify: `docs/verification/2026-11-25-multi-source-subtitles.md` after G1 creates it

**Required evidence matrix:**

| Target | Required probes |
|---|---|
| Android phone | SAF picker, media_kit embedded/external tracks, ASS/SSA actual result, RTL frames, failover, background/lifecycle |
| Android TV | Remote focus, picker/fallback, source/subtitle controls, failover, RTL frames |
| Windows | Native file/directory picker, libmpv tracks/formats, failover, installer startup |
| macOS | NSOpenPanel/bookmarks, AVFoundation legible tracks, external SRT/WebVTT overlay, remux limitation, failover, RTL frames |
| webOS | Remote focus, HTML5 VTT actual result, failover, local-file limitation, long-run stability |

- [ ] **Step 1: Run hosted emulator probes where the repository already supports them; use physical devices only through an explicitly authorized owner/device procedure.**
- [ ] **Step 2: Record firmware/OS, device model, commit, engine version, input method, screenshots/video, and pass/fail per probe.**
- [ ] **Step 3: Reopen any capability marked Supported if new contradictory evidence appears.**
- [ ] **Step 4: Append dated device evidence and resulting capability changes to the G1 compatibility matrix and verification report; preserve prior entries and identify the exact candidate commit.**
- [ ] **Step 5: Commit.** Stage only the two G2 evidence documents; commit `docs: record multi-source subtitle device acceptance`.
- [ ] **Step 6: Publish no production release or tag without separate explicit authorization.**

## Phase G Exit Gate

- All applicable automated tests and builds pass on the exact candidate commit.
- Data migrations are verified from the previous release schema and on fresh installs.
- No known critical regression remains in existing playback, favorites, history, Continue Watching, auto-next, search, diagnostics workstream contracts, link health, or the EPG no-data boundary.
- Every compatibility cell has evidence or an honest unsupported/not-verified status.
- Dependencies and licenses are recorded; native-media/legal blockers remain visible and enforceable.
- Security review confirms URL validation, size limits, safe XMLTV/subtitle parsing, authorized file access, secret storage, and redaction.
- Local runtime is **NOT VERIFIED** unless the report contains actual local evidence; this plan itself provides none.

# Acceptance Traceability

| Specification requirement | Implementing tasks | Acceptance evidence |
|---|---|---|
| Multiple independent playlists | B1, B2, B4 | Repository coexistence/isolation tests |
| URL/local playlist import | B4-D/S/J | Picker/fetch tests; webOS local status |
| Rename/enable/disable/refresh/remove/status/count | B4 | Repository/UI tests |
| Stable playlist/channel/source identity | B1-B3 | Identity/refresh tests |
| Duplicate candidates without automatic merge | B3 | Candidate/association tests |
| Manual association/separation | B3, B4, C5 | Pure and UI tests |
| Multiple sources and priority | B2-B4, C1-C5 | Registry/policy/UI tests |
| Manual/automatic source selection and remembered last success | B3-B4, C1-C5 | Preference, ordering, player tests/runtime probes |
| Controlled/configurable failover/retry/timeout/backoff/cooldown/buffering-threshold/cancel | B4, C1-C5 | Persisted policy/range tests and player tests |
| Source health from playback only | C1-C5 | Health transition tests; no probe audit |
| Live TV favorites/categories/order/hidden/recent | C5 | Persistence/UI tests |
| Unified catalog search | B4, C5 | Existing country search regression plus imported-catalog search tests |
| Embedded subtitle detection/selection/Off | D1-D4 | Renderer-specific tests/frames |
| External SRT/WebVTT/ASS/SSA | D1-D4 | Parser plus per-renderer evidence |
| Native manual file picker | B4, D2-D4 | Platform picker probes |
| Authorized automatic discovery with confidence/manual correction | E1, F2 | Matcher/cache/access tests and candidate-choice UI tests |
| Subtitle styling/timing/reset | F1-F2 | Settings tests/renderer frames |
| Preference persistence/manual selection | F1-F2 | Migration/round-trip/media-key isolation tests |
| Persian/Arabic/Kurdish/mixed RTL | D1, F2, G2 | Renderer frames with Unicode fixtures |
| XMLTV mapping/no-data boundary | B3 stable `channelId` seam; G1 boundary review | Channel identity independent of URL; no feed/programmes invented; XMLTV implementation remains in the separate EPG workstream |
| Migration/backward compatibility | B1, B4, F1, G1 | Legacy fixtures/fresh-install tests |
| Free/no account/no paid API | All | Dependency/account/paywall review |
| Security/privacy/redaction | B2, B4, C1, D1, E1, G1 | URL/secret/size/access tests |
| Performance/cancellation/disposal | B4, C1-C4, D1-D4, F2 | Parse-cache/in-flight/cancel/teardown/long-run tests |
| Existing UI identity and platform input models | B4, C5, D2-D4, F2, G2 | Keyboard/mouse/touch/remote focus evidence |
| CI/build/license/release gates | G1-G2 | Workflow and artifact evidence |

# EPG and Adjacent-Work Boundary

- This plan does not create an EPG feed, programme data, scraper, or paid service.
- The inspected baseline has no XMLTV repository, programme store, or mapping implementation. This plan does not create one. The separate EPG workstream consumes the stable `LogicalChannel.channelId` seam and maps provider channel IDs to that identity, never to a stream URL.
- Missing XMLTV channel IDs, duplicate mappings, timezone differences, malformed files, and missing programmes produce explicit no-data/error states.
- Existing Live TV search and favorites are extended at their current boundaries. The diagnostics and EPG blueprints remain separate workstreams; this plan exposes stable IDs and redacted diagnostics without duplicating their repositories or UI.
- The existing public API identifier is unchanged and is intentionally not reproduced in this plan.

# Risks, Tradeoffs, and Blockers

1. **Platform subtitle capability differs.** AVFoundation, libmpv, and HTML5 video do not expose identical subtitle/style APIs. The plan uses capability records and renderer adapters rather than pretending parity.
2. **ASS/SSA external styling may be lossy or unavailable.** The plan does not convert ASS/SSA to WebVTT as a substitute for renderer support.
3. **webOS secure storage/local files are unverified.** Credential-bearing URLs and local subtitle/playlist files remain rejected/unsupported until evidence exists.
4. **Android TV pickers may be unavailable.** The required behavior is an honest remote-accessible fallback, not simulated access.
5. **Large playlists stress persistence and UI.** Parsing is off the UI path, input ceilings are explicit, unchanged snapshots are cached, and refresh requests are deduplicated.
6. **Manual merge changes logical ownership.** The selected logical ID survives; separated branches receive deterministic IDs and explicit preferences. The UI must explain this before confirmation.
7. **Remux discards embedded subtitles.** Direct playback and external sidecars are separate paths; remux subtitle support is not claimed.
8. **Native-media legal blockers are independent.** Green code/tests do not authorize redistribution or release.
9. **No licensed Iran EPG feed is verified.** EPG remains no-data unless the user supplies a legitimate source.
10. **Remembered source versus explicit priority.** The last successful source is retained for display and manual selection, but automatic attempts always honor the user's priority order.

# Self-Review

- **Audit/spec coverage:** Every Phase B-G requirement maps to a task and acceptance-evidence row. This includes remembered last-successful-source selection, configurable buffering threshold, unified search, discovery confidence/manual correction, fixed Iran composition, public API behavior, migration, favorites/history/Continue Watching/auto-next/link-health, UI/input preservation, separate EPG no-data boundary, security, dependency/license, performance/cancellation, and renderer-evidence constraints.
- **Phase B readiness:** B1-B4 specify exact files, interfaces, fixture contents, expected values, dependency order, GitHub-hosted commands, RED/GREEN expectations, and exclusive ownership. Shared fixture producers precede consumers; B2-S/B2-J, B3 platform tasks, and B4 platform tasks may run in parallel only after their stated gates.
- **Placeholder absence:** No unresolved signature, deferred behavior description, or filler instruction is used. Platform unknowns are expressed as evidence gates with a concrete probe and an honest status. JavaScript B4 repository assertions enumerate their cases instead of delegating test meaning to another task.
- **Type consistency:** `PlaylistRecord`, `ChannelMember`, `ChannelSourceRecord`, `LogicalChannel`, `ChannelPreference`, `ChannelWatchRecord`, `LiveCatalogState`, `UnifiedCatalogSnapshot`, `LivePlaybackContext`, `PlaybackAttemptContext`, `SourceOrigin`, `SourcePolicy`, `SourceHealth`, `SubtitleStyle`, `SubtitleTrack`, `SubtitlePreferences`, and `SubtitleSelectionRecord` retain the same field names and semantics across Dart, Swift, and JavaScript; the five identity-error cases are `ChannelIdentityErrorCode` in Dart, `ChannelIdentityError` in Swift, and `ChannelIdentityError.<code>` errors in JavaScript. `PlaylistParseResult` carries `contentHash`/`inputBytes`; sources include `rendererCapability`, `origin`, and `lastFailedPlaybackAt`; `SourcePolicy` includes `bufferingThresholdMs`; preferences include nullable `lastSuccessfulSourceId`. Refresh reconciliation is by stable `sourceId`; a valid empty refresh is successful zero-channel cleanup, while invalid or nonempty zero-valid refresh is an error with last-good retention; re-enabled sources return to `unverified`; playback-only health transitions and timestamp cooldowns are explicit. `LivePlaybackContext` and `PlaybackAttemptContext` remain runtime-only and are excluded from channel/request JSON; stale callbacks must match generation, source ID, and attempt number; `sourceId` is never substituted for request-local media IDs; `channelId` always means logical channel ID.
- **Parallel safety:** Platform tasks that may run in parallel own disjoint files; shared Swift foundation/player harness files are owned sequentially by their ordered phase tasks. `.github/workflows/ci.yml` is modified sequentially by B1-S, B1-J, B4-S, and finally G1; B4-D/B4-J do not own it. `unified_catalog.js` is created by B3-J and modified by B4-J. `SubtitleSettingsView.swift` is created by D2 and modified by F2. `MainActivity.kt` is owned only by E1. The G1 compatibility/verification documents are created by G1 and modified only by the sequential G2 task. Shared migration/playlist/subtitle/discovery fixtures have one producer and explicit consumers.
- **Verification honesty:** This document is a source/design artifact. No build, test, analysis, formatting, runtime, device, workflow dispatch, commit, or push was performed during its creation. Local runtime remains **NOT VERIFIED**.

---

## Addendum 2026-11-28 — binding decisions for Task B1-S and Task B1-J

Recorded by the project manager after the read-only review of `1382a93..597b4db`, whose High note was
that the persisted timestamp **text form** was never pinned. This addendum is part of the contract:
where it disagrees with a literal snippet above, this addendum wins, and the reason is stated so the
deviation is not mistaken for drift. Items 1 and 2 are already committed and hosted-green at
`fcd456c`; items 3-6 bind the Swift and JavaScript ports.

1. **Canonical timestamp text form (already frozen in Dart by `28019c8`).** Persisted live-catalog
   timestamps are RFC 3339 UTC with exactly three fractional digits — `2026-01-01T00:00:00.000Z` — which
   is what `DateTime.toIso8601String()` writes and what `webos_app/app/js/store.js:70`
   (`new Date().toISOString()`) already writes. **Decoding accepts both** that form and the
   seconds-precision form used by the frozen `Tests/fixtures/migration/catalog-v1.json`
   (`2026-01-01T00:00:00Z`), and normalizes to the canonical form on the next write. Consequence for the
   ports: Swift must **not** reuse the bare `.iso8601` strategy its sibling stores use
   (`Sources/Core/Stores.swift:35`, `:40`, `Sources/Core/DownloadsStore.swift:70`), because Foundation's
   default `ISO8601DateFormatter` excludes fractional seconds and would reject a Dart-written document.
   Swift encodes with `[.withInternetDateTime, .withFractionalSeconds]` and decodes fractionals-first with
   a seconds-precision fallback. Do not "solve" this by editing `_dateText` in Dart: the millisecond form
   is the chosen canonical form and the fixture is frozen.
2. **Symmetric schema-version handling (already frozen in Dart by `28019c8`).** `encode` rejects any
   `schemaVersion` the decoder does not support, with a message that begins exactly
   `Unsupported live catalog schema`, and writes the supported constant rather than the caller's field.
   Swift and JavaScript mirror both halves, sharing that message prefix so a later cross-language
   agreement test can assert on one string.
3. **`supportedSchemaVersion` is a stated contract member, not a Dart-only accident.** The review found
   it as a public Dart symbol absent from every interface list. It is now specified for all three ports:
   Dart `LiveCatalogStateCodec.supportedSchemaVersion` (exists), Swift
   `LiveCatalogStateCodec.supportedSchemaVersion` in `Sources/Core/LiveTVCatalogCodec.swift`, JavaScript
   `CC.liveContracts.supportedSchemaVersion` in `webos_app/app/js/playlist_contracts.js`. Each port must
   reference the constant instead of inlining `1`, and a B2 agreement assertion may compare the three.
4. **Swift runner flags follow the repository, not this document's snippet.** The `run.sh` block above
   calls bare `swiftc`, but every hosted Swift compile in this repo pins the SDK and target
   (`scripts/typecheck.sh:11-12`, `Tests/api/run.sh:18,30-31`, `Tests/player/run.sh:25,103`,
   `build.sh:13,35-36` all use `xcrun swiftc … -target arm64-apple-macos15.0 -sdk "$SDK"`). Whether bare
   `swiftc` resolves the macOS SDK on `macos-15` is **NOT VERIFIED** and must not be settled on the
   owner's Mac, so B1-S uses
   `xcrun swiftc -O -swift-version 5 -module-name CCloudLiveFoundationTests -module-cache-path "$CACHE"
   -target arm64-apple-macos15.0 -sdk "$(xcrun --show-sdk-path)" …` with the same four sources and the
   same `mktemp -d` output path. Everything else in the snippet (the `set -euo pipefail` header, the
   `$ROOT` computation, the `trap` cleanup) stays.
5. **The Swift step must produce countable proof.** No workflow step inspects `macos-typecheck` output,
   and this repo's own Swift idiom is `try?`-and-return (`Sources/Core/Stores.swift:96`), so a missing
   fixture would otherwise yield a silently passing step — the exact failure mode this phase exists to
   prevent. Requirements: the test binary receives the repository root as `argv[1]` (with
   `#filePath`-derived resolution as fallback, since the binary lives in `mktemp -d`), every fixture
   read **hard-fails** on absence or parse error instead of returning, the binary prints a final
   `assertions: <n>` line and exits non-zero on any failed assertion, and `run.sh` greps its own output
   for that line and enforces a floor on `<n>`. B1-S therefore creates the first Swift test baseline in
   this repository; there is no earlier Swift test count to compare against.
6. **B1-J test location: `Tests/webos/live_contracts.test.js`, not `webos_app/test/…`.** The Files block
   above names `webos_app/test/live_contracts.test.js` and a new `node --test webos_app/test/*.test.js`
   step. Use the repository's existing JS test home (`Tests/webos/`, already driven by
   `.github/workflows/ci.yml:167-168`) and extend that step to `node --test Tests/webos/*.test.js`.
   Reason: identical `../..` fixture depth so the proven `path.resolve(__dirname, '../..')` idiom from
   `Tests/webos/transport.test.js:17` ports unchanged; test code stays out of the packaged `app/` tree;
   and that step already prints `# tests / # pass / # fail / # skipped`, which is the countable proof
   item 5 requires. This is a test-placement decision only — the assertions, the ES2017 ceiling (no
   `let`/`const`/optional chaining/nullish coalescing), the `window.CC` attachment and the
   "does not access `localStorage`" rule from the task body are unchanged and still binding.
7. **Ordering reaffirmed.** B1-D → B1-S → B1-J → B2. B1-J follows B1-S because B1-S is the run that
   reads the frozen fixture from a second language, which is where a residual wire-format mismatch would
   surface. Neither B1-S nor B1-J may touch `UserDefaults`, `localStorage`, Application Support, playback
   code, UI code, or any consumer: migration triggers and disk I/O belong to B4-S/B4-J.
