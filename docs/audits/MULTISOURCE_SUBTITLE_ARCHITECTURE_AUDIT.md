# Multi-Source IPTV + Advanced Subtitle Architecture Audit

**Phase:** A — read-only architecture audit and implementation-ready design  
**Date:** 2026-11-25  
**Baseline:** `ci/github-first-foundation` at `3d6e8762ce8826a52297f83b5f6952a26f15ba44`  
**Platforms:** Swift/macOS; Flutter Android phone, Android TV, Windows; JavaScript/LG webOS  
**Status vocabulary:** Supported / Partially Supported / Unsupported / Not Yet Verified

## 1. Executive conclusion

The repository already contains substantial **multiple-playback-source support for one channel**, but it does **not** contain the requested **multiple-independent-playlist product**.

Reusable foundations are:

- Swift `LiveTVM3U.parse`, `LiveTVNameKey`, `LiveTVChannel.sources`, `PlaybackController` source walking, same-source retries, manual source selection, remux fallback, reconnect and persistent link health.
- Flutter `parseM3u`, `liveNameKey`, `LiveTvChannel.sources`, `PlayerArgs.forChannel`, source rotation, same-link recovery, software-decoder fallback and persistent link health.
- webOS channel/source menus and the existing HTML5 player, although webOS has no automatic failover or source-health subsystem.
- Existing Live TV search, Continue Watching, watch history, auto-next and media favorites.

The principal missing pieces are:

1. Stable playlist identity, playlist ownership and refresh/provenance records.
2. A logical channel identity independent of playback URL.
3. Cross-playlist channel association with manual merge/split controls.
4. Application-level subtitle track enumeration, selection and external-file loading on every platform.
5. Native file-picker adapters and authorized-directory discovery.
6. Versioned subtitle preferences and renderer capability reporting.
7. A webOS automatic-failover policy.
8. Runtime proof for subtitle rendering, ASS/SSA behavior, Persian/Arabic shaping and Android TV/webOS remote interactions.

The recommended implementation is an **extension of the existing playback architecture**, not a replacement player and not a disconnected subtitle subsystem.

The first independently testable implementation slice should be the **pure Multi-Source foundation**: versioned playlist/channel/source contracts, parser results, identity resolution, source registry and migration fixtures. It requires no playback, UI, network or device changes.

## 2. Scope, method and evidence boundaries

### 2.1 Objective

This audit answers six implementation questions:

1. Which playlist import, parser, catalog, channel, source and failover components already exist and can be reused?
2. Which embedded/external subtitle, track-selection, file-picker, persistence, styling, timing and RTL capabilities exist per platform?
3. Which limitations belong to the actual playback engine or platform rather than to missing application code?
4. Which migrations are required to preserve playlists, favorites, history, Continue Watching, EPG mappings and preferences?
5. Which dependencies are present or missing, and what is their license impact?
6. What exact Phases B–G sequence and first independently testable slice should be implemented?

### 2.2 Work completed

- Read the full supplied specification.
- Inspected Swift, Flutter, Android and webOS source paths for playlist parsing, catalog construction, playback, recovery, subtitles, file access, persistence, tests and CI.
- Checked declared Flutter dependencies separately from resolved lockfile versions.
- Consulted official platform and playback-engine documentation for capabilities not established by repository code.
- Consulted the concurrent legal artifacts only as risk evidence; they are not committed baseline evidence.
- Reconciled the requested work with existing Live TV search and the earlier favorites/diagnostics/EPG blueprint.

### 2.3 Work not performed

No application code, workflow, dependency, configuration or execution-log file was edited. No local build, test, analysis, formatting, syntax probe, dependency installation, workflow dispatch, provider request, signing, packaging or git mutation was performed.

Consequently:

- Repository findings are source-confirmed.
- Official API findings are documentation-confirmed.
- Actual rendering and device behavior remain **Not Yet Verified** unless explicitly stated otherwise.
- No existing runtime failure or passing test is claimed by this audit.

### 2.4 Concurrent-work boundary

The working tree contains unrelated legal-packaging changes, including modifications to workflows, `build.sh`, Flutter packaging files and untracked `Legal/`, `NOTICE`, `SOURCES.md` and `THIRD_PARTY_NOTICES.md`.

Those changes were not modified and are not attributed to the baseline commit. Any later dependency or packaging implementation must coordinate with that work rather than overwrite it.

### 2.5 Evidence classes

| Class | Meaning |
|---|---|
| Repository evidence | Directly observed in current source, manifests, tests or workflow files |
| Official API documentation | Capability documented by the platform/vendor; not proof of CCloud implementation |
| Project constraint | Carried forward from the approved product/EPG direction; not a new runtime claim |
| Inference | Architectural conclusion drawn from cited evidence |
| Not Yet Verified | Requires hosted runtime, emulator, device or release-specific evidence |

## 3. Current-state findings

### 3.1 Swift/macOS

#### Playlist parsing and catalog

`LiveTVM3U` already parses IPTV-style `#EXTINF` entries and groups stream URLs by normalized `tvg-id`:

- Entry and conversion contract: `Sources/Core/LiveTVM3UClient.swift:116-134`
- Parser: `Sources/Core/LiveTVM3UClient.swift:136-157`
- Attribute and identity extraction: `Sources/Core/LiveTVM3UClient.swift:160-179`
- Name normalization: `Sources/Core/LiveTVM3UClient.swift:223-266`

Reusable behavior includes:

- Quality suffix removal from display names.
- First-seen stream ordering.
- Exact URL deduplication within an entry.
- Persian/Arabic letter, digit, width and diacritic normalization.
- Country extraction from provider identifiers.

Important limitations:

- The parser is an **IPTV channel-list parser**, not a general HLS master-manifest parser.
- It does not retain `tvg-logo`, original `tvg-id`, language or arbitrary provider metadata.
- It does not return structured parse issues for malformed or partially invalid input.
- A file named `.m3u8` is not necessarily a channel playlist; content detection must distinguish an `#EXTINF` channel list from an `#EXT-X-STREAM-INF` playback manifest.

The current Iran catalog is a fixed network composition, not a user playlist registry:

- Singleton/cache setup: `Sources/Core/LiveTVCatalog.swift:25-76`
- Famelack/iptv-org merge: `Sources/Core/LiveTVCatalog.swift:80-137`

The merge adds backup URLs to Famelack rows but does not add iptv-org-only channels. This behavior must remain intact. User playlists should be represented as additional independent catalog sources, not by silently changing the established Iran-list composition.

#### Channel and source identity

Current models:

- `LiveTVStreams`: `Sources/Core/LiveTVModels.swift:5-18`
- `LiveTVChannel`: `Sources/Core/LiveTVModels.swift:20-79`
- Playback request conversion: `Sources/Core/LiveTVModels.swift:83-105`
- `MediaSource`: `Sources/Core/Models.swift:33-110`
- `PlaybackRequest`: `Sources/Core/Models.swift:420-471`

`MediaSource.id` is request-local and is not a persistent playlist-source identity. `LiveTVChannel.nanoid` is the closest existing channel identifier, but decoding can generate a random UUID when the upstream identifier is absent:

- `Sources/Core/LiveTVModels.swift:72`

That fallback is unsafe for persisted favorites, EPG mappings or source associations. The target design must introduce a separate stable `channelId` and retain `nanoid` as a legacy/provider key.

