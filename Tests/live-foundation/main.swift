import Foundation

// Hosted regression harness for the Swift half of the schema-v1 live catalog
// contract (multi-source foundation, task B1-S).
//
// `Tests/live-foundation/run.sh` compiles this file together with the *production*
// `Sources/Core/LiveTVContracts.swift` and `Sources/Core/LiveTVCatalogCodec.swift`,
// so the binary under test is the code the app ships, not a copy of it. Deliberately
// no XCTest: the CI step judges this run by exactly two things — the process exit
// status and the final `assertions: <n>` line, which `run.sh` greps and floors, so a
// harness that silently executed zero checks cannot pass.
//
// Everything here is deterministic and offline: fixed documents, fixed timestamps,
// no network, no device, no `UserDefaults`, and no file writes.

var assertionsRun = 0

func fail(_ message: String, line: Int = #line) -> Never {
    FileHandle.standardError.write(
        Data("FAIL (Tests/live-foundation/main.swift:\(line)): \(message)\n".utf8)
    )
    exit(1)
}

func check(_ condition: Bool, _ label: String, line: Int = #line) {
    assertionsRun += 1
    if !condition { fail(label, line: line) }
}

/// A call that must succeed; an unexpected throw becomes a named failure instead of
/// an unhandled error that hides which contract broke.
func must<T>(_ label: String, line: Int = #line, _ body: () throws -> T) -> T {
    do {
        return try body()
    } catch {
        fail("\(label) threw unexpectedly: \(error)", line: line)
    }
}

func expectThrows(_ label: String, line: Int = #line, _ body: () throws -> Any?) {
    assertionsRun += 1
    do {
        _ = try body()
    } catch {
        return
    }
    fail("\(label) did not throw", line: line)
}

func expectSchemaError(_ label: String, line: Int = #line, _ body: () throws -> Any?) {
    assertionsRun += 1
    do {
        _ = try body()
    } catch let error as LiveCatalogSchemaError where error == .unsupportedVersion {
        return
    } catch {
        fail("\(label) threw \(error) instead of LiveCatalogSchemaError.unsupportedVersion", line: line)
    }
    fail("\(label) did not throw", line: line)
}

/// For the rejections this codec raises itself, whose message is part of the value:
/// a malformed document that somehow reached typed decoding still throws, but as a
/// different case, which means the preflight silently stopped existing.
func expectDataCorrupted(_ label: String, line: Int = #line, _ body: () throws -> Any?) {
    assertionsRun += 1
    do {
        _ = try body()
    } catch let error as DecodingError {
        switch error {
        case .dataCorrupted:
            return
        default:
            fail("\(label) threw \(error) instead of DecodingError.dataCorrupted", line: line)
        }
    } catch {
        fail("\(label) threw \(error) instead of DecodingError.dataCorrupted", line: line)
    }
    fail("\(label) did not throw", line: line)
}

/// Substring surgery on a document fixture.
///
/// A negative test whose mutation silently fails to match is a tautology: the
/// unmutated document decodes fine, nothing throws, and the case passes for the
/// wrong reason. Every mutation therefore asserts it found its target first.
func mutated(
    _ label: String,
    from source: String,
    _ target: String,
    to replacement: String,
    line: Int = #line
) -> Data {
    let result = source.replacingOccurrences(of: target, with: replacement)
    assertionsRun += 1
    if result == source { fail("mutation '\(label)' found no occurrence of \(target)", line: line) }
    return Data(result.utf8)
}

// MARK: - Fixture location

// `run.sh` passes the repository root as argv[1]; `#filePath` keeps the harness
// runnable by a human reading the checkout, including when it is built into a
// temporary directory. A missing fixture is a hard failure, never a skip: a silently
// skipped group is exactly how a contract test stops protecting anything.
let repoRoot: String = {
    let argument = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
    if !argument.isEmpty { return argument }
    return URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .path
}()

let fixtureDirectory = "\(repoRoot)/Tests/fixtures/migration"

func fixtureText(_ name: String) -> String {
    let path = "\(fixtureDirectory)/\(name)"
    guard let data = FileManager.default.contents(atPath: path) else {
        fail("missing fixture \(path)")
    }
    guard let text = String(data: data, encoding: .utf8) else {
        fail("fixture \(path) is not UTF-8")
    }
    return text
}

func decoded(_ json: String, _ label: String, line: Int = #line) -> LiveCatalogState {
    must(label, line: line) { try LiveCatalogStateCodec.decode(Data(json.utf8)) }
}

func encodedText(_ state: LiveCatalogState, _ label: String, line: Int = #line) -> String {
    let data = must(label, line: line) { try LiveCatalogStateCodec.encode(state) }
    return String(decoding: data, as: UTF8.self)
}

// MARK: - Documents

