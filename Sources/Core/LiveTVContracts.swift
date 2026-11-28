import Foundation

// Schema-v1 live catalog contracts (multi-source foundation, task B1-S).
//
// These types are the Swift half of a three-port contract: the Dart originals
// live in `flutter_app/lib/core/live_contracts.dart`, the ES2017 half arrives in
// `webos_app/app/js/playlist_contracts.js`, and the frozen document both ports
// must read is `Tests/fixtures/migration/catalog-v1.json`. Field names, JSON
// keys and enum raw values therefore are not free choices here — they are copied
// from "Canonical Contract" in
// `docs/superpowers/plans/2026-11-25-multi-source-subtitles.md`, and a rename on
// one port is a persistence break on the other two.
//
// Deliberately dependency-free: no AVFoundation, no UI, no networking. That is
// what lets `Tests/live-foundation/run.sh` compile these two core files with
// `xcrun swiftc` into a standalone hosted test binary, while
// `scripts/typecheck.sh` and `build.sh` compile them into the app module
// unchanged. Nothing in this file is read by the current Live TV screens yet —
// wiring a consumer and the on-disk migration trigger belong to tasks B2/B4, so
// shipping these declarations cannot change today's playback behaviour.

// MARK: - Enumerations

/// How a playlist's channel list is obtained.
enum PlaylistSourceType: String, Codable, Sendable {
    /// The built-in Famelack/iptv-org composition, which is not user-deletable.
    case builtIn
    /// An HTTP(S) M3U address the user supplied.
    case remoteUrl
    /// A file the user explicitly picked.
    case localFile
}

/// Lifecycle of the most recent (or in-flight) refresh of a playlist.
enum PlaylistRefreshStatus: String, Codable, Sendable {
    case idle
    case refreshing
    case ready
    case error
}

/// Playback history of a single source, used to order failover candidates.
enum SourceHealth: String, Codable, Sendable {
    case unverified
    case available
    case failed
    case disabled
}

/// Whether a source came from a playlist parse or from the user directly.
enum SourceOrigin: String, Codable, Sendable {
    case playlist
    case user
}

/// Subtitle and codec capability of this source on this platform.
///
/// The raw values are the user-facing labels, because they are persisted. A
/// source is only ever marked `supported` from real renderer/device evidence —
/// compiling successfully never proves support, so the default is
/// `notYetVerified`.
enum RendererSupport: String, Codable, Sendable {
    case supported = "Supported"
    case partiallySupported = "Partially Supported"
    case unsupported = "Unsupported"
    case notYetVerified = "Not Yet Verified"
}

// MARK: - Playlist and channel records