`LiveTVCountryMeta` contains timezone information, but `LiveTVCountry` discards it:

- `Sources/Core/LiveTVModels.swift:148-192`

Channel-level EPG timezone therefore cannot be inferred safely from the current country model.

#### Playback and failover

`PlaybackController` already implements much of the required per-channel source behavior:

- Direct AVPlayer for MP4/HLS/DASH and FFmpeg-to-HLS fallback for unsupported sources: `Sources/Player/PlaybackController.swift:55-70`
- Preferred source, fresh links before deprioritized links: `Sources/Player/PlaybackController.swift:211-220`
- Failure recording and source rotation: `Sources/Player/PlaybackController.swift:229-241`
- Two same-source reload attempts: `Sources/Player/PlaybackController.swift:244-251`
- Manual source selection: `Sources/Player/PlaybackController.swift:342-354`
- Direct timeout and remux setup: `Sources/Player/PlaybackController.swift:468-585`
- Readiness, failure and success handling: `Sources/Player/PlaybackController.swift:687-785`
- Stall/connectivity recovery: `Sources/Player/PlaybackController.swift:812-863`

This logic should be extended, not replaced.

Gaps relative to the specification are:

- No stable `playlistId` or `sourceId`.
- No persisted user-defined source ordering.
- No source enable/disable state.
- No explicit failure taxonomy separating timeout, transport, demux, decoder, unsupported media and temporary buffering.
- No configurable retry/cooldown policy exposed to the user.
- No unified source diagnostic record containing provenance and redacted errors.

#### Subtitle and remux limitations

The Swift player currently enumerates only audible tracks:

- Audio-track APIs: `Sources/Player/PlaybackController.swift:356-435`
- `.audible` handling: `Sources/Player/PlaybackController.swift:511-542`
- Ready-state refresh: `Sources/Player/PlaybackController.swift:687-710`

No application-level `.legible`, `AVMediaSelectionGroup`, external subtitle loader or subtitle renderer was found.

The FFmpeg remux path maps only video and audio:

- `Sources/Player/RemuxSession.swift:295-320`

Embedded subtitle streams are therefore discarded by the current remux command. Subtitle behavior must be defined separately for:

1. Direct AVPlayer playback.
2. FFmpeg remux playback.
3. External sidecar playback.

#### File access and persistence

No `NSOpenPanel`, security-scoped bookmark or authorized-directory browser was found.

Existing storage is:

- Media favorites: unversioned JSON array at Application Support `CCloudMac/favorites.json`: `Sources/Core/Stores.swift:7-105`
- History/Continue Watching: unversioned JSON at `CCloudMac/history.json`: `Sources/Core/Stores.swift:109-293`
- Settings in `UserDefaults`: `Sources/Core/Stores.swift:319-397`
- Downloads under `~/Downloads/CCloud`: `Sources/Core/DownloadsStore.swift:54-88`

The downloads directory is not evidence of user authorization to scan it. Automatic subtitle discovery must be limited to a directory explicitly selected by the user.

### 3.2 Flutter Android, Android TV and Windows

#### Playlist parsing and catalog

Reusable Flutter components:

- `M3uEntry`: `flutter_app/lib/core/live_catalog.dart:18-32`
- `liveNameKey`: `flutter_app/lib/core/live_catalog.dart:40-105`
- `parseM3u`: `flutter_app/lib/core/live_catalog.dart:153-177`
- Entry/attribute extraction: `flutter_app/lib/core/live_catalog.dart:179-207`
- Iran merge: `flutter_app/lib/core/live_catalog.dart:220-279`
- Fixed catalog loading/cache: `flutter_app/lib/core/live_catalog.dart:290-431`

The Flutter parser has the same semantic boundary as Swift: it parses `#EXTINF` channel lists, not HLS master manifests, and does not yet produce a provenance-rich playlist document.

#### Channel identity and playback request

- `MediaSource`: `flutter_app/lib/core/models.dart:61-141`
- `LiveTvChannel`: `flutter_app/lib/core/models.dart:356-418`
- Existing fallback identifier: `flutter_app/lib/core/models.dart:373`
- `PlayerArgs`: `flutter_app/lib/core/playback.dart:50-191`
- Channel request conversion: `flutter_app/lib/core/playback.dart:156-190`
- Source selection helper: `flutter_app/lib/core/playback.dart:193-213`

The fallback `name-country` identifier is deterministic but not playlist-aware and can collide. `PlayerArgs.forChannel` currently passes streams without stable channel, playlist or source provenance.

#### Playback and failover

The Flutter player already contains:

- Network-oriented mpv configuration: `flutter_app/lib/screens/player_screen.dart:147-166`
- Playback subscriptions: `flutter_app/lib/screens/player_screen.dart:169-254`
- Two same-link reload attempts and software-decoder fallback before source rotation: `flutter_app/lib/screens/player_screen.dart:313-352`
- Link failure/success recording: `flutter_app/lib/screens/player_screen.dart:354-365`
- Media opening: `flutter_app/lib/screens/player_screen.dart:428-459`
- Existing auto-next: `flutter_app/lib/screens/player_screen.dart:629-657`

This is a strong base for Phase C. The missing work is policy and provenance, not a new player.

#### Subtitle state

Track subscriptions exist, but only audio tracks are processed:

- Track subscriptions: `flutter_app/lib/screens/player_screen.dart:228-240`
- Audio-only `_applyTracks`: `flutter_app/lib/screens/player_screen.dart:256-268`

`tracks.subtitle`, `track.subtitle`, `setSubtitleTrack`, external subtitle files and subtitle preferences are not used by the application.

#### File access

The Android manifest declares only network and wake-lock permissions:

- `flutter_app/android/app/src/main/AndroidManifest.xml:1-12`

No SAF document/tree intent handling or persistable URI permission flow exists. `path_provider` and the downloads store provide ordinary app/storage paths, not user-authorized directory access:

- `flutter_app/lib/core/downloads_store.dart:220-247`

#### Dependencies

Declared direct dependencies are at `flutter_app/pubspec.yaml:9-26`.

Resolved versions include:

- `media_kit 1.2.6`: `flutter_app/pubspec.lock:320-327`
- `media_kit_libs_android_video 1.3.8`: `flutter_app/pubspec.lock:328-335`
- `media_kit_libs_windows_video 1.0.11`: `flutter_app/pubspec.lock:336-343`
- `media_kit_video 1.3.1`: `flutter_app/pubspec.lock:344-351`
- `shared_preferences 2.5.6`: `flutter_app/pubspec.lock:568-575`
- `path_provider 2.1.6`: `flutter_app/pubspec.lock:432-439`

Additional resolved dependencies:

- `intl 0.20.3` is transitive only: `flutter_app/pubspec.lock:232-239`
- `xml 7.0.1` is transitive only: `flutter_app/pubspec.lock:893-900`

There is no declared direct file picker, secure-storage package, subtitle parser, timezone database or XMLTV parser. A transitive package must not be used as though it were a stable direct dependency.

### 3.3 webOS

#### Architecture and storage

webOS uses browser-style JavaScript IIFEs under `CC`:

- Script order: `webos_app/app/index.html:15-32`
- RTL document: `webos_app/app/index.html:1-32`
- Persistent storage wrapper: `webos_app/app/js/util.js:40-56`