/// A v1 document written before the three additive keys existed: no
/// `recentWatches`, no `sourcePolicy` on the first preference, and no
/// `rendererCapability` on the secret-backed source. Optional timestamps appear in
/// both the seconds-precision and the canonical fractional form, and one source
/// carries only a secret reference.
let additiveV1JSON = #"""
{
  "schemaVersion": 1,
  "playlists": [
    {
      "playlistId": "builtin:live",
      "name": "CCloud",
      "sourceType": "builtIn",
      "locationRef": "builtin:live",
      "enabled": true,
      "createdAt": "2026-01-01T00:00:00Z",
      "lastUpdatedAt": "2026-01-02T03:04:05.123Z",
      "lastSuccessfulRefresh": null,
      "refreshStatus": "ready",
      "lastErrorCode": null,
      "channelCount": 62,
      "parsingVersion": 1
    },
    {
      "playlistId": "pl-remote",
      "name": "Remote List",
      "sourceType": "remoteUrl",
      "locationRef": "https://example.test/list.m3u",
      "enabled": false,
      "createdAt": "2026-02-01T00:00:00.500Z",
      "lastUpdatedAt": null,
      "lastSuccessfulRefresh": "2026-02-02T00:00:00.000Z",
      "refreshStatus": "error",
      "lastErrorCode": "refresh_timeout",
      "channelCount": 0,
      "parsingVersion": 2
    }
  ],
  "members": [
    {
      "memberId": "m-1",
      "playlistId": "builtin:live",
      "providerNamespace": "famelack",
      "providerChannelId": "IRIB1",
      "displayName": "IRIB 1",
      "normalizedName": "irib 1",
      "logoUrl": "https://img.example/irib1.png",
      "group": "General",
      "countryCode": "IR",
      "languages": ["fa"],
      "tvgId": "irib1.example",
      "ordinal": 0
    },
    {
      "memberId": "m-2",
      "playlistId": "pl-remote",
      "providerNamespace": "iptv-org",
      "providerChannelId": "IRIB1.IR",
      "displayName": "IRIB 1 HD",
      "normalizedName": "irib 1 hd",
      "logoUrl": null,
      "group": null,
      "countryCode": null,
      "languages": [],
      "tvgId": null,
      "ordinal": 1
    }
  ],
  "sources": [
    {
      "sourceId": "s-1",
      "channelId": "ch-1",
      "memberId": "m-1",
      "playlistId": "builtin:live",
      "providerNamespace": "famelack",
      "label": "Famelack",
      "streamUrl": "https://stream.example/irib1.m3u8",
      "streamSecretRef": null,
      "protocolHint": "hls",
      "rendererCapability": "Supported",
      "origin": "playlist",
      "priority": 0,
      "enabled": true,
      "health": "available",
      "lastSuccessfulPlaybackAt": "2026-03-01T12:00:00.000Z",
      "lastFailedPlaybackAt": null,
      "lastErrorCode": null
    },
    {
      "sourceId": "s-2",
      "channelId": "ch-1",
      "memberId": "m-2",
      "playlistId": "pl-remote",
      "providerNamespace": "iptv-org",
      "label": "Backup (signed)",
      "streamSecretRef": "secret:ccloud-live-s-2",
      "protocolHint": "hls",
      "origin": "user",
      "priority": 1,
      "enabled": true,
      "health": "unverified"
    }
  ],
  "associations": [
    { "memberIds": ["m-1", "m-2"] }
  ],
  "preferences": [
    {
      "channelId": "ch-1",
      "favorite": true,
      "hidden": false,
      "category": null,
      "userOrder": 3,
      "automaticFailoverEnabled": true,
      "lastSuccessfulSourceId": "s-1"
    },
    {
      "channelId": "ch-2",
      "favorite": false,
      "hidden": true,
      "category": "News",
      "userOrder": null,
      "automaticFailoverEnabled": false,
      "sourcePolicy": {
        "maxAutomaticAttempts": 5,
        "sameSourceRetries": 1,
        "connectTimeoutMs": 9000,
        "backoffMs": [250, 750],
        "failedCooldownSeconds": 30,
        "bufferingThresholdMs": 1500
      },
      "lastSuccessfulSourceId": null
    }
  ],
  "logicalIdByMemberId": {
    "m-1": "ch-1",
    "m-2": "ch-1"
  }
}
"""#

let secretBackedSourceJSON = #"""
{"schemaVersion":1,"playlists":[],"members":[],"sources":[{"sourceId":"s-secret","channelId":"ch-1","memberId":"m-1","playlistId":"pl-1","providerNamespace":"manual","label":"Signed","streamSecretRef":"secret:ccloud-live-s-secret","protocolHint":"hls","rendererCapability":"Not Yet Verified","origin":"user","priority":0,"enabled":true,"health":"unverified"}],"associations":[],"preferences":[],"recentWatches":[],"logicalIdByMemberId":{}}
"""#

/// No address and no secret reference: nobody could ever play this source, so it has
/// to be rejected rather than defaulted to an empty string.
let addresslessSourceJSON = #"""
{"schemaVersion":1,"playlists":[],"members":[],"sources":[{"sourceId":"s-broken","channelId":"ch-1","memberId":"m-1","playlistId":"pl-1","providerNamespace":"manual","label":"Nothing","protocolHint":"hls","origin":"user","priority":0,"enabled":true,"health":"unverified"}],"associations":[],"preferences":[],"recentWatches":[],"logicalIdByMemberId":{}}
"""#

/// Present-but-mistyped additive keys must survive normalization and fail in typed
/// decoding; replacing them with defaults would invent user intent.
let mistypedPolicyJSON = #"""
{"schemaVersion":1,"playlists":[],"members":[],"sources":[],"associations":[],"preferences":[{"channelId":"ch-1","favorite":true,"hidden":false,"category":null,"userOrder":null,"automaticFailoverEnabled":true,"sourcePolicy":5,"lastSuccessfulSourceId":null}],"recentWatches":[],"logicalIdByMemberId":{}}
"""#

let mistypedCollectionsJSON = #"""
{"schemaVersion":1,"playlists":7,"members":[],"sources":[],"associations":[],"preferences":[],"recentWatches":[],"logicalIdByMemberId":{}}
"""#

/// The shortest document the contract accepts: every field the Dart reader defaults is
/// left out, and the one `sourcePolicy` that is present carries only the two keys an
/// early build wrote. Task B1-J feeds the webOS port the identical text, so this is the
/// document on which the two readers' tolerance must agree — a port that required any of
/// these keys would reject a catalog an older Android or macOS build legitimately saved.
let minimalV1JSON = #"""
{"schemaVersion":1,"playlists":[{"playlistId":"pl-1","name":"Minimal","sourceType":"remoteUrl","locationRef":"https://example.test/list.m3u","enabled":true,"createdAt":"2026-01-01T00:00:00Z"}],"members":[{"memberId":"m-1","playlistId":"pl-1","providerNamespace":"iptv-org","providerChannelId":"IR.IRIB1","displayName":"IRIB 1","normalizedName":"irib 1","ordinal":0}],"sources":[{"sourceId":"s-1","channelId":"ch-1","memberId":"m-1","playlistId":"pl-1","providerNamespace":"iptv-org","label":"Primary","streamUrl":"https://stream.example/irib1.m3u8","protocolHint":"hls","origin":"playlist","priority":0,"enabled":true,"health":"unverified"}],"associations":[],"preferences":[{"channelId":"ch-1","sourcePolicy":{"backoffMs":[100],"connectTimeoutMs":8000}}],"logicalIdByMemberId":{"m-1":"ch-1"}}
"""#

/// Byte-for-byte the legacy macOS documents the plan pins in
/// `Tests/fixtures/migration/macos-favorites.json` and `macos-history.json`. Pinning
/// the text here is what makes "migration never rewrites the legacy stores" a real
/// assertion: a fixture that a later change quietly edited would stop describing the
/// legacy shape at all, and the before/after comparison would still pass.
let legacyFavoritesJSON = #"""
[{"kind":"movie","movie":{"id":7,"type":"movie","title":"Legacy Movie","description":"","year":2020,"imdb":7.1,"rating":7.1,"duration":null,"image":"https://img.example/poster.jpg","cover":"https://img.example/cover.jpg","genres":[],"sources":[],"country":[]},"series":null,"addedAt":"2026-01-02T03:04:05Z"}]
"""#

let legacyHistoryJSON = #"""
[{"kind":"movie","movie":{"id":7,"type":"movie","title":"Legacy Movie","description":"","year":2020,"imdb":7.1,"rating":7.1,"duration":null,"image":"https://img.example/poster.jpg","cover":"https://img.example/cover.jpg","genres":[],"sources":[],"country":[]},"series":null,"lastWatchedAt":"2026-01-03T03:04:05Z","progress":0.5,"episodes":[],"position":120.0,"duration":240.0}]
"""#

// MARK: - 1. Supported version, empty state, and the standard policy

check(
    LiveCatalogStateCodec.supportedSchemaVersion == 1,
    "supportedSchemaVersion is 1, the version the frozen fixture and the Dart codec use"
)
check(
    LiveCatalogStateCodec.supportedSchemaVersion == LiveCatalogState.empty.schemaVersion,
    "the empty state is written in the version this codec can read back"
)
check(LiveCatalogState.empty.playlists.isEmpty, "empty state has no playlists")
check(LiveCatalogState.empty.members.isEmpty, "empty state has no members")
check(LiveCatalogState.empty.sources.isEmpty, "empty state has no sources")
check(LiveCatalogState.empty.associations.isEmpty, "empty state has no associations")
check(LiveCatalogState.empty.preferences.isEmpty, "empty state has no preferences")
check(LiveCatalogState.empty.recentWatches.isEmpty, "empty state has no recent watches")
check(LiveCatalogState.empty.logicalIdByMemberId.isEmpty, "empty state has no member mapping")

let standardPolicy = SourcePolicy.standard
check(standardPolicy.maxAutomaticAttempts == 3, "standard policy allows three automatic attempts")
check(standardPolicy.sameSourceRetries == 2, "standard policy retries one source twice")
check(standardPolicy.connectTimeoutMs == 15000, "standard policy connects within 15000 ms")
check(standardPolicy.backoffMs == [500, 1500, 4000], "standard policy backs off 500/1500/4000")
check(standardPolicy.failedCooldownSeconds == 600, "standard policy cools a failed source for 600 s")
check(standardPolicy.bufferingThresholdMs == 30000, "standard policy buffers up to 30000 ms")

check(
    must("migrate(nil)") { try LiveCatalogMigration.migrate(nil) } == .empty,
    "absent stored data migrates to the canonical empty state"
)
check(
    must("migrate(empty data)") { try LiveCatalogMigration.migrate(Data()) } == .empty,
    "empty stored data migrates to the canonical empty state, as the Dart port does"
)

// MARK: - 2. Timestamp text is canonical on write and lenient on read

check(
    LiveCatalogDate.date(from: "2026-01-01T00:00:00Z")
        == LiveCatalogDate.date(from: "2026-01-01T00:00:00.000Z"),
    "the seconds-precision and canonical forms name the same instant"
)
check(
    LiveCatalogDate.date(from: "2026-01-01T00:00:00.001Z")
        != LiveCatalogDate.date(from: "2026-01-01T00:00:00.002Z"),
    "millisecond resolution is not discarded while parsing"
)
check(LiveCatalogDate.date(from: "yesterday") == nil, "an unparseable timestamp is rejected, not defaulted")
check(LiveCatalogDate.date(from: "") == nil, "an empty timestamp is rejected")
check(
    LiveCatalogDate.text(for: Date(timeIntervalSince1970: 1_767_225_600)) == "2026-01-01T00:00:00.000Z",
    "the canonical text form is RFC 3339 UTC with three fractional digits and a Z"
)
check(
    LiveCatalogDate.text(for: Date(timeIntervalSince1970: 1_767_225_600.999)) == "2026-01-01T00:00:00.999Z",
    "999 ms renders as 999 rather than rounding up to the next second"
)
let offsetInstant = LiveCatalogDate.date(from: "2026-01-01T05:00:00+05:00")
check(offsetInstant != nil, "an explicit non-UTC offset parses")
check(
    offsetInstant.map(LiveCatalogDate.text(for:)) == "2026-01-01T00:00:00.000Z",
    "a non-UTC offset normalizes to canonical UTC on write, matching DateTime.parse().toUtc()"
)

// A day the month does not have is refused rather than rolled forward. The webOS port
// states this rule as an explicit calendar check (`requireTimestamp` in
// `playlist_contracts.js`), and this port may not depend on `ISO8601DateFormatter`'s
// undocumented range behaviour to reach the same verdict: a value that one reader stores as
// 3 March and another refuses is a persistence split, not a rounding detail. The leap-year
// pair below is what makes the check a calendar rule rather than a blanket "day <= 28".
check(
    LiveCatalogDate.date(from: "2026-02-31T00:00:00.000Z") == nil,
    "a 31 February instant is refused instead of rolling into March"
)
check(
    LiveCatalogDate.date(from: "2026-02-29T00:00:00.000Z") == nil,
    "29 February in a common year is refused"
)
check(
    LiveCatalogDate.date(from: "2028-02-29T00:00:00.000Z") != nil,
    "29 February in a leap year parses"
)
check(
    LiveCatalogDate.date(from: "2026-13-01T00:00:00.000Z") == nil,
    "month 13 is refused"
)
check(
    LiveCatalogDate.date(from: "2026-04-31T00:00:00.000Z") == nil,
    "a 31st day in a 30-day month is refused"
)
check(
    LiveCatalogDate.date(from: "2026-01-01T00:00:00.000Z") != nil,
    "an ordinary canonical instant still parses, so the calendar rule is not a blanket refusal"
)
expectDataCorrupted("a stored document carrying a 31 February date") {
    try LiveCatalogStateCodec.decode(mutated(
        "impossible day",
        from: additiveV1JSON,
        "\"createdAt\": \"2026-01-01T00:00:00Z\"",
        to: "\"createdAt\": \"2026-02-31T00:00:00Z\""
    ))
}

// MARK: - 3. The frozen v1 fixture decodes, including its seconds-precision dates

let v1FixtureText = fixtureText("catalog-v1.json")
let v1State = must("the frozen v1 fixture") { try LiveCatalogMigration.migrate(Data(v1FixtureText.utf8)) }
check(v1State.schemaVersion == 1, "v1 fixture declares schema 1")
check(v1State.playlists.count == 1, "v1 fixture has one playlist")
let v1Playlist = v1State.playlists[0]
check(v1Playlist.playlistId == "builtin:live", "v1 fixture playlist id is builtin:live")
check(v1Playlist.name == "CCloud", "v1 fixture playlist name is CCloud")
check(v1Playlist.sourceType == .builtIn, "v1 fixture playlist is builtIn")
check(v1Playlist.locationRef == "builtin:live", "v1 fixture locationRef is the builtin token")
check(v1Playlist.enabled, "v1 fixture playlist is enabled")
check(v1Playlist.refreshStatus == .ready, "v1 fixture refresh status is ready")
check(v1Playlist.lastErrorCode == nil, "v1 fixture has no error code")
check(v1Playlist.channelCount == 0, "v1 fixture channel count is zero")
check(v1Playlist.parsingVersion == 1, "v1 fixture parsing version is 1")
check(v1Playlist.lastUpdatedAt == v1Playlist.createdAt, "v1 fixture lastUpdatedAt equals createdAt")
check(v1Playlist.lastSuccessfulRefresh == v1Playlist.createdAt, "v1 fixture refresh time equals createdAt")
// The absolute instant, not just a self-consistent round trip: the runner clock zone
// is UTC, so only a pinned epoch catches a parser that ignored the trailing Z.
check(
    v1Playlist.createdAt == Date(timeIntervalSince1970: 1_767_225_600),
    "the seconds-precision form parsed to the right instant"
)
check(v1State.members.isEmpty, "v1 fixture has no members")
check(v1State.sources.isEmpty, "v1 fixture has no sources")
check(v1State.associations.isEmpty, "v1 fixture has no associations")
check(v1State.preferences.isEmpty, "v1 fixture has no preferences")
check(v1State.recentWatches.isEmpty, "v1 fixture has no recent watches")
check(v1State.logicalIdByMemberId.isEmpty, "v1 fixture has no member mapping")
check(
    decoded(v1FixtureText, "v1 fixture re-decode") == v1State,
    "decode and migrate agree on the frozen fixture, so B4 cannot get two behaviours"
)
check(
    encodedText(v1State, "v1 fixture re-encode").contains("\"createdAt\":\"2026-01-01T00:00:00.000Z\""),
    "the fixture's seconds-precision timestamp is rewritten in the canonical form"
)
check(
    decoded(encodedText(v1State, "v1 round trip"), "v1 round trip re-decode") == v1State,
    "the frozen fixture survives a write/read cycle unchanged"
)

// MARK: - 4. Additive v1 omissions normalize, and only those omissions

let additive = decoded(additiveV1JSON, "additive v1 document")
check(additive.recentWatches.isEmpty, "an absent recentWatches key decodes as an empty history")
check(additive.playlists.count == 2, "both playlists decoded")
check(additive.members.count == 2, "both members decoded")
check(additive.sources.count == 2, "both sources decoded")
check(additive.associations.count == 1, "the association decoded")
check(additive.preferences.count == 2, "both preferences decoded")
check(
    additive.logicalIdByMemberId == ["m-1": "ch-1", "m-2": "ch-1"],
    "the member mapping decoded"
)
check(additive.members[1].ordinal == 1, "member ordinal survived")
check(additive.members[0].languages == ["fa"], "member languages survived")
check(additive.members[0].normalizedName == "irib 1", "member normalized name survived")
check(additive.members[1].logoUrl == nil, "a null logoUrl decodes as absent")
check(additive.associations[0].memberIds == ["m-1", "m-2"], "association member order survived")
check(!additive.playlists[1].enabled, "a disabled playlist stays disabled")
check(additive.playlists[1].refreshStatus == .error, "playlist error status decoded")
check(additive.playlists[1].lastErrorCode == "refresh_timeout", "playlist error code decoded")

let firstPreference = additive.preferences[0]
check(
    firstPreference.sourcePolicy == SourcePolicy.standard,
    "a preference without sourcePolicy receives the standard policy"
)
check(firstPreference.sourcePolicy.maxAutomaticAttempts == 3, "the defaulted policy attempts three times")
check(firstPreference.sourcePolicy.backoffMs == [500, 1500, 4000], "the defaulted policy backs off 500/1500/4000")
check(firstPreference.favorite, "preference favorite survived")
check(!firstPreference.hidden, "preference hidden survived")
check(firstPreference.userOrder == 3, "preference userOrder survived")
check(firstPreference.automaticFailoverEnabled, "preference failover flag survived")
check(firstPreference.lastSuccessfulSourceId == "s-1", "preference last successful source survived")
let secondPreference = additive.preferences[1]
check(secondPreference.sourcePolicy.maxAutomaticAttempts == 5, "an explicit sourcePolicy is not replaced")
check(secondPreference.sourcePolicy.sameSourceRetries == 1, "explicit sameSourceRetries preserved")
check(secondPreference.sourcePolicy.connectTimeoutMs == 9000, "explicit connectTimeoutMs preserved")
check(secondPreference.sourcePolicy.backoffMs == [250, 750], "explicit backoffMs preserved")
check(secondPreference.sourcePolicy.failedCooldownSeconds == 30, "explicit failedCooldownSeconds preserved")
check(secondPreference.sourcePolicy.bufferingThresholdMs == 1500, "explicit bufferingThresholdMs preserved")
check(secondPreference.category == "News", "explicit preference category preserved")
check(secondPreference.userOrder == nil, "a null userOrder decodes as absent")
check(!secondPreference.automaticFailoverEnabled, "a preference can turn automatic failover off")

let firstSource = additive.sources[0]
check(firstSource.rendererCapability == .supported, "an explicit rendererCapability is preserved")
check(firstSource.streamUrl == "https://stream.example/irib1.m3u8", "a plain source keeps its address")
check(firstSource.streamSecretRef == nil, "a plain source has no secret reference")
check(firstSource.origin == .playlist, "playlist-origin source decoded")
check(firstSource.health == .available, "available health decoded")
check(firstSource.lastErrorCode == nil, "a null error code decodes as absent")
check(
    firstSource.lastSuccessfulPlaybackAt.map(LiveCatalogDate.text(for:)) == "2026-03-01T12:00:00.000Z",
    "source playback timestamp kept its wall-clock instant"
)
check(
    firstSource.lastSuccessfulPlaybackAt == Date(timeIntervalSince1970: 1_772_366_400),
    "source playback timestamp parsed to the pinned epoch instant"
)
check(firstSource.lastFailedPlaybackAt == nil, "a null failure timestamp decodes as absent")
check(
    additive.playlists[0].lastUpdatedAt.map(LiveCatalogDate.text(for:)) == "2026-01-02T03:04:05.123Z",
    "millisecond precision survived parse and canonical re-render"
)
check(
    LiveCatalogDate.text(for: additive.playlists[1].createdAt) == "2026-02-01T00:00:00.500Z",
    "a half-second canonical timestamp survived parse and canonical re-render"
)

let secondSource = additive.sources[1]
check(
    secondSource.rendererCapability == .notYetVerified,
    "a source without rendererCapability decodes as Not Yet Verified"
)
check(
    secondSource.streamUrl.isEmpty,
    "a secret-backed source has no address in the document to read into memory"
)
check(secondSource.streamSecretRef == "secret:ccloud-live-s-2", "the secret reference survived")
check(secondSource.origin == .user, "user-origin source decoded")
check(secondSource.health == .unverified, "unverified health decoded")
check(secondSource.priority == 1, "source priority decoded")

// The capability vocabulary is closed. An unknown label or a non-string value must
// throw rather than default to Not Yet Verified: silently downgrading a capability is
// how an unverified renderer later gets described as supported.
expectThrows("an unknown rendererCapability label") {
    try LiveCatalogStateCodec.decode(mutated(
        "unknown rendererCapability",
        from: additiveV1JSON,
        "\"rendererCapability\": \"Supported\",",
        to: "\"rendererCapability\": \"Probably\","
    ))
}
expectThrows("a non-string rendererCapability") {
    try LiveCatalogStateCodec.decode(mutated(
        "non-string rendererCapability",
        from: additiveV1JSON,
        "\"rendererCapability\": \"Supported\",",
        to: "\"rendererCapability\": 3,"
    ))
}
expectThrows("an unknown playlist sourceType") {
    try LiveCatalogStateCodec.decode(mutated(
        "unknown sourceType",
        from: additiveV1JSON,
        "\"sourceType\": \"builtIn\"",
        to: "\"sourceType\": \"torrent\""
    ))
}
expectThrows("an unknown source health") {
    try LiveCatalogStateCodec.decode(mutated(
        "unknown source health",
        from: additiveV1JSON,
        "\"health\": \"available\"",
        to: "\"health\": \"weird\""
    ))
}
expectThrows("a non-object sourcePolicy") {
    try LiveCatalogStateCodec.decode(Data(mistypedPolicyJSON.utf8))
}
expectThrows("a non-list playlists collection") {
    try LiveCatalogStateCodec.decode(Data(mistypedCollectionsJSON.utf8))
}
expectThrows("a non-list recentWatches") {
    try LiveCatalogStateCodec.decode(mutated(
        "non-list recentWatches",
        from: additiveV1JSON,
        "\"logicalIdByMemberId\": {",
        to: "\"recentWatches\": 7,\n  \"logicalIdByMemberId\": {"
    ))
}
expectThrows("a non-timestamp playlist date") {
    try LiveCatalogStateCodec.decode(mutated(
        "non-timestamp createdAt",
        from: additiveV1JSON,
        "\"createdAt\": \"2026-01-01T00:00:00Z\",",
        to: "\"createdAt\": \"not a timestamp\","
    ))
}
expectThrows("a non-string required identifier") {
    try LiveCatalogStateCodec.decode(mutated(
        "non-string playlist name",
        from: additiveV1JSON,
        "\"name\": \"CCloud\",",
        to: "\"name\": 7,"
    ))
}

// MARK: - 4b. Dart's optional-with-default fields stay optional here too

// The document above omits every field `_optEnum`, `_optInt`, `_optBool` and
// `_optStringList` cover in the Dart codec. Required here, those omissions would throw,
// which means a catalog an older build saved would be unreadable after an update — the
// user would lose playlists, associations and preferences on next launch.
let minimal = decoded(minimalV1JSON, "minimal v1 document")
let minimalPlaylist = minimal.playlists[0]
check(minimalPlaylist.refreshStatus == .idle, "an absent refreshStatus decodes as idle")
check(minimalPlaylist.channelCount == 0, "an absent channelCount decodes as zero")
check(minimalPlaylist.parsingVersion == 1, "an absent parsingVersion decodes as version 1")
check(minimalPlaylist.lastUpdatedAt == nil, "an absent optional date stays absent, it is not invented")
check(minimal.members[0].languages.isEmpty, "an absent member languages list decodes as empty")
check(minimal.members[0].ordinal == 0, "the member ordinal decoded")
let minimalSource = minimal.sources[0]
check(minimalSource.rendererCapability == .notYetVerified, "a minimal source is not yet verified")
check(minimalSource.streamUrl == "https://stream.example/irib1.m3u8", "a minimal source keeps its address")
check(minimalSource.lastSuccessfulPlaybackAt == nil, "no playback history is invented for a minimal source")
let minimalPreference = minimal.preferences[0]
check(!minimalPreference.favorite, "an absent favorite decodes as not favourited")
check(!minimalPreference.hidden, "an absent hidden flag decodes as visible")
check(minimalPreference.automaticFailoverEnabled, "failover is on unless the user turned it off")
check(minimalPreference.category == nil, "an absent category stays absent")
check(minimalPreference.userOrder == nil, "an absent user order stays absent")
check(minimalPreference.lastSuccessfulSourceId == nil, "no last source is invented")
let minimalPolicy = minimalPreference.sourcePolicy
check(minimalPolicy.backoffMs == [100], "the backoff schedule an old document did write is kept")
check(minimalPolicy.connectTimeoutMs == 8000, "a timeout an old document did write is kept")
check(minimalPolicy.maxAutomaticAttempts == 3, "an absent policy integer takes the standard value")
check(minimalPolicy.sameSourceRetries == 2, "absent sameSourceRetries takes the standard value")
check(minimalPolicy.failedCooldownSeconds == 600, "absent failedCooldownSeconds takes the standard value")
check(minimalPolicy.bufferingThresholdMs == 30000, "absent bufferingThresholdMs takes the standard value")
// The defaults are only a read-side tolerance. A schedule is never invented, because
// deciding when to retry again is the user's or the standard policy's, not a decoder's.
expectThrows("a sourcePolicy with no backoffMs") {
    try LiveCatalogStateCodec.decode(mutated(
        "policy without backoffMs",
        from: minimalV1JSON,
        "\"backoffMs\":[100],",
        to: ""
    ))
}
let minimalText = encodedText(minimal, "minimal state")
check(
    minimalText.contains("\"refreshStatus\":\"idle\""),
    "a defaulted field is written on the next save, so the document is upgraded once and only once"
)
check(
    minimalText.contains("\"languages\":[]"),
    "a defaulted member list is written as the empty list it decoded to"
)
check(
    decoded(minimalText, "minimal round trip") == minimal,
    "a minimal document survives a write/read cycle, so the upgrade is loss-free"
)

// MARK: - 5. Canonical text on write, including optional dates

let additiveText = encodedText(additive, "additive state")
check(
    additiveText.contains("\"createdAt\":\"2026-01-01T00:00:00.000Z\""),
    "a required date read from the seconds form is written with three fractional digits"
)
check(
    additiveText.contains("\"lastUpdatedAt\":\"2026-01-02T03:04:05.123Z\""),
    "an optional date is written through the canonical formatter, not as an epoch number"
)
check(
    additiveText.contains("\"lastSuccessfulRefresh\":\"2026-02-02T00:00:00.000Z\""),
    "the second optional playlist date is canonical too"
)
check(
    additiveText.contains("\"recentWatches\":[]"),
    "a newly written document always includes recentWatches"
)
check(
    additiveText.contains("\"sourcePolicy\""),
    "a newly written document always includes sourcePolicy"
)
check(
    additiveText.contains("\"rendererCapability\":\"Not Yet Verified\""),
    "a newly written document always includes rendererCapability"
)
check(
    !additiveText.contains("\"watchedAt\""),
    "no watch records are invented for a document that had none"
)
// The strict half of the date contract: no timestamp may leave this codec as a bare
// number, because Dart writes text and task B3 compares the two ports' documents.
// Two guards, because each catches a different regression. The per-key guard is what a
// date-strategy mistake actually produces (`JSONEncoder`'s default writes a Double
// seconds-since-2001 for every `Date`), and it cannot be fooled by the document's other
// numbers. The fractional scan additionally catches an integer field that became a
// float, but must anchor on a value boundary: the naive `:[0-9]+\.[0-9]+` matches
// *inside* every canonical timestamp, because `T00:00:00.000` contains `:00.000`.
//
// Only fields this document holds a real value for are listed. `lastFailedPlaybackAt`
// is null in both sources and this encoder omits null keys (the Dart writer emits an
// explicit null; both decode to the same value, which is why B3 compares parsed values
// rather than text), so asserting its presence here would be a tautology.
let dateFieldNames = [
    "createdAt",
    "lastUpdatedAt",
    "lastSuccessfulRefresh",
    "lastSuccessfulPlaybackAt"
]
for name in dateFieldNames {
    check(
        additiveText.range(of: "\"\(name)\":[0-9]", options: .regularExpression) == nil,
        "the \(name) field is never written as a bare epoch number"
    )
    check(
        additiveText.contains("\"\(name)\":\""),
        "the \(name) field is written as canonical text"
    )
}
check(
    additiveText.range(of: #":[0-9]+\.[0-9]+[,}\]]"#, options: .regularExpression) == nil,
    "no numeric field in the document carries a fractional part"
)

let watchState = LiveCatalogState(
    schemaVersion: 1,
    playlists: [],
    members: [],
    sources: [],
    associations: [],
    preferences: [],
    recentWatches: [ChannelWatchRecord(channelId: "ch-1", watchedAt: Date(timeIntervalSince1970: 1_767_225_600))],
    logicalIdByMemberId: [:]
)
check(
    encodedText(watchState, "watch state").contains("\"watchedAt\":\"2026-01-01T00:00:00.000Z\""),
    "a watch record's timestamp is written canonically"
)
check(
    decoded(encodedText(watchState, "watch state round trip"), "watch state round trip") == watchState,
    "watch records survive a write/read cycle"
)
check(
    encodedText(LiveCatalogState.empty, "empty state").contains("\"schemaVersion\":1"),
    "the empty state writes the version it declares"
)

// MARK: - 6. Round trip preserves every record

let roundTrip = decoded(additiveText, "additive round trip")
check(roundTrip == additive, "encode then decode preserves the whole state")
check(roundTrip.playlists.count == additive.playlists.count, "playlist count preserved")
check(roundTrip.members == additive.members, "members preserved")
check(roundTrip.sources == additive.sources, "sources preserved")
check(roundTrip.associations == additive.associations, "associations preserved")
check(roundTrip.preferences == additive.preferences, "preferences preserved")
check(roundTrip.recentWatches == additive.recentWatches, "recent watches preserved")
check(roundTrip.logicalIdByMemberId == additive.logicalIdByMemberId, "member mapping preserved")

// MARK: - 7. A secret-backed address never reaches the document

let secretState = decoded(secretBackedSourceJSON, "secret-backed document")
check(secretState.sources.count == 1, "the secret-backed source decoded")
check(secretState.sources[0].streamUrl.isEmpty, "the secret-backed source holds no address")
let secretText = encodedText(secretState, "secret-backed state")
check(!secretText.contains("streamUrl"), "encoding omits streamUrl entirely when a secret reference exists")
check(
    secretText.contains("\"streamSecretRef\":\"secret:ccloud-live-s-secret\""),
    "encoding keeps the reference that replaces the address"
)
check(decoded(secretText, "secret-backed round trip") == secretState, "a secret-backed source round-trips")
expectDataCorrupted("a source with neither streamUrl nor streamSecretRef") {
    try LiveCatalogStateCodec.decode(Data(addresslessSourceJSON.utf8))
}
expectDataCorrupted("a null streamUrl without a secret reference") {
    try LiveCatalogStateCodec.decode(mutated(
        "null streamUrl",
        from: addresslessSourceJSON,
        "\"protocolHint\":\"hls\",",
        to: "\"streamUrl\":null,\"protocolHint\":\"hls\","
    ))
}

// MARK: - 8. Unknown or malformed documents fail closed, on read and on write

let schemaTwoData = mutated(
    "schemaVersion 2",
    from: additiveV1JSON,
    "\"schemaVersion\": 1,",
    to: "\"schemaVersion\": 2,"
)
expectSchemaError("a future schema version on read") {
    try LiveCatalogStateCodec.decode(schemaTwoData)
}
expectSchemaError("a future schema version on migrate") {
    try LiveCatalogMigration.migrate(schemaTwoData)
}
var futureState = additive
futureState.schemaVersion = 2
expectSchemaError("a future schema version on encode") {
    try LiveCatalogStateCodec.encode(futureState)
}
futureState.schemaVersion = 0
expectSchemaError("a zero schema version on encode") {
    try LiveCatalogStateCodec.encode(futureState)
}
check(
    LiveCatalogSchemaError.unsupportedVersion.message == "Unsupported live catalog schema",
    "the typed Swift error carries the exact text the Dart codec and the webOS port throw"
)
expectDataCorrupted("a string schemaVersion") {
    try LiveCatalogStateCodec.decode(mutated(
        "string schemaVersion",
        from: additiveV1JSON,
        "\"schemaVersion\": 1,",
        to: "\"schemaVersion\": \"1\","
    ))
}
expectDataCorrupted("a boolean schemaVersion") {
    try LiveCatalogStateCodec.decode(mutated(
        "boolean schemaVersion",
        from: additiveV1JSON,
        "\"schemaVersion\": 1,",
        to: "\"schemaVersion\": true,"
    ))
}
expectDataCorrupted("a fractional schemaVersion") {
    try LiveCatalogStateCodec.decode(mutated(
        "fractional schemaVersion",
        from: additiveV1JSON,
        "\"schemaVersion\": 1,",
        to: "\"schemaVersion\": 1.5,"
    ))
}
expectDataCorrupted("an absent schemaVersion") {
    try LiveCatalogStateCodec.decode(mutated(
        "absent schemaVersion",
        from: additiveV1JSON,
        "\"schemaVersion\": 1,",
        to: ""
    ))
}
expectDataCorrupted("malformed JSON text") {
    try LiveCatalogStateCodec.decode(Data("{ not json".utf8))
}
expectDataCorrupted("an empty document passed straight to decode") {
    try LiveCatalogStateCodec.decode(Data("".utf8))
}
expectDataCorrupted("a top-level array instead of an object") {
    try LiveCatalogStateCodec.decode(Data("[1,2,3]".utf8))
}
expectDataCorrupted("a top-level string instead of an object") {
    try LiveCatalogStateCodec.decode(Data("\"2026-01-01\"".utf8))
}

// MARK: - 9. The legacy media stores are never opened or rewritten

let favoritesPath = "\(fixtureDirectory)/macos-favorites.json"
let historyPath = "\(fixtureDirectory)/macos-history.json"
guard let favoritesBefore = FileManager.default.contents(atPath: favoritesPath),
      let historyBefore = FileManager.default.contents(atPath: historyPath) else {
    fail("the legacy migration fixtures must exist for this task to prove they stay untouched")
}
check(
    String(decoding: favoritesBefore, as: UTF8.self) == legacyFavoritesJSON,
    "macos-favorites.json still holds the legacy FavoriteEntry shape the plan pinned"
)
check(
    String(decoding: historyBefore, as: UTF8.self) == legacyHistoryJSON,
    "macos-history.json still holds the legacy HistoryEntry shape the plan pinned"
)
let legacyFavoritesArray = must("legacy favourites parse") {
    try JSONSerialization.jsonObject(with: favoritesBefore)
} as? [Any]
check(legacyFavoritesArray?.count == 1, "the legacy favourites document is still a one-entry array")
let legacyHistoryArray = must("legacy history parse") {
    try JSONSerialization.jsonObject(with: historyBefore)
} as? [Any]
check(legacyHistoryArray?.count == 1, "the legacy history document is still a one-entry array")
// Exercise every read and write path this task ships, then prove the legacy bytes are
// untouched. This harness performs no write, so a difference could only come from
// migration growing side effects into the catalog codec — which is precisely the
// behaviour task B4 must not acquire silently.
_ = must("migrate v1 after reading legacy fixtures") { try LiveCatalogMigration.migrate(Data(v1FixtureText.utf8)) }
_ = must("migrate additive") { try LiveCatalogMigration.migrate(Data(additiveV1JSON.utf8)) }
_ = must("encode additive after reading legacy fixtures") { try LiveCatalogMigration.encode(additive) }
check(
    FileManager.default.contents(atPath: favoritesPath) == favoritesBefore,
    "migration did not rewrite macos-favorites.json"
)
check(
    FileManager.default.contents(atPath: historyPath) == historyBefore,
    "migration did not rewrite macos-history.json"
)

// MARK: - 10. Snapshot and playback-context types serialize as declared

let logicalChannel = LogicalChannel(
    channelId: "ch-1",
    displayName: "IRIB 1",
    normalizedName: "irib 1",
    logoUrl: nil,
    category: "General",
    countryCode: "IR",
    languages: ["fa"],
    memberIds: ["m-1", "m-2"],
    sources: [firstSource, secondSource],
    favorite: true,
    hidden: false,
    userOrder: nil,
    automaticFailoverEnabled: true,
    sourcePolicy: SourcePolicy.standard,
    lastSuccessfulSourceId: "s-2"
)
let snapshot = UnifiedCatalogSnapshot(
    revision: 4,
    generatedAt: Date(timeIntervalSince1970: 1_767_225_600),
    playlists: additive.playlists,
    channels: [logicalChannel],
    issues: [CatalogIssue(code: "playlist_unreachable", message: "Playlist unreachable", line: 12)]
)
let snapshotData = must("snapshot encode") { try LiveCatalogStateCodec.makeEncoder().encode(snapshot) }
let snapshotText = String(decoding: snapshotData, as: UTF8.self)
check(
    snapshotText.contains("\"generatedAt\":\"2026-01-01T00:00:00.000Z\""),
    "a snapshot timestamp uses the same canonical text as persisted state"
)
check(
    snapshotText.contains("\"streamSecretRef\":\"secret:ccloud-live-s-2\""),
    "a snapshot carries the reference instead of the address"
)
// Two sources, one with an address and one held in a secret reference: a snapshot that
// only ever carried the secret-backed source would pass a blanket "no streamUrl text"
// check for the wrong reason. Here the plain sibling proves the key is written when it
// may be, so the count below measures the omission rule rather than its absence.
let streamUrlKeys = snapshotText.components(separatedBy: "\"streamUrl\"").count - 1
// The address is read back out of the parsed document instead of searching `snapshotText`
// for the URL: Foundation's JSON writer escapes forward slashes on Apple platforms — the
// same behaviour the API layer already strips at `Sources/Core/APIClient.swift:206` — so the
// encoded text holds `https:\/\/stream.example\/irib1.m3u8`. A substring test there would be
// measuring the writer's escaping rather than the contract, and a future Foundation that
// stops escaping would turn this red for a reason no user cares about. The parsed value is
// the contract; the escaping is encoding noise both readers undo.
let snapshotDocument = must("snapshot document parses") {
    try JSONSerialization.jsonObject(with: snapshotData)
}
let snapshotChannels = (snapshotDocument as? [String: Any])?["channels"] as? [[String: Any]]
let snapshotSources = snapshotChannels?.first?["sources"] as? [[String: Any]]
check(snapshotSources?.count == 2, "the persisted snapshot document carries both sources")
check(
    snapshotSources?[0]["streamUrl"] as? String == "https://stream.example/irib1.m3u8",
    "the snapshot keeps the address of the source that stores one"
)
check(
    snapshotSources?[1]["streamUrl"] == nil,
    "the snapshot writes no address value at all for the secret-backed source"
)
check(
    snapshotSources?[1]["streamSecretRef"] as? String == "secret:ccloud-live-s-2",
    "the secret-backed source keeps its reference in the persisted document"
)
check(
    streamUrlKeys == 1,
    "the snapshot writes one address key for its two sources, so the secret-backed one is omitted"
)
let snapshotRoundTrip = must("snapshot decode") {
    try LiveCatalogStateCodec.makeDecoder().decode(UnifiedCatalogSnapshot.self, from: snapshotData)
}
check(snapshotRoundTrip.revision == 4, "snapshot revision survived")
check(snapshotRoundTrip.channels.count == 1, "snapshot channel survived")
check(snapshotRoundTrip.channels[0].sources.count == 2, "snapshot source list survived")
check(snapshotRoundTrip.channels[0].memberIds == ["m-1", "m-2"], "snapshot member order survived")
check(snapshotRoundTrip.playlists.count == 2, "snapshot playlist list survived")
check(snapshotRoundTrip.issues[0].line == 12, "issue line number survived")
check(snapshotRoundTrip == snapshot, "a snapshot round-trips through the shared codec configuration")

let context = LivePlaybackContext(
    playlistId: "builtin:live",
    logicalChannelId: "ch-1",
    sourceIds: ["s-1", "s-2"],
    automaticFailoverEnabled: true,
    sourcePolicy: SourcePolicy.standard
)
let contextData = must("playback context encode") { try JSONEncoder().encode(context) }
check(
    must("playback context decode") { try JSONDecoder().decode(LivePlaybackContext.self, from: contextData) } == context,
    "the playback context round-trips"
)
check(context.sourceIds == ["s-1", "s-2"], "candidate order is preserved, which is how failover is specified")

let attempt = PlaybackAttemptContext(
    requestGeneration: "gen-1",
    playlistId: "builtin:live",
    logicalChannelId: "ch-1",
    sourceId: "s-1",
    attemptNumber: 1,
    stableMediaIdentity: "identity-1"
)
let staleAttempt = PlaybackAttemptContext(
    requestGeneration: "gen-0",
    playlistId: "builtin:live",
    logicalChannelId: "ch-1",
    sourceId: "s-1",
    attemptNumber: 1,
    stableMediaIdentity: "identity-1"
)
check(attempt != staleAttempt, "a superseded generation is distinguishable, so a stale player callback cannot commit state")
check(RendererSupport.supported.rawValue == "Supported", "the persisted capability labels are the contract's exact strings")
check(RendererSupport.partiallySupported.rawValue == "Partially Supported", "Partially Supported persists verbatim")
check(RendererSupport.unsupported.rawValue == "Unsupported", "Unsupported persists verbatim")
check(RendererSupport.notYetVerified.rawValue == "Not Yet Verified", "Not Yet Verified persists verbatim")

// MARK: - Multi-source playlist parser (task B2-S)

// The same bytes the Dart suite (B2-D) reads, so a difference in verdict is a difference in the
// platforms a user can actually move a catalog between. Everything below is pinned against the
// parsed object rather than encoded text: Foundation escapes `/` as `\/` in JSON, so a raw
// substring comparison could never be port-neutral (proof: `Sources/Core/APIClient.swift:206`).
let playlistFixtureDirectory = "\(repoRoot)/Tests/fixtures/multi-source"

func playlistFixture(_ name: String) -> String {
    let path = "\(playlistFixtureDirectory)/\(name)"
    guard let data = FileManager.default.contents(atPath: path) else {
        fail("missing fixture \(path)")
    }
    guard let text = String(data: data, encoding: .utf8) else {
        fail("fixture \(path) is not UTF-8")
    }
    return text
}

func issueCodes(_ issues: [CatalogIssue]) -> [String] {
    issues.map(\.code)
}

// MARK: identity hash

check(StableKeyHash.hash("same") == StableKeyHash.hash("same"),
      "stableKeyHash is deterministic across calls")
check(StableKeyHash.hash("same") != StableKeyHash.hash("different"),
      "stableKeyHash separates distinct inputs")
check(StableKeyHash.hash("same").count == 32, "the identity digest is 128 bits, rendered as 32 digits")
check(StableKeyHash.hash("same") == StableKeyHash.hash("same").lowercased(),
      "identity digits are lowercase, so a persisted id never depends on a platform's case rules")
check(StableKeyHash.hash("").count == 32, "the empty input still yields a full 32-digit value")
check(StableKeyHash.hash("") != StableKeyHash.hash("same"),
      "an unseeded accumulator cannot masquerade as the empty-input hash")
check(StableKeyHash.hash("پرس").count == 32, "non-ASCII input hashes over UTF-8 bytes")
check(StableKeyHash.hash("پرس") != StableKeyHash.hash("press"),
      "Persian and Latin spellings are distinct identities, not one folded key")

let hashSegments = stride(from: 0, to: 32, by: 8).map {
    String(Array(StableKeyHash.hash("segment-check"))[$0..<$0 + 8])
}
check(hashSegments.count == 4, "the digest is four eight-digit passes")
check(Set(hashSegments).count == 4,
      "all four FNV passes contribute, so a single-pass bug is visible: \(hashSegments)")

// Golden vectors. These lines exist so the webOS and Dart ports can pin the *same literals* rather
// than trusting that three independent implementations of one recipe agree; the values are printed
// from the runner, never transcribed from a developer machine.
for golden in ["", "playlist:valid", "پرس"] {
    print("golden stableKeyHash(\"\(golden)\") = \(StableKeyHash.hash(golden))")
}

// MARK: match key

check(LiveMatchKey.key("پرس تی‌وی") == LiveMatchKey.key("پرس تی وی"),
      "the match key folds ZWNJ into a separator")
check(LiveMatchKey.key("IRIB ۱") == LiveMatchKey.key("irib 1"),
      "the match key folds Persian digits, which Foundation's folding does not")
check(LiveMatchKey.key("  Press-TV  ") == "press tv", "the match key drops punctuation and edges")
check(LiveMatchKey.key("Press TV (720p)") == "press tv 720p",
      "the match key folds separators but deliberately does not strip quality noise")
check(LiveMatchKey.key(LiveTVM3UText.displayName("Press TV (720p)")) == "press tv",
      "so the shared display-name rule is what removes the quality token before matching")

// MARK: parsePlaylist

let validText = playlistFixture("valid.m3u")
let valid = LivePlaylistParser.parse(playlistID: "playlist:valid", text: validText, baseURL: nil)
check(valid.contentHash == StableKeyHash.hash(validText),
      "contentHash is the identity of the exact decoded bytes")
check(valid.inputBytes == validText.utf8.count, "inputBytes counts UTF-8 bytes, not characters")
check(valid.format == .m3uChannelList, "a headed channel list is classified as one")
check(!valid.truncated, "a fixture inside every ceiling is not reported as partial")
check(valid.channels.count == 3, "the valid fixture yields three channels")
check(valid.channels.first?.providerChannelId == "PressTV",
      "the `@quality` marker and the country suffix are stripped from provider identity")
check(valid.channels.first?.countryCode == "IR", "the country comes from the tvg-id suffix")
check(valid.channels.first?.streamUrls.count == 2, "quality variants stay two separate addresses")
check(valid.channels.first?.logoUrl == "https://img.example/press.png", "tvg-logo survives")
check(valid.channels.last?.languages.isEmpty == true,
      "a row without tvg-language invents no language")
check(valid.channels.first?.displayName == "Press TV", "the display name drops the quality token")
check(valid.channels.first?.tvgId == "PressTV.ir",
      "the untouched tvg-id survives for identity review")
check(valid.channels.first?.line == 2, "line numbers are 1-based physical lines")
check(valid.channels.last?.providerChannelId == "MusicTV", "the third row keeps its own id")
check(valid.channels.last?.streamUrls == ["https://music.example/live.m3u8"],
      "a single address stays single")
check(valid.channels.first?.languages == ["English"], "tvg-language is parsed, not guessed")
check(valid.channels.map { $0.countryCode ?? "" } == ["IR", "IR", "IR"],
      "every fixture row states Iran in its own tvg-id")
check(valid.issues.isEmpty, "a clean playlist reports no issues")

let empty = LivePlaylistParser.parse(
    playlistID: "playlist:empty", text: playlistFixture("empty.m3u"), baseURL: nil
)
check(empty.format == .empty, "a header-only document is empty rather than invalid")
check(empty.channels.isEmpty && empty.issues.isEmpty,
      "an empty catalog is invented from nothing, with no phantom issues")
check(!empty.truncated, "eight bytes cross no ceiling")

let hls = LivePlaylistParser.parse(
    playlistID: "playlist:hls", text: playlistFixture("hls-master.m3u8"), baseURL: nil
)
check(hls.format == .hlsMediaManifest,
      "an HLS master manifest is classified, not imported as channels")
check(hls.issues.first?.code == "unsupportedMediaManifest" && hls.issues.count == 1,
      "the manifest refusal is one named issue, not a silent empty list")
check(hls.channels.isEmpty, "no channel is invented from a media manifest")

let malformed = LivePlaylistParser.parse(
    playlistID: "playlist:malformed", text: playlistFixture("malformed.m3u"), baseURL: nil
)
check(malformed.format == .m3uChannelList, "one good row keeps the document a channel list")
check(malformed.channels.count == 1, "exactly one channel survives the malformed fixture")
check(malformed.channels.first?.displayName == "Good TV", "the surviving row is the well-formed one")
for code in ["missingName", "missingStream", "malformedEntry", "invalidUrl"] {
    check(issueCodes(malformed.issues).contains(code),
          "the malformed fixture reports \(code)")
}
check(malformed.issues.allSatisfy { ($0.line ?? 0) > 0 },
      "every issue names a physical line, because the UI has to say which row broke")

let twinText = "#EXTM3U\n"
    + "#EXTINF:-1 ,Twin TV\nhttps://twin.example/a.m3u8\n"
    + "#EXTINF:-1 ,Twin TV\nhttps://twin.example/b.m3u8\n"
let twin = LivePlaylistParser.parse(playlistID: "playlist:twin", text: twinText, baseURL: nil)
check(twin.channels.count == 2,
      "identity rule 2: two id-less rows of one name stay two channels")
check(twin.channels.first?.providerChannelId != twin.channels.last?.providerChannelId,
      "the fallback key carries an occurrence index, so twins cannot collapse")
check(twin.channels.first?.providerChannelId.hasPrefix("fallback:") == true,
      "a fallback identity is visibly a fallback")
let twinRegistry = LiveSourceRegistry.register(
    parsed: twin, playlistId: "playlist:twin", providerNamespace: "fixture:provider"
)
check(twinRegistry.members.count == 2 && twinRegistry.sources.count == 2,
      "the registry keeps the twins separate all the way to sources")
check(twinRegistry.members.first?.memberId != twinRegistry.members.last?.memberId,
      "two fallback members never share an id")

let relText = "#EXTM3U\n#EXTINF:-1 tvg-id=\"Rel.ir\",Rel TV\nstream.m3u8\n"
let relNoBase = LivePlaylistParser.parse(playlistID: "playlist:rel", text: relText, baseURL: nil)
check(relNoBase.channels.isEmpty, "a relative address without a base is not a channel")
check(issueCodes(relNoBase.issues).contains("invalidUrl"),
      "and the refusal is named rather than dropped")
let relWithBase = LivePlaylistParser.parse(
    playlistID: "playlist:rel", text: relText,
    baseURL: URL(string: "https://cdn.example/live/index.m3u8")
)
check(relWithBase.channels.first?.streamUrls == ["https://cdn.example/live/stream.m3u8"],
      "a relative address resolves against the HTTP(S) base the playlist was fetched from")
check(relWithBase.issues.isEmpty, "resolution is not an error")
let relFileBase = LivePlaylistParser.parse(
    playlistID: "playlist:rel", text: relText, baseURL: URL(string: "file:///tmp/index.m3u8")
)
check(relFileBase.channels.isEmpty,
      "a local base must not smuggle a relative path into a playable URL")
check(issueCodes(relFileBase.issues).contains("invalidUrl"), "and it says so")

let bigRows = (0..<50_001).map {
    "#EXTINF:-1 tvg-id=\"C\($0).ir\",Channel \($0)\nhttps://cdn.example/\($0).m3u8\n"
}.joined()
let memberCeiling = LivePlaylistParser.parse(
    playlistID: "playlist:large", text: "#EXTM3U\n\(bigRows)", baseURL: nil
)
check(memberCeiling.channels.count == 50_000,
      "the member ceiling keeps the permitted prefix instead of failing the playlist")
check(memberCeiling.truncated, "a truncated parse always says so")
check(issueCodes(memberCeiling.issues).contains("limitExceeded"),
      "the ceiling is reported as limitExceeded")

let manyURLs = (0..<101).map { "https://cdn.example/\($0).m3u8" }.joined(separator: "\n")
let urlCeiling = LivePlaylistParser.parse(
    playlistID: "playlist:many",
    text: "#EXTM3U\n#EXTINF:-1 tvg-id=\"Many.ir\",Many TV\n\(manyURLs)\n",
    baseURL: nil
)
check(urlCeiling.channels.first?.streamUrls.count == 100,
      "the per-member URL ceiling keeps the first hundred addresses")
check(urlCeiling.truncated && issueCodes(urlCeiling.issues).contains("limitExceeded"),
      "the dropped hundred-and-first address is visible")

let padding = (0..<200_001).map { "# pad \($0)" }.joined(separator: "\n")
let lineCeiling = LivePlaylistParser.parse(
    playlistID: "playlist:lines",
    text: "#EXTM3U\n\(padding)\n#EXTINF:-1 tvg-id=\"Late.ir\",Late TV\n"
        + "https://cdn.example/late.m3u8\n",
    baseURL: nil
)
check(lineCeiling.truncated && issueCodes(lineCeiling.issues).contains("limitExceeded"),
      "the physical-line ceiling stops the scan and reports it")
check(lineCeiling.channels.isEmpty,
      "a row past the line ceiling is not imported, because its line number would be a lie")

let filler = String(repeating: "x", count: 10 * 1024 * 1024 + 16)
let oversized = LivePlaylistParser.parse(
    playlistID: "playlist:huge", text: "#EXTM3U\n\(filler)", baseURL: nil
)
check(oversized.channels.isEmpty, "a ten-mebibyte payload is refused, not parsed")
check(issueCodes(oversized.issues).contains("oversizedInput"),
      "oversizedInput is its own code, so a size problem never looks like a limit trip")
check(oversized.truncated && oversized.contentHash.isEmpty,
      "refused bytes are not hashed, because there is no imported content to key")

let headerless = LivePlaylistParser.parse(
    playlistID: "playlist:none", text: "https://cdn.example/orphan.m3u8\n", baseURL: nil
)
check(headerless.format == .invalid, "a document without #EXTM3U is not a channel list")
check(headerless.channels.isEmpty, "no orphan address becomes a channel")
check(issueCodes(headerless.issues).contains("malformedEntry"), "the header is a content issue")

// MARK: registerParsedPlaylist

let duplicatesRegistry = LiveSourceRegistry.register(
    parsed: LivePlaylistParser.parse(
        playlistID: "playlist:duplicates",
        text: playlistFixture("duplicates.m3u"),
        baseURL: nil
    ),
    playlistId: "playlist:duplicates",
    providerNamespace: "fixture:provider"
)
check(duplicatesRegistry.members.count == 2, "two ids are two members")
check(duplicatesRegistry.sources.count == 3, "three addresses are three sources")
check(duplicatesRegistry.sources.map(\.priority) == [0, 1, 0],
      "priority restarts for each member, so the second channel still has a primary")
check(duplicatesRegistry.sources.allSatisfy { $0.health == .unverified },
      "parsing a playlist is not evidence that a stream plays")
check(duplicatesRegistry.sources.allSatisfy { $0.rendererCapability == .notYetVerified },
      "no renderer capability is claimed without recorded playback evidence")
check(duplicatesRegistry.sources.allSatisfy { !$0.sourceId.contains("https://") },
      "an identifier never embeds the raw address it was built from")
let dupFirstMemberId = "member:" + StableKeyHash.hash(
    "playlist:duplicates\nprovider\nfixture:provider\nDup"
)
check(duplicatesRegistry.members.first?.memberId == dupFirstMemberId,
      "identity rule 1 is spelled out, because the ports paste these exact seeds")
check(duplicatesRegistry.sources.first?.sourceId
    == "source:" + StableKeyHash.hash(
        "\(dupFirstMemberId)\nurl\nhttps://dup.example/a.m3u8"
    ),
    "identity rule 3 keys on the canonical address")
check(duplicatesRegistry.sources.first?.channelId == dupFirstMemberId,
      "identity rule 4: a new logical channel uses its member id")
check(duplicatesRegistry.sources.first?.memberId == dupFirstMemberId,
      "the source records the member it came from")
check(duplicatesRegistry.sources.first?.playlistId == "playlist:duplicates"
    && duplicatesRegistry.sources.first?.providerNamespace == "fixture:provider",
    "a source keeps its real playlist and namespace ownership")
check(duplicatesRegistry.sources.first?.origin == .playlist,
      "a parsed address is a playlist origin, not a user addition")
check(duplicatesRegistry.sources.first?.enabled == true,
      "a fresh source is enabled but unverified")
check(duplicatesRegistry.sources.first?.streamUrl == "https://dup.example/a.m3u8"
    && duplicatesRegistry.sources.first?.streamSecretRef == nil,
    "a plaintext address is stored in streamUrl and never in a secret reference")
check(duplicatesRegistry.sources.first?.lastSuccessfulPlaybackAt == nil
    && duplicatesRegistry.sources.first?.lastFailedPlaybackAt == nil,
    "no playback history is invented at parse time")
check(duplicatesRegistry.members.first?.normalizedName == "dup tv",
      "the match key is stored beside the display name")
check(duplicatesRegistry.members.first?.displayName == "Dup TV"
    && duplicatesRegistry.members.first?.group == "News"
    && duplicatesRegistry.members.first?.countryCode == "IR",
    "the member keeps what the playlist stated")
check(duplicatesRegistry.members.first?.ordinal == 0
    && duplicatesRegistry.members.last?.ordinal == 1,
    "ordinals preserve source position so user order survives a refresh")
check(duplicatesRegistry.members.first?.providerChannelId == "Dup",
      "identity keys on the stripped provider id")
check(duplicatesRegistry.members.first?.tvgId == "Dup.ir",
      "while the member still records the raw attribute, so an `@SD` feed is recognisable")
check(duplicatesRegistry.sources.first?.label == "منبع اصلی",
      "the first source of a member is named in Persian")
check(duplicatesRegistry.sources[1].label == "منبع ۲",
      "later sources are counted with Persian digits")
check(duplicatesRegistry.sources.last?.label == "منبع اصلی",
      "counting restarts per member")
check(duplicatesRegistry.issues.isEmpty, "a clean registration reports no issues")

let hintText = "#EXTM3U\n#EXTINF:-1 tvg-id=\"Hints.ir\",Hints TV\n"
    + "https://cdn.example/a.m3u8\nhttps://cdn.example/b.mpd\n"
    + "https://cdn.example/c.MP4?x=M3U8\nhttps://cdn.example/d.m3u8?sig=1\n"
    + "https://cdn.example/stream\n"
let hintRegistry = LiveSourceRegistry.register(
    parsed: LivePlaylistParser.parse(playlistID: "playlist:hint", text: hintText, baseURL: nil),
    playlistId: "playlist:hint",
    providerNamespace: "fixture:provider"
)
check(hintRegistry.sources.map(\.protocolHint) == ["hls", "dash", "mp4", "hls", "unknown"],
      "the hint comes from the canonical path extension only, never from the query")

check(LivePlaylistParser.canonicalStreamURL("HTTPS://CDN.Example:443/Live.A.m3u8?Q=1")
    == "https://cdn.example/Live.A.m3u8?Q=1",
    "canonicalization folds scheme and host only: path case is case-sensitive on CDNs")
check(LivePlaylistParser.canonicalStreamURL("http://cdn.example:80/a.m3u8")
    == "http://cdn.example/a.m3u8",
    "a default port is the same origin as no port, so keeping both would double every list")
check(LivePlaylistParser.canonicalStreamURL("https://cdn.example/a.m3u8#top") == nil,
    "a fragment is refused rather than stripped, because two rows would silently merge")
check(LivePlaylistParser.canonicalStreamURL("ftp://cdn.example/a.m3u8") == nil,
    "only HTTP(S) is playable on this build")
check(LivePlaylistParser.canonicalStreamURL("not a url") == nil,
    "an unparseable address is refused, not stored")
check(LivePlaylistParser.canonicalStreamURL("https://cdn.example") == nil,
    "no path means no manifest to play")
check(LivePlaylistParser.canonicalStreamURL("https://user:pass@cdn.example/a.m3u8") == nil,
    "userinfo is a credential, not part of a canonical address")

check(LivePlaylistParser.isSensitiveURL("https://user:pass@cdn.example/a.m3u8"),
      "userinfo makes an address sensitive")
check(LivePlaylistParser.isSensitiveURL("https://cdn.example/a.m3u8?token=abc")
    && LivePlaylistParser.isSensitiveURL("https://cdn.example/a.m3u8?Key=abc"),
      "credential query keys are matched case-insensitively")
check(LivePlaylistParser.isSensitiveURL("https://cdn.example/a.m3u8?x=1&Signature=abc"),
      "any credential-looking key in the query marks the address")
check(!LivePlaylistParser.isSensitiveURL("https://cdn.example/a.m3u8;Signature=abc"),
      "a query only begins at `?`, so a path parameter is not a credential")
check(LivePlaylistParser.isSensitiveURL("https://cdn.example/a.m3u8?auth=1")
    && LivePlaylistParser.isSensitiveURL("https://cdn.example/a.m3u8?credential=x")
    && LivePlaylistParser.isSensitiveURL("https://cdn.example/a.m3u8?password=x"),
      "the whole canonical key set is recognised")
check(!LivePlaylistParser.isSensitiveURL("https://cdn.example/a.m3u8?quality=720")
    && !LivePlaylistParser.isSensitiveURL("https://cdn.example/monkey.m3u8")
    && !LivePlaylistParser.isSensitiveURL("https://cdn.example/a.m3u8?monkey=1"),
      "matching is on exact keys, or a legitimate `monkey` channel would silently disappear")

let credentialText = "#EXTM3U\n#EXTINF:-1 tvg-id=\"Secret.ir\",Secret TV\n"
    + "https://cdn.example/a.m3u8?token=abc\nhttps://cdn.example/b.m3u8\n"
let secretRegistry = LiveSourceRegistry.register(
    parsed: LivePlaylistParser.parse(playlistID: "playlist:secret", text: credentialText, baseURL: nil),
    playlistId: "playlist:secret",
    providerNamespace: "fixture:provider"
)
check(secretRegistry.sources.count == 1
    && secretRegistry.sources.first?.streamUrl == "https://cdn.example/b.m3u8"
    && secretRegistry.sources.first?.priority == 0,
    "a credential-bearing address never becomes a plaintext stream URL")
check(issueCodes(secretRegistry.issues).contains("secretStorageUnavailable"),
      "and it is refused with the honest code: the row parsed fine, only the store is missing")

let caseText = "#EXTM3U\n#EXTINF:-1 tvg-id=\"Same.ir\",Same TV\n"
    + "https://cdn.example/a.m3u8\nHTTPS://CDN.Example/a.m3u8\n"
let caseRegistry = LiveSourceRegistry.register(
    parsed: LivePlaylistParser.parse(playlistID: "playlist:case", text: caseText, baseURL: nil),
    playlistId: "playlist:case",
    providerNamespace: "fixture:provider"
)
check(caseRegistry.members.count == 1 && caseRegistry.sources.count == 1,
      "two spellings of one origin are one source")
check(caseRegistry.issues.isEmpty,
      "deduplicating is not an error and not a ceiling, so it must report nothing")
check(caseRegistry.sources.first?.streamUrl == "https://cdn.example/a.m3u8"
    && LivePlaylistParser.canonicalStreamURL(caseRegistry.sources.first!.streamUrl)
        == caseRegistry.sources.first?.streamUrl,
      "canonicalization is idempotent, or a refresh would mint a new sourceId and lose history")
check(caseRegistry.sources.first?.sourceId
    == "source:" + StableKeyHash.hash(
        "\(caseRegistry.members.first!.memberId)\nurl\nhttps://cdn.example/a.m3u8"
    ),
    "the deduplicated source keeps the canonical identity")

let longURL = "https://cdn.example/" + String(repeating: "a", count: 8_193) + ".m3u8"
let longText = "#EXTM3U\n#EXTINF:-1 tvg-id=\"Long.ir\",Long TV\n\(longURL)\n"
    + "https://cdn.example/ok.m3u8\n"
let longParsed = LivePlaylistParser.parse(playlistID: "playlist:urltoolong", text: longText, baseURL: nil)
let longRegistry = LiveSourceRegistry.register(
    parsed: longParsed, playlistId: "playlist:urltoolong", providerNamespace: "fixture:provider"
)
check(longRegistry.sources.count == 1
    && longRegistry.sources.first?.streamUrl == "https://cdn.example/ok.m3u8",
    "an over-long URL is dropped whole, never truncated into a plausible wrong address")
check(longParsed.truncated && issueCodes(longParsed.issues).contains("limitExceeded"),
      "and dropping it makes the parse partial, which the result must admit")

let pureFirst = LiveSourceRegistry.register(
    parsed: valid, playlistId: "playlist:valid", providerNamespace: "builtin:ccloud"
)
let pureSecond = LiveSourceRegistry.register(
    parsed: valid, playlistId: "playlist:valid", providerNamespace: "builtin:ccloud"
)
check(pureFirst.members.map(\.memberId) == pureSecond.members.map(\.memberId)
    && pureFirst.sources.map(\.sourceId) == pureSecond.sources.map(\.sourceId),
    "the registry is a pure function of one parse result, so a refresh cannot reshuffle identity")
let otherNamespace = LiveSourceRegistry.register(
    parsed: valid, playlistId: "playlist:valid", providerNamespace: "builtin:other"
)
check(otherNamespace.members.first?.memberId != pureFirst.members.first?.memberId,
    "a different namespace must not merge its identically-named channels")
check(!pureFirst.sources.isEmpty
    && pureFirst.sources.allSatisfy { $0.streamSecretRef == nil }
    && pureFirst.sources.allSatisfy { $0.health != .available }
    && pureFirst.members.allSatisfy { $0.providerNamespace == "builtin:ccloud" },
    "no secret reference, no capability claim and no ownership leak on a clean parse")

let emptyRegistry = LiveSourceRegistry.register(
    parsed: empty, playlistId: "playlist:empty", providerNamespace: "fixture:provider"
)
check(emptyRegistry.members.isEmpty && emptyRegistry.sources.isEmpty
    && emptyRegistry.issues.isEmpty,
    "a playlist with no usable row registers nothing at all")

// MARK: - Result

print("live foundation fixtures: \(fixtureDirectory)")
print("assertions: \(assertionsRun)")