/// One playlist the user (or the built-in adapter) owns.
struct PlaylistRecord: Codable, Hashable, Sendable {
    var playlistId: String
    var name: String
    var sourceType: PlaylistSourceType
    /// File reference, URL, or `builtin:` token — never a credential.
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

/// A channel as one playlist reported it, before any user association.
struct ChannelMember: Codable, Hashable, Sendable {
    var memberId: String
    var playlistId: String
    /// Provider identity namespace, so two playlists can describe one channel.
    var providerNamespace: String
    var providerChannelId: String
    var displayName: String
    var normalizedName: String
    var logoUrl: String?
    var group: String?
    var countryCode: String?
    var languages: [String]
    var tvgId: String?
    /// Position within the playlist, preserved so user order survives a refresh.
    var ordinal: Int
}

/// A playable endpoint. `streamUrl` and `streamSecretRef` are mutually
/// authoritative: an address held in a secret reference is never persisted.
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

// The only coding surface that knows the secret-omission rule. This lives in the
// type's own file on purpose: the compiler decides whether to synthesize
// `init(from:)` and `encode(to:)` from the members declared in the type's
// declaration file, so the same extension placed in `LiveTVCatalogCodec.swift`
// would compile as a redeclaration of the synthesized members instead of replacing
// them. A silently synthesized pair here would persist `streamUrl` for a
// secret-backed source, which is the leak this code exists to prevent.
extension ChannelSourceRecord {
    enum CodingKeys: String, CodingKey {
        case sourceId
        case channelId
        case memberId
        case playlistId
        case providerNamespace
        case label
        case streamUrl
        case streamSecretRef
        case protocolHint
        case rendererCapability
        case origin
        case priority
        case enabled
        case health
        case lastSuccessfulPlaybackAt
        case lastFailedPlaybackAt
        case lastErrorCode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let secretRef = try container.decodeIfPresent(String.self, forKey: .streamSecretRef)
        let address = try container.decodeIfPresent(String.self, forKey: .streamUrl)
        let streamUrl: String
        if let address {
            streamUrl = address
        } else if secretRef != nil {
            // The address lives in a secret store; the document only carries the
            // reference, so decoding to an empty string is honest, not a default.
            streamUrl = ""
        } else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: """
                live catalog source.streamUrl is required unless the address is \
                held in a streamSecretRef
                """
            ))
        }
        self.init(
            sourceId: try container.decode(String.self, forKey: .sourceId),
            channelId: try container.decode(String.self, forKey: .channelId),
            memberId: try container.decode(String.self, forKey: .memberId),
            playlistId: try container.decode(String.self, forKey: .playlistId),
            providerNamespace: try container.decode(String.self, forKey: .providerNamespace),
            label: try container.decode(String.self, forKey: .label),
            streamUrl: streamUrl,
            streamSecretRef: secretRef,
            protocolHint: try container.decode(String.self, forKey: .protocolHint),
            rendererCapability: try container.decodeIfPresent(
                RendererSupport.self,
                forKey: .rendererCapability
            ) ?? .notYetVerified,
            origin: try container.decode(SourceOrigin.self, forKey: .origin),
            priority: try container.decode(Int.self, forKey: .priority),
            enabled: try container.decode(Bool.self, forKey: .enabled),
            health: try container.decode(SourceHealth.self, forKey: .health),
            lastSuccessfulPlaybackAt: try container.decodeIfPresent(
                Date.self,
                forKey: .lastSuccessfulPlaybackAt
            ),
            lastFailedPlaybackAt: try container.decodeIfPresent(
                Date.self,
                forKey: .lastFailedPlaybackAt
            ),
            lastErrorCode: try container.decodeIfPresent(String.self, forKey: .lastErrorCode)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourceId, forKey: .sourceId)
        try container.encode(channelId, forKey: .channelId)
        try container.encode(memberId, forKey: .memberId)
        try container.encode(playlistId, forKey: .playlistId)
        try container.encode(providerNamespace, forKey: .providerNamespace)
        try container.encode(label, forKey: .label)
        // The omission rule: a secret-backed source persists only the reference,
        // never the address it points at, so a signed URL can never reach a shared
        // preferences file or a diagnostic dump.
        if streamSecretRef == nil {
            try container.encode(streamUrl, forKey: .streamUrl)
        }
        try container.encodeIfPresent(streamSecretRef, forKey: .streamSecretRef)
        try container.encode(protocolHint, forKey: .protocolHint)
        try container.encode(rendererCapability, forKey: .rendererCapability)
        try container.encode(origin, forKey: .origin)
        try container.encode(priority, forKey: .priority)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(health, forKey: .health)
        try container.encodeIfPresent(lastSuccessfulPlaybackAt, forKey: .lastSuccessfulPlaybackAt)
        try container.encodeIfPresent(lastFailedPlaybackAt, forKey: .lastFailedPlaybackAt)
        try container.encodeIfPresent(lastErrorCode, forKey: .lastErrorCode)
    }
}

// MARK: - Policy and playback context

/// Bounded retry/failover policy carried with each logical channel.
///
/// Values are the defaults the specification settled on; they are persisted so a
/// future change cannot silently rewrite a user's tuned behaviour, and so an
/// older v1 document without the key still decodes (see `LiveCatalogStateCodec`).
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

/// What the player is asked to start: a logical channel plus its ordered
/// candidate sources. Persisted indirectly (through the channel), never mutated
/// by the player.
struct LivePlaybackContext: Codable, Hashable, Sendable {
    var playlistId: String
    var logicalChannelId: String
    var sourceIds: [String]
    var automaticFailoverEnabled: Bool
    var sourcePolicy: SourcePolicy
}

/// Runtime-only identity of one attempt, used to discard callbacks from a
/// superseded player session. Never encoded: an attempt must not outlive its
/// process, and a stale attempt must never be able to rewrite catalog state.
struct PlaybackAttemptContext: Hashable, Sendable {
    var requestGeneration: String
    var playlistId: String
    var logicalChannelId: String
    var sourceId: String
    var attemptNumber: Int
    var stableMediaIdentity: String
}

// MARK: - Aggregated catalog

/// The channel the user sees: members from one or more playlists, merged only
/// through an explicit association, plus the user's own preferences.
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

/// An explicit user statement that these members are one channel.
struct ChannelAssociation: Codable, Hashable, Sendable {
    var memberIds: [String]
}

/// Per-channel user state, kept separate from provider data so a refresh cannot
/// erase favourites, order or tuning.
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

/// One entry of the live watch history.
struct ChannelWatchRecord: Codable, Hashable, Sendable {
    var channelId: String
    var watchedAt: Date
}

/// The whole persisted live catalog under one schema version.
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

// MARK: - Parse and snapshot output

/// A non-fatal problem found while parsing a playlist or building a snapshot.
struct CatalogIssue: Codable, Hashable, Sendable {
    var code: String
    var message: String
    var line: Int?
}

/// Point-in-time view the UI renders, so a refresh cannot mutate a list mid-scroll.
struct UnifiedCatalogSnapshot: Codable, Hashable, Sendable {
    var revision: Int
    var generatedAt: Date
    var playlists: [PlaylistRecord]
    var channels: [LogicalChannel]
    var issues: [CatalogIssue]
}