`CC.store` prefixes keys with `ccloud.` and silently falls back on parse/storage failure. That behavior is acceptable for legacy settings but insufficient for playlist import, where the user must be told if persistence failed.

Current stores contain settings, media favorites and history only:

- `webos_app/app/js/store.js:11-145`

There is no playlist, Live TV favorite, EPG or subtitle-preference store.

#### Catalog and sources

The webOS API layer normalizes backend sources and Live TV channels:

- Source normalization/preference: `webos_app/app/js/api.js:32-49`
- Source preference: `webos_app/app/js/api.js:218-229`
- Live TV state/countries/channels: `webos_app/app/js/api.js:265-323`
- Channel normalization: `webos_app/app/js/api.js:326-344`

There is no local M3U parser or user playlist manager.

#### Player and failover

The player uses a plain HTML5 `<video>` element:

- Markup: `webos_app/app/js/player.js:24-53`
- Source state: `webos_app/app/js/player.js:56-63`
- Event listeners: `webos_app/app/js/player.js:83-93`
- Media loading: `webos_app/app/js/player.js:96-115`

Manual quality/channel switching exists:

- `webos_app/app/js/player.js:236-296`

Automatic source rotation does not. The error path offers retry/back rather than selecting another source:

- `webos_app/app/js/player.js:299-320`

No text-track API, `<track>` element, `VTTCue`, subtitle renderer, link-health store or automatic failover state machine was found.

The player comment claiming broad MKV support is not runtime evidence. Codec/container support must be established by device tests.

### 3.4 Cross-platform absences established by targeted search

Targeted searches found no application implementation for:

- Swift `.legible`, `AVMediaSelectionOption`, subtitle track selection, `NSOpenPanel` or security-scoped bookmarks.
- Flutter `track.subtitle`, `SubtitleTrack`, `setSubtitleTrack`, `file_picker`, SAF document/tree handling or external subtitle discovery.
- webOS `textTracks`, `addTextTrack`, `TextTrack`, `VTTCue`, `<track>` or local file selection.

These are code-search findings, not claims about undocumented platform capability.

## 4. Compatibility matrices

### 4.1 Current application implementation

These values describe the repository as inspected, not hypothetical engine capability. Existing behavior was not re-executed during Phase A.

| Feature | Android | Android TV | Windows | macOS | webOS |
|---|---|---|---|---|---|
| Multiple independent playlists | Unsupported | Unsupported | Unsupported | Unsupported | Unsupported |
| Multiple playback sources per channel | Partially Supported | Partially Supported | Partially Supported | Partially Supported | Partially Supported |
| Manual source selection | Partially Supported | Partially Supported | Partially Supported | Partially Supported | Partially Supported |
| Automatic failover after playback failure | Partially Supported | Partially Supported | Partially Supported | Partially Supported | Unsupported |
| Persistent user source ordering | Unsupported | Unsupported | Unsupported | Unsupported | Unsupported |
| Source enable/disable and provenance | Unsupported | Unsupported | Unsupported | Unsupported | Unsupported |
| Embedded subtitle detection/selection | Unsupported | Unsupported | Unsupported | Unsupported | Unsupported |
| External subtitle loading | Unsupported | Unsupported | Unsupported | Unsupported | Unsupported |
| Manual subtitle file picker | Unsupported | Unsupported | Unsupported | Unsupported | Unsupported |
| Automatic subtitle discovery | Unsupported | Unsupported | Unsupported | Unsupported | Unsupported |
| App-level subtitle styling/timing | Unsupported | Unsupported | Unsupported | Unsupported | Unsupported |
| Persian/Arabic subtitle rendering | Not Yet Verified | Not Yet Verified | Not Yet Verified | Not Yet Verified | Not Yet Verified |

“Partially Supported” for multiple sources means that source arrays, source menus and some recovery behavior exist, but stable playlist/source identity, ownership, ordering, status and complete cross-platform failover do not.

### 4.2 Engine and platform capability

These values must not be presented as current CCloud product support.

| Capability | Android | Android TV | Windows | macOS | webOS |
|---|---|---|---|---|---|
| Subtitle-track API exposed by playback engine | Supported | Supported | Supported | Supported | Partially Supported |
| Embedded subtitle runtime rendering in CCloud | Not Yet Verified | Not Yet Verified | Not Yet Verified | Not Yet Verified | Unsupported |
| External subtitle API available to app | Supported | Supported | Supported | Not Yet Verified | Partially Supported |
| External SRT/VTT/ASS/SSA runtime rendering | Not Yet Verified | Not Yet Verified | Not Yet Verified | Not Yet Verified | Partially Supported |
| Native single-file picker API | Supported | Not Yet Verified | Supported | Supported | Not Yet Verified |
| Persistable authorized-directory access | Supported | Not Yet Verified | Supported | Supported | Not Yet Verified |
| ASS/SSA native rendering | Not Yet Verified | Not Yet Verified | Not Yet Verified | Not Yet Verified | Unsupported |
| Renderer-controlled subtitle appearance | Not Yet Verified | Not Yet Verified | Not Yet Verified | Partially Supported | Not Yet Verified |
| Visible Persian/mixed RTL rendering | Not Yet Verified | Not Yet Verified | Not Yet Verified | Not Yet Verified | Not Yet Verified |

Key qualifications:

- **macOS:** AVFoundation officially exposes legible media-selection groups and renders selected subtitles in `AVPlayerLayer`, the surface used by CCloud. This is API capability, not proof that the current application selects or correctly displays tracks.
- **Flutter:** media_kit 1.2.6 exposes subtitle streams and `setSubtitleTrack`; mpv supports external subtitle files and ASS/SSA rendering. Actual Android/Windows bundled-runtime behavior remains unverified.
- **webOS:** LG officially supports external WebVTT, with version, VoD and device caveats. General embedded-subtitle support is not established.
- **Android TV:** SAF exists, but remote-only picker usability is unverified.
- **webOS local files:** no application-facing local-file route has been verified.

## 5. Recommended target architecture

```text
Playlist import/refresh
        |
        v
PlaylistRepository ----> PlaylistParserRegistry
        |                         |
        |                         v
        |                  PlaylistParseResult
        v                         |
SourceRegistry <------------------+
        |
        v
ChannelIdentityResolver
        |
        v
UnifiedChannelCatalog
        |
        v
ChannelSourceResolver ----> existing PlaybackController / Player
        |                              |
        |                              v
        |                     verified playback outcomes
        |                              |
        +-------- SourceHealth <-------+
                                       |
                                       v
                             existing diagnostics surface

Active media session
        |
        +--> SubtitleTrackRepository
        |          |
        |          +--> embedded-track adapter
        |          +--> external-file adapter
        |          +--> authorized discovery
        |
        v
SubtitleRendererAdapter
        |
        +--> AVFoundation / CCloud cue overlay
        +--> media_kit / libmpv
        +--> webOS WebVTT TextTrack, only after device verification
```

This preserves the existing playback engines and UI shells.

### 5.1 Required contracts

| Contract | Required fields/rules |
|---|---|
| `PlaylistRecord` | `schemaVersion`, `playlistId`, display name, remote/local kind, redacted location, secret reference where required, enabled state, created/updated timestamps, last successful refresh, last error, channel count, parser version |
| `PlaylistParseResult` | Entries, original provider metadata, source provenance, structured issues, content hash, detected document kind |
| `LogicalChannel` | Stable `channelId`, display metadata, normalized name, provider identifiers with namespace, logo/group/country/language, manual association state |
| `ChannelSource` | Stable `sourceId`, `channelId`, `playlistId`, stream URL reference, user label, priority, enabled state, renderer capability, last actual playback outcome |
| `PlaybackContext` | Existing request fields plus optional `channelId`, `sourceId`, `playlistId`, stable media identity and request generation token |
| `PlaybackFailure` | Classification, recoverability, attempt number, redacted detail, originating source |
| `SubtitleTrackRef` | Stable track reference, embedded/external origin, format, language/title, renderer handle, availability, source label |
| `SubtitleCue` | Start/end time, Unicode text, optional renderer-neutral style metadata |
| `SubtitlePreferences` | Schema version, preferred language, default state, appearance, delay, capability flags, per-media manual override |
| `EPGMapping` | `xmltvChannelId` to stable `channelId`; never keyed by stream URL |

### 5.2 Stable identity rules

1. `playlistId` is generated once at import and survives refresh, rename, disable and re-enable.
2. `channelId` is persisted independently of stream URL.
3. Provider identifiers are namespaced. A bare `tvg-id` from two providers is not automatically the same identity.
4. Exact provider ID plus compatible metadata may create an automatic association.
5. Normalized-name similarity creates a **candidate**, not an automatic merge.
6. Manual merge and split decisions are persisted.
7. Missing legacy identifiers receive deterministic migration keys; random per-decode IDs must not become persisted identities.
8. Source refresh reconciliation preserves user priority and enabled state when an entry remains recognizable.
9. The same URL in two playlists may retain two provenance records, but a playback session does not retry the identical URL twice.
10. URL query/fragment stripping remains useful for legacy link-health matching, but URL is not channel identity.
11. Built-in catalog records retain their current provenance and merge behavior.
12. Public API transport, cache and identifier behavior remain unchanged; the identifier value is intentionally omitted from this audit.

## 6. Platform-specific change boundaries

### 6.1 Swift/macOS

Recommended additions:

- `PlaylistModels.swift`
- `PlaylistRepository.swift`
- `PlaylistParserRegistry.swift`
- `ChannelIdentityResolver.swift`
- `ChannelSourceResolver.swift`
- `PlaybackFailure.swift`
- `SubtitleModels.swift`
- `SubtitleTrackAdapter.swift`
- `AVFoundationSubtitleAdapter.swift`
- `SubtitleCueOverlayAdapter.swift`

Minimal modifications:

- Extend the existing M3U parsing path with a richer parse-result adapter while preserving `LiveTVM3U.parse` for the fixed catalog.
- Add optional catalog provenance to `LiveTVChannel`; do not replace `nanoid` in existing callers.
- Add optional context fields to `PlaybackRequest`.
- Keep source walking, remux and reconnect logic in `PlaybackController`.
- Add subtitle adapter calls at the existing player-session boundary in `Sources/UI/Detail/PlayerScreen.swift:285-392`.
- Store security-scoped bookmark data, not arbitrary absolute paths, for authorized local folders.
- Store credential-bearing URL secrets in Keychain and persist only a redacted location plus secret reference.

#### macOS subtitle strategy

- **Direct embedded tracks:** enumerate `.legible`, expose language/title, select through `AVPlayerItem.select(_:in:)`, and verify visible rendering on the real `AVPlayerLayer`.
- **External SRT/WebVTT:** use a CCloud-owned cue overlay synchronized to AVPlayer time. This is a renderer adapter, not a second playback engine.
- **External ASS/SSA:** remain **Not Yet Verified** until a hosted renderer probe establishes an acceptable native path. Do not claim support by stripping ASS styling and displaying plain text.
- **Remux embedded tracks:** currently discarded. Do not promise embedded subtitle selection in the remux path until a hosted FFmpeg/HLS mapping probe succeeds.
- **Styling:** do not rely on `AVPlayer.textStyleRules` for universal embedded-subtitle styling; Apple documents it as WebVTT-specific and ineffective for local MP4/MOV embedded tracks.

### 6.2 Flutter

Recommended additions:

- `core/playlist_models.dart`
- `core/playlist_repository.dart`
- `core/playlist_parser.dart`
- `core/channel_identity_resolver.dart`
- `core/channel_source_resolver.dart`
- `core/playback_failure.dart`
- `core/subtitle_models.dart`
- `core/subtitle_preferences.dart`
- `platform/subtitle_track_adapter.dart`
- `platform/file_picker_adapter.dart`

Minimal modifications:

- Preserve `parseM3u` and add a provenance-rich wrapper.
- Add optional stable IDs to `LiveTvChannel` and `PlayerArgs`.
- Process `tracks.subtitle` in `player_screen.dart`.
- Use `Player.setSubtitleTrack` for embedded selection.
- Use `SubtitleTrack.data` for validated external bytes where content-URI handling is unreliable.
- Keep existing retry, software-decoder and source-rotation behavior; extract its policy into a pure testable state machine.
- Store large playlist/catalog snapshots as versioned JSON files in application support, not as large SharedPreferences strings.
- Keep legacy favorites/history keys unchanged.
- Use SAF persistable URI grants for Android directory discovery. If the chosen picker package cannot provide the required grant lifecycle, implement a small native SAF adapter instead.
- Store secrets through a reviewed platform secure-storage adapter; do not persist credential-bearing URLs in plain SharedPreferences.

### 6.3 webOS

Recommended additions:

- `CC.m3u` parser module.
- `CC.playlist` versioned repository.
- `CC.subtitle` track/preference module.
- `CC.failover` bounded state machine.

Minimal modifications:

- Insert new scripts after storage/network dependencies and before player/screens in `webos_app/app/index.html:15-32`.
- Keep ES2017/Chromium 68 compatibility.
- Add explicit persistence error reporting for new playlist stores instead of inheriting silent `CC.store` failures.
- Extend the existing player rather than creating another player.
- Add automatic failover only for classified fatal playback failures, never for ordinary `waiting` events.
- Add WebVTT `TextTrack`/cue handling only after a webOS device probe proves visible rendering.
- Do not advertise local playlist/subtitle import until a real webOS file-access route is verified.
- Do not persist credential-bearing playlist URLs in plain localStorage without a verified secure-storage mechanism.

## 7. Subtitle implementation strategy

### 7.1 Format and renderer policy

| Format/source | macOS target | Flutter target | webOS target |
|---|---|---|---|
| Embedded direct media | AVFoundation legible selection; runtime gate | media_kit subtitle tracks; runtime gate | Unsupported as a general officially supported capability |
| Embedded remuxed media | Not Yet Verified; current remux drops subtitles | Verify through actual remux/player path if used | Not Yet Verified |
| External SRT | CCloud cue overlay after parser tests | media_kit/libmpv after runtime tests | Unsupported unless a custom renderer is separately proven |
| External WebVTT | CCloud cue overlay after parser tests | media_kit/libmpv after runtime tests | Partially Supported at engine level; device-gated |
| External ASS/SSA | Not Yet Verified | media_kit/libmpv/libass after runtime tests | Unsupported |
| HLS subtitle renditions | Verify exact AVFoundation/media behavior | Verify exact media_kit/mpv behavior | Version/VoD limited; Not Yet Verified |
| Bitmap subtitles | Renderer-dependent; no styling promise | Renderer-dependent; no styling promise | Unsupported unless device-proven |

### 7.2 File access policy

- Never scan Downloads, external storage or arbitrary directories by default.
- Single-file import requires an explicit picker action.
- Automatic discovery requires an explicitly authorized root.
- Android uses SAF and persistable URI permissions.
- macOS uses `NSOpenPanel` and security-scoped bookmarks.
- Windows uses the native picker and stores only user-selected locations.
- webOS local discovery remains blocked pending platform evidence.
- IPTV URLs never imply access to neighboring subtitle files.

### 7.3 Discovery and matching

Matching order:

1. Exact media basename.
2. Basename plus recognized language suffix.
3. Explicit episode identifier.
4. Supported release naming patterns.
5. Manual association.

Rules:

- Ambiguous matches require user confirmation.
- Unrelated files in the same directory must not be attached.
- Cache by file identity plus modification time/size/hash.
- Revalidate after file changes.
- Persist file references, not unrestricted filesystem scans.
- Never use a preferred language to select an unrelated track.

### 7.4 Preferences and RTL

- Global preferences provide defaults.
- A manual selection creates a per-media/session override.
- Automatic language selection applies only when no manual override exists.
- Delay is scoped to the selected track/media where appropriate.
- UI controls are enabled only when the active renderer reports the capability.
- Persian, Arabic, Kurdish and mixed RTL/LTR text must use platform shaping and bidi layout.
- Manual string reversal is prohibited.
- Font fallback, diacritics, numbers, punctuation and long lines require visual fixtures.

### 7.5 Track selection behavior

- Embedded and external tracks remain distinguishable in the UI.
- Duplicate renderer exposures of the same track are collapsed without losing origin metadata.
- Off is an explicit state, not an empty track list.
- Missing language metadata is displayed as unknown rather than guessed.
- Unsupported tracks remain visible as unavailable when the renderer exposes them, with a clear reason.
- Switching tracks does not restart playback unless the renderer requires it.
- Loading an external track during playback is attempted without restart; platforms that cannot do this must report the limitation before implementation is claimed.

## 8. Migration and backward compatibility

### 8.1 Existing data inventory

| Platform | Media favorites | History/Continue Watching | Settings | Link health | Multi-Source/subtitles |
|---|---|---|---|---|---|
| macOS | `favorites.json`, unversioned array | `history.json`, unversioned array | `UserDefaults` | `UserDefaults` via `LinkHealth` | Absent |
| Flutter | `ccloud.favorites`, JSON-string list | Existing history keys | `AppSettings` | `ccloud.linkHealth` | Absent |
| webOS | `CC.store` media favorites | `CC.store` history | `CC.store` settings | Absent | Absent |

Evidence:

- `Sources/Core/Stores.swift:7-397`
- `flutter_app/lib/core/stores.dart:21-568`
- `flutter_app/lib/core/link_health.dart:6-137`
- `webos_app/app/js/store.js:11-145`
- `webos_app/app/js/util.js:40-56`

### 8.2 Existing playlists and catalog behavior

There are no persisted user-managed playlists in the inspected baseline. Existing “playlists” are fixed remote catalog inputs and in-memory caches.

Migration requirements are therefore:

- Preserve the built-in Famelack/iptv-org inputs and their current merge rules.
- Do not require users to reimport anything to retain current single-source playback.
- Represent built-in inputs as read-only built-in playlist records with stable provenance.
- Keep user-imported playlists independent from the built-in Iran list.
- Preserve existing channel metadata and stream order when adapting legacy entries.
- Do not treat a cache file as a user playlist without explicit provenance.

### 8.3 Migration rules

1. Do not rewrite legacy favorites or history merely to add Multi-Source fields.
2. New stores use `{ "schemaVersion": 1, ... }` envelopes.
3. Readers accept both legacy and versioned forms during transition.
4. Writes use temporary-file replacement or an equivalent atomic strategy.
5. A failed migration leaves the original data intact and reports an error.
6. Fresh installations start at schema version 1.
7. Upgrade tests load fixtures representing the previous release.
8. Existing media favorites remain separate from future Live TV favorites.
9. Continue Watching and auto-next retain current behavior and identifiers.
10. Existing settings gain safe defaults; absent subtitle preferences mean no automatic override.
11. Link health may be migrated to `sourceId`, with sanitized URL matching retained for legacy records.
12. EPG mappings, when implemented by the prior blueprint, reference `channelId`, never stream URL.
13. Rollback does not delete new playlist, source-association or preference records.

### 8.4 Favorites, history and Continue Watching safeguards

- Media favorites keep their current storage keys and JSON shapes.
- Live TV favorites remain a separate future store owned by the earlier blueprint.
- Watch history and Continue Watching keep current media identifiers and resume semantics.
- Source refresh never rewrites media history.
- Channel association changes never merge movie/series favorites with Live TV favorites.
- Subtitle preference migration never changes an existing manual media selection.

### 8.5 EPG mapping migration

No XMLTV mapping store exists in the inspected baseline. When the EPG blueprint is implemented:

- Mapping records use stable `channelId` plus `xmltvChannelId`.
- Missing XMLTV IDs remain unmapped.
- Duplicate mappings are surfaced for user/provider resolution.
- Timezone comes from explicit feed/provider metadata, not a country-level guess.
- No programme record is created from a stream URL or inferred schedule.
- The no-data seam in section 11 remains authoritative when no legitimate feed is available.

## 9. Dependencies and license impact

### 9.1 Present and reusable

- AVFoundation/AppKit: platform frameworks.
- FFmpeg: already used by macOS remux; existing native-license obligations apply.
- media_kit/media_kit_video: already declared and resolved.
- `shared_preferences`, `path_provider`: already present.
- `intl` and `xml`: transitive only; promote to direct dependencies only if the implementing code imports them.

### 9.2 Missing or candidate dependencies

| Need | Candidate | Current status | License/security gate |
|---|---|---|---|
| Flutter file/directory picker | `file_picker` | Not declared; public version observed during research: 13.4.1 | MIT candidate; pin exact version, audit transitive packages/archive hashes, prove Android TV and persistable-URI behavior |
| Flutter secure storage | Platform secure-storage adapter/package | Not selected | Must verify Android Keystore/Windows credential protection and exact licenses before adoption |
| Subtitle parser | CCloud-owned SRT/WebVTT parser or reviewed package | Not selected | Prefer small in-repo parsers where practical; any package requires provenance and license review |
| XMLTV | Direct `xml` dependency if EPG work proceeds | `xml 7.0.1` currently transitive | Belongs to the EPG workstream; do not silently rely on transitive resolution |
| Timezone database | Not selected | Absent | Belongs to EPG; no country-timezone shortcut |
| webOS tests | Node built-in test runner/VM harness | No test suite exists | No new runtime dependency required |

No dependency was installed or selected during Phase A.

### 9.3 Existing native-media blockers

The concurrent legal artifacts report:

- macOS Homebrew FFmpeg provenance is not release-pinned.
- Android mpv/FFmpeg relinkable objects and a verified relinking procedure are absent.
- Windows native mpv/FFmpeg provenance and complete source package are incomplete.
- The MIT license of media_kit wrappers does not change native-library obligations.

Evidence:

- `SOURCES.md:78-116`
- `THIRD_PARTY_NOTICES.md:29-69`

These are pre-existing production-redistribution blockers, not issues introduced by this audit. New picker, secure-storage or parser dependencies must be added to the canonical notices and source provenance before release.

## 10. Security and privacy limits

### 10.1 Untrusted inputs

Playlist URLs, stream URLs, local playlist files, subtitle files and XMLTV documents are untrusted input.

Required controls:

- Validate URL schemes against a platform/engine allowlist.
- Remote playlist documents must not inject local `file:` or `content:` stream references.
- Reject path traversal and unsupported local schemes.
- Never execute imported content.
- Never disable TLS certificate validation.
- Never add scraping services or mandatory paid subtitle APIs.
- Do not introduce unnecessary network requests.

### 10.2 Resource limits

Initial implementation limits must be explicit and configurable:

- Playlist response/decode limit: 10 MiB.
- Parsed channel-entry limit: 100,000 per playlist.
- Subtitle file limit: 5 MiB.
- Parsed cue limit: 100,000 per subtitle.
- Reject non-finite, negative or excessively long cue timings.
- Parse large documents off the UI thread.
- Cancel obsolete refresh, parse and discovery operations.

These are proposed safety defaults, not measured performance results.

### 10.3 Credential and URL handling

- Strip userinfo and sensitive query values from logs, diagnostics and crash-safe metadata.
- Persist credential-bearing URLs through platform secret storage.
- Store only a redacted location and secret reference in playlist records.
- Do not include raw stream URLs in user-visible diagnostics by default.
- Preserve the existing public API identifier and transport behavior; its value is not reproduced here.
- webOS credential-bearing playlist persistence remains blocked until secure storage is verified.

### 10.4 File access

- No unrestricted filesystem scanning.
- No implicit access to Downloads or external storage.
- Android access uses user-selected SAF documents/trees and persistable grants.
- macOS access uses security-scoped bookmarks.
- Windows access uses native user selection.
- Access is revoked or marked stale when files move, disappear or permission is lost.
- Discovery results are cached only inside the authorized scope.

### 10.5 Playback health and probing

- Source health comes from actual playback outcomes.
- No background probing or scanning of third-party servers.
- Temporary buffering is not proof that a source is dead.
- “Available” means recently confirmed by successful playback, not currently online.
- Retry and cooldown state is bounded and cancelled when the user leaves the channel.

### 10.6 XMLTV safety

When the EPG workstream is implemented:

- Use a safe XML parser with external entity/network resolution disabled.
- Apply document-size and programme-count limits.
- Treat malformed XML as a no-data/error state.
- Never invent programmes to fill gaps.
- Never infer a schedule from the selected stream URL.

## 11. EPG no-data seam and Iran-feed constraint

### 11.1 Current evidence

The inspected baseline contains no XMLTV repository, programme store or channel-to-XMLTV mapping implementation. `LiveTVCountryMeta.timeZone` exists, but `LiveTVCountry` discards it:

- `Sources/Core/LiveTVModels.swift:148-192`

The earlier approved EPG blueprint remains the implementation owner for provider configuration, XMLTV parsing, timezone handling and UI.

### 11.2 Feed constraint

**No licensed Iran-covering EPG feed has been verified.** This is a project constraint carried forward from the approved EPG direction, not a claim that a provider was tested during this audit.

Therefore:

- No provider is selected by this audit.
- No programme data is invented or bundled.
- No public API identifier or feed URL is reproduced.
- Multi-Source work must not depend on EPG availability.
- EPG availability must not be inferred from channel or stream availability.

### 11.3 Explicit no-data states

The future EPG seam must distinguish at least:

- `providerUnavailable`: no legitimate provider configured or accessible.
- `noMapping`: feed exists but the logical channel has no verified XMLTV mapping.
- `noProgrammes`: mapped channel has no programmes for the requested interval.
- `parseError`: feed is malformed or unsupported.
- `staleData`: cached data exists but is outside its validity window.

Rules:

- Render an honest empty/no-data state.
- Never substitute fabricated titles, times or descriptions.
- Never use country timezone as a channel-level default without explicit evidence.
- Preserve mappings independently of selected stream URL.
- Keep EPG no-data behavior independent of source failover.

## 12. Ordered Phases B–G with independently testable slices

### Phase B — Multi-Source Foundation

#### B1 — Contracts and migrations

- Add versioned playlist/channel/source contracts.
- Add legacy readers and migration fixtures.
- Add deterministic identity rules.
- Add redacted location/secret-reference contracts.

**Testable slice:** serialization, fresh-install schema, legacy fixture migration and stable ID round-trips.

#### B2 — Parser and source registry

- Add a provenance-rich M3U parse result.
- Distinguish channel-list M3U from HLS master manifests.
- Preserve original metadata and structured parse issues.
- Add source registry and refresh reconciliation.

**Testable slice:** deterministic parser/registry tests with no UI, network or playback.

#### B3 — Catalog and identity resolution

- Add namespaced provider identity.
- Add candidate matching without name-only auto-merge.
- Add manual merge/split records.
- Represent built-in catalog inputs as read-only records.

**Testable slice:** duplicate/missing ID, namespace collision, manual association and built-in preservation tests.

#### B4 — Playlist management and catalog integration

- Add remote URL and authorized local-file import.
- Add rename, enable/disable, refresh, remove and status/error handling.
- Feed the unified catalog into existing Live TV screens and search.
- Preserve fixed Iran catalog behavior.

**Exit gate:** multiple playlists coexist; refresh preserves identity/settings; malformed entries are reported; no playback behavior has changed.

### Phase C — Intelligent Source Resolution

#### C1 — Pure resolver and failover policy

- Extract source ordering and failover decisions into pure components.
- Add stable priority, enabled state, last successful source and cooldown.
- Classify playback failures before rotation.

**Testable slice:** deterministic policy tests for buffering, transport failure, retry caps, cooldown and cancellation.

#### C2 — Swift and Flutter integration

- Adapt existing controllers to the policy.
- Preserve same-source retries, software-decoder fallback and remux behavior.
- Add stable playback context and stale-callback protection.

**Testable slice:** hosted controller integration with deterministic local fixtures.

#### C3 — webOS integration and source UI

- Add bounded automatic failover to the existing player.
- Ensure manual selection cancels automatic attempts.
- Expose redacted source state to the existing diagnostics blueprint.

**Exit gate:** genuine failures rotate; temporary buffering does not; retries are bounded; all-sources-failed and cancellation paths are tested.

### Phase D — Subtitle Foundation

#### D1 — Subtitle contracts and preferences

- Add track, cue and preference contracts.
- Add renderer capability descriptors.
- Add per-media manual override semantics.

**Testable slice:** model/preference migration and selection-priority tests.

#### D2 — Platform renderer adapters

- Implement macOS direct embedded selection.
- Implement validated macOS external SRT/WebVTT overlay.
- Implement Flutter embedded and external media_kit track handling.
- Probe webOS WebVTT visibility before enabling it.

**Testable slice:** hosted renderer fixtures; unsupported formats remain explicitly unavailable.

#### D3 — File access

- Add native single-file picker adapters.
- Add macOS bookmarks and Android SAF grants.
- Keep webOS local import blocked until verified.

**Exit gate:** supported embedded/external tracks can be selected and disabled during playback on each verified platform.

### Phase E — Automatic Discovery

#### E1 — Matching and ambiguity

- Implement basename/language/episode matching.
- Add ambiguity confirmation and manual correction.

**Testable slice:** deterministic filename fixtures, including unrelated-file rejection.

#### E2 — Authorized-root discovery and caching

- Restrict discovery to authorized roots.
- Add cache invalidation and file revalidation.
- Expose discovery only where directory access is verified.

**Exit gate:** correct files are discovered; unrelated files are rejected; no unrestricted scan occurs.

### Phase F — Subtitle Customization

#### F1 — Renderer-backed appearance and timing

- Enable only supported appearance controls.
- Implement positive/negative delay and reset.
- Apply changes without unnecessary playback restart.

**Testable slice:** capability-driven settings and timing tests.

#### F2 — RTL validation and persistence

- Validate Persian, Arabic, Kurdish and mixed RTL/LTR rendering.
- Persist global defaults and per-media overrides.
- Verify manual selection is not unexpectedly overridden.

**Exit gate:** preferences survive restart; visual fixtures pass on each claimed platform.

### Phase G — Integration and Verification

#### G1 — Regression and hosted CI

- Run pure, integration and platform tests.
- Verify Continue Watching, auto-next, Live TV search, favorites separation and existing playback.
- Build supported platforms through existing GitHub workflows.

#### G2 — Packaging, legal and documentation

- Run packaging, installer/startup, legal and security gates.
- Update notices and dependency provenance.
- Publish the implementation report with exact platform limitations.

**Exit gate:** all acceptance criteria applicable to claimed support are evidenced; no unsupported platform is marked Supported.

## 13. First independently testable implementation slice

**Recommended slice:** B1–B3 — pure Multi-Source contracts, parser result, identity resolver, source registry and migration fixtures.

It must not:

- Change playback startup.
- Perform network requests.
- Add UI.
- Add a dependency.
- Modify legacy favorites/history.
- Change the built-in Iran catalog.

Required deterministic fixtures:

- UTF-8 and BOM M3U.
- CRLF input.
- Duplicate `tvg-id`.
- Missing `tvg-id`.
- Multiple quality/backup URLs.
- Malformed `#EXTINF`.
- Empty playlist.
- Two playlists containing the same provider channel.
- Same normalized name but different provider IDs.
- HLS master manifest that must not be treated as a channel list.
- Credential-bearing URL requiring redaction.
- Legacy macOS JSON arrays.
- Legacy Flutter JSON-string lists.
- Legacy webOS localStorage values.

Required assertions:

- IDs remain stable across serialization, refresh and URL replacement.
- Playlist ownership is preserved.
- Similar names do not auto-merge.
- Manual merge/split round-trips.
- Source priority and enabled state survive refresh.
- Existing data remains readable and unchanged.
- Logs/diagnostics contain no credentials.
- Fresh-install and upgrade schemas both work.

## 14. Acceptance tests and CI plan

### 14.1 Pure tests

| Area | Required tests |
|---|---|
| Parser | M3U/BOM/CRLF/malformed/empty/large input; HLS-master rejection as channel catalog |
| Identity | Duplicate/missing IDs, namespace collisions, deterministic migration keys |
| Association | Multi-playlist sources, manual merge/split, no name-only auto-merge |
| Registry | Stable IDs, priority, enabled state, refresh reconciliation |
| Migration | Previous-release fixtures, fresh install, rollback safety |
| Security | URL redaction, scheme validation, size limits, no path traversal |
| Subtitles | SRT/VTT parsing, BOM, malformed cues, timing bounds, Unicode preservation |
| Discovery | Exact/language/episode matching, ambiguity, unrelated-file rejection |
| Failover | Genuine failure vs buffering, retry cap, cooldown, cancellation, all sources failed |
| EPG seam | Provider unavailable, no mapping, no programmes, malformed XML, stale data; no fabricated output |

### 14.2 Hosted runtime tests

- **Flutter pure tests:** extend the existing `flutter test` path at `.github/workflows/ci.yml:67-124`.
- **Swift pure tests:** add a small `Tests/core` harness compiled with `swiftc`, following the source-compilation pattern in `scripts/typecheck.sh:1-13`; execute only on a hosted macOS runner.
- **macOS playback:** extend `Tests/player` with embedded/external subtitle fixtures and visible `AVPlayerLayer` checks. Current harness evidence: `Tests/player/main.swift:1-8`, `Tests/player/run.sh:96-185`.
- **Flutter Android/TV/Windows:** run media_kit subtitle integration fixtures on hosted emulators/runners. Android TV remote-only acceptance remains a separate gate.
- **webOS pure tests:** add Node/VM tests alongside `.github/workflows/ci.yml:147-208`.
- **webOS device:** WebVTT cue visibility, mixed RTL, remote selection and model/version behavior require simulator/device evidence. Until then, retain **Not Yet Verified**.

No random public IPTV stream may be the sole CI fixture.

### 14.3 Product acceptance criteria

#### Multi-Source

- Multiple independent playlists coexist.
- A logical channel has multiple playback sources.
- Sources can be selected manually and reordered.
- Automatic selection and failover work after verified playback failures.
- Temporary buffering does not trigger failover.
- Retry loops and rapid source-switching loops are prevented.
- Existing single-source behavior continues without reimport.
- Existing favorites, history and Continue Watching remain intact.
- EPG mappings remain independent of stream URL.
- No unauthorized probing occurs.

#### Subtitles

- Embedded subtitles can be selected where verified.
- External subtitles can be loaded where verified.
- Manual file selection works on supported platforms.
- Automatic discovery works only where authorized file access exists.
- SRT, VTT, ASS and SSA are claimed only to the extent verified by the renderer.
- Styling works only where technically supported.
- Positive and negative synchronization works where supported.
- Preferences persist without overriding manual selection unexpectedly.
- Persian, Arabic, Kurdish and mixed RTL/LTR rendering pass visual fixtures.

#### Product and quality

- No existing feature is removed.
- No mandatory account or paid service is introduced.
- No platform is falsely marked supported.
- No licensing or security gate is bypassed.
- Tests and builds pass on hosted runners.
- Data migrations are verified.
- No known critical regression remains.
- Platform limitations are documented.

### 14.4 Regression tests

The following must remain explicitly covered:

- Existing Live TV search.
- Existing source menus.
- Continue Watching and resume position.
- Auto-next episode behavior.
- Media favorites.
- Future Live TV favorites remaining separate.
- Built-in Iran catalog composition.
- Link-health persistence.
- Existing macOS remux and reconnect behavior.
- Existing Flutter software-decoder fallback.
- Existing webOS manual channel switching.
- EPG no-data behavior when no legitimate feed exists.

## 15. Reconciliation with adjacent approved work

### 15.1 Live TV search

Search is already implemented in:

- `Sources/UI/Live/LiveTVView.swift:6-93`
- `flutter_app/lib/screens/live_screen.dart:250-300`
- `webos_app/app/js/screens/live.js`

The unified catalog must feed these existing search paths. No duplicate search feature should be created.

### 15.2 Live TV favorites

The earlier blueprint is not implemented in the inspected baseline. That work remains the owner of the separate Live TV favorite store and UI.

Multi-Source must:

- Provide stable `channelId` values.
- Preserve media favorites unchanged.
- Avoid creating a competing Live TV favorite store.
- Avoid mixing Live TV favorites with movie/series favorites.

### 15.3 Diagnostics

The earlier diagnostics blueprint remains the UI owner.

Multi-Source supplies:

- Redacted source provenance.
- Actual playback outcomes.
- Retry/cooldown state.
- Source-specific errors.

Multi-Source must not:

- Add background probing.
- Create a duplicate request-count subsystem.
- Claim a source is online without playback evidence.

### 15.4 EPG

The earlier provider/XMLTV/timezone/no-data seam remains separate planned work.

Multi-Source only:

- Reserves stable channel mapping contracts.
- Preserves no-data behavior.
- Keeps EPG independent of stream URL and failover.

### 15.5 Fixed Iran catalog and API behavior

- Preserve the current Famelack/iptv-org merge behavior.
- Preserve the established Iran channel-list source.
- Preserve existing API transport/cache behavior.
- Preserve the public API identifier behavior without reproducing its value.

## 16. Risks and blockers

| Risk/blocker | Severity | Confidence | Mitigation |
|---|---|---|---|
| Random Swift fallback IDs break persisted associations | High | High | Stable `channelId` plus deterministic legacy mapping |
| M3U8 channel-list/HLS-master confusion | High | High | Content detection and separate parser outcomes |
| Name-only automatic channel merging | High | High | Candidate-only matching; explicit user confirmation |
| Credential leakage through URLs/logs | High | High | Secret references, redaction, diagnostics review |
| Unauthorized filesystem scanning | High | High | Picker-only access and authorized roots |
| Swift remux silently drops subtitles | High | High | Separate direct/remux capability states; hosted probe |
| Engine API mistaken for product support | High | High | Separate app/engine matrices and runtime gates |
| Android TV picker unusable with remote | High | Unknown | Hosted TV/device D-pad acceptance test |
| webOS local-file route unavailable | High | Unknown | Do not claim local import; document limitation |
| webOS WebVTT cues invisible on some models | High | Medium | Device/model fixture matrix |
| ASS/SSA falsely reduced to plain text | High | High | No support claim without style-capable renderer proof |
| RTL text manually corrupted | High | High | Platform bidi/shaping and mixed-text fixtures |
| Stale playback/subtitle callbacks after channel switch | High | Medium | Request generation tokens and disposal tests |
| Large playlists blocking UI | Medium | High | Async parsing, limits, cancellation and large fixtures |
| New dependency license/native obligations | High | High | Pin/hash/review before adoption |
| Existing native redistribution blockers | High | High | Preserve legal gates; no production approval by signature alone |
| Concurrent legal work overwritten | High | High | Exact-path coordination and diff review |
| No licensed Iran-covering EPG feed verified | High | High | Preserve explicit no-data seam; never invent programmes |

## 17. Conclusions, completed work, uncovered scope and blockers

### 17.1 Conclusions

1. **Multiple channel sources already exist** and are reusable on all platform families, but they lack independent playlist provenance and complete policy.
2. **Multiple independent playlists are absent** and require a new versioned registry, not a modification of the fixed Iran catalog loader.
3. **No application-level subtitle system exists** on any platform.
4. **Subtitle engine capability is not uniform.** AVFoundation and media_kit expose useful APIs; webOS officially supports only limited external WebVTT behavior.
5. **Runtime verification is mandatory** before changing any compatibility value to Supported.
6. **Existing playback controllers should remain**; new resolver, failure-policy and subtitle adapters should integrate at their current boundaries.
7. **Data migration must be additive.** Existing media favorites, history, Continue Watching, settings and single-source playback remain intact.
8. **The earlier Live TV favorites/diagnostics/EPG blueprints remain separate workstreams.** This implementation consumes their contracts and does not duplicate them.
9. **Phase B’s pure foundation is the correct first slice** because it establishes identity and migration safety before UI or playback behavior changes.
10. **Native-media licensing and webOS/device verification remain release blockers** independent of code completion.

### 17.2 Completed in Phase A

- Source-backed current-state audit.
- App-versus-engine compatibility matrices.
- Stable identity and target contract design.
- Platform-specific change boundaries.
- Subtitle renderer, file-access, discovery, preference and RTL strategy.
- Migration and backward-compatibility plan.
- Dependency/license impact assessment.
- Security/privacy limits.
- EPG no-data seam and Iran-feed constraint.
- Ordered Phases B–G with independently testable slices.
- Acceptance and hosted-CI plan.
- Reconciliation with search, favorites, diagnostics and EPG work.

### 17.3 Uncovered scope

- No runtime playback or subtitle rendering was executed.
- No Android TV or webOS device acceptance was performed.
- No release-specific native binary inventory was produced.
- No new dependency was selected, installed or transitively audited.
- No UI visual design or performance benchmark was performed.
- No provider or streaming endpoint was contacted.
- No EPG feed was selected and no programme data was created.

### 17.4 Blocking conditions for later phases

- macOS external sidecar API behavior requires a hosted probe.
- macOS remux subtitle preservation requires a hosted FFmpeg/HLS probe.
- Flutter Android/Windows ASS/SSA and RTL rendering require hosted fixtures.
- Android TV SAF remote usability requires device/emulator evidence.
- webOS WebVTT visibility and local-file access require device evidence.
- Credential-bearing webOS playlist persistence requires verified secure storage.
- New picker/secure-storage dependencies require exact version, hash and license review.
- Existing native-media redistribution obligations remain unresolved.
- No licensed Iran-covering EPG feed is verified; EPG must remain in an explicit no-data state until one is legitimately supplied.

**Phase A deliverable status:** complete.  
**Implementation status:** not started.

## Sources

- [Apple — Selecting subtitles and alternative audio tracks](https://developer.apple.com/documentation/avfoundation/selecting-subtitles-and-alternative-audio-tracks.md)
- [Apple Technical Q&A QA1794 — Customizing subtitles with AVPlayer](https://developer.apple.com/library/archive/qa/qa1794/_index.html)
- [media_kit 1.2.6 — Player](https://pub.dev/documentation/media_kit/1.2.6/media_kit/Player-class.html)
- [media_kit 1.2.6 — PlayerStream](https://pub.dev/documentation/media_kit/1.2.6/media_kit/PlayerStream-class.html)
- [media_kit 1.2.6 — SubtitleTrack](https://pub.dev/documentation/media_kit/1.2.6/media_kit/SubtitleTrack-class.html)
- [mpv manual — Subtitle options and external subtitle files](https://mpv.io/manual/stable/)
- [Android Developers — Storage Access Framework](https://developer.android.com/training/data-storage/shared/documents-files)
- [Flutter file_picker package](https://pub.dev/packages/file_picker)
- [Chrome Developers — File System Access API](https://developer.chrome.com/docs/capabilities/web-apis/file-system-access)
- [LG webOS — Streaming Protocol and DRM specification](https://webostv.developer.lge.com/develop/specifications/streaming-protocol-drm)
- [LG webOS Developer Forum — Subtitles and Native Player](https://forum.webostv.developer.lge.com/t/subtitles-and-native-player/27908)
- [LG webOS Developer Forum — VTTCue visibility report](https://forum.webostv.developer.lge.com/t/vttcue-not-shown-in-lg-2019/2486)
