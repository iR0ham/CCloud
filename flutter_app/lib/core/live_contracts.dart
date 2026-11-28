import 'package:flutter/foundation.dart';

import 'live_catalog_codec.dart';

/// Canonical multi-source live TV contracts for the Flutter client.
///
/// Mirrors `Sources/Core/LiveTVContracts.swift` on macOS and
/// `CC.playlistContracts` in `webos_app/app/js/playlist_contracts.js`: the same
/// record names, the same field names, the same persisted JSON shape and the
/// same additive schema-v1 defaults, so a catalog written by one platform stays
/// readable on the others. Dates are RFC 3339 UTC strings in persisted JSON,
/// arrays preserve user or source order, and identifiers are opaque values that
/// never embed a raw URL, credential, provider token or display name.
///
/// This file is data only. Parsing, identity, persistence and playback live in
/// later layers, so the contracts can be unit-tested without a player, a
/// network stack or a device.
///
/// A playlist source is the thing the user manages: the built-in Iran catalog, a
/// remote URL, or a file they picked from local storage.
enum PlaylistSourceType { builtIn, remoteUrl, localFile }

/// Refresh state of one playlist, so a slow or broken source is visible instead
/// of silently showing a stale list.
enum PlaylistRefreshStatus { idle, refreshing, ready, error }

/// Playback evidence for one stream. `unverified` is the only state a freshly
/// parsed source may hold; nothing here is inferred from a successful parse.
enum SourceHealth { unverified, available, failed, disabled }

/// Whether a source came from playlist text or from an explicit user addition.
enum SourceOrigin { playlist, user }

/// The four capability labels every platform records for renderer support.
///
/// Values are persisted verbatim, so they are part of the cross-platform wire
/// format and must stay identical in Swift and JavaScript. A capability is only
/// ever raised from `Not Yet Verified` by recorded playback or engine evidence;
/// compiling against a player never proves support.
const List<String> rendererSupportValues = [
  'Supported',
  'Partially Supported',
  'Unsupported',
  'Not Yet Verified',
];

/// One playlist the user manages, with its refresh bookkeeping.
///
/// `locationRef` is never a raw credential-bearing URL: it is a built-in key, a
/// security-scoped bookmark/URI reference, or a secret-store reference.
@immutable
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

  /// Parser evolution for this record, so a re-parse can be forced when the
  /// channel-list grammar changes. The envelope's `schemaVersion` is the
  /// persisted format version; there is deliberately no second one per record.
  final int parsingVersion;
}

/// One channel entry as a single playlist stated it, before any cross-playlist
/// association. Members are never deleted by a refresh of another playlist.
@immutable
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

  /// Script- and case-folded match key used for candidate detection only. Name
  /// similarity never changes `logicalIdByMemberId` by itself.
  final String normalizedName;

  /// Position in the source playlist, so user order survives a re-parse.
  final int ordinal;
  final String? logoUrl;
  final String? group;
  final String? countryCode;
  final List<String> languages;
  final String? tvgId;
}

/// One playable stream belonging to a member.
///
/// `streamUrl` is a runtime value only: when `streamSecretRef` is present the
/// codec omits `streamUrl` entirely, so a signed address is never written to
/// shared storage. A platform without verified secret storage must reject
/// credential-bearing URLs explicitly rather than store them in plaintext.
@immutable
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

  /// Logical channel this source currently belongs to.
  final String channelId;
  final String memberId;
  final String playlistId;
  final String providerNamespace;
  final String label;
  final String streamUrl;
  final String? streamSecretRef;

  /// `hls`, `dash`, `mp4` or `unknown`, from the manifest or URL shape. A hint
  /// never claims that the renderer can actually play the stream.
  final String protocolHint;
  final String rendererCapability;
  final SourceOrigin origin;

  /// User-controlled order within the channel's source list.
  final int priority;
  final bool enabled;
  final SourceHealth health;
  final DateTime? lastSuccessfulPlaybackAt;
  final DateTime? lastFailedPlaybackAt;
  final String? lastErrorCode;
}

/// Bounded recovery settings for one logical channel.
///
/// These are resource-safety limits for a single playback request, not product
/// quotas, and only one recovery chain may run per logical channel.
@immutable
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

  /// Delays between successive advances, in milliseconds. The last entry is
  /// reused if a chain is longer than the list.
  final List<int> backoffMs;
  final int failedCooldownSeconds;

  /// How long buffering may stall before the attempt counts as failed.
  final int bufferingThresholdMs;
}

/// Runtime description of the enabled source set for one playback request.
@immutable
class LivePlaybackContext {
  const LivePlaybackContext({
    required this.playlistId,
    required this.logicalChannelId,
    required this.sourceIds,
    required this.automaticFailoverEnabled,
    required this.sourcePolicy,
  });

  /// Preferred logical member's playlist, for diagnostics only; every source
  /// keeps its own actual playlist ownership.
  final String playlistId;
  final String logicalChannelId;

  /// Same order as the enabled request-local sources.
  final List<String> sourceIds;
  final bool automaticFailoverEnabled;
  final SourcePolicy sourcePolicy;
}

/// Identifies one attempt inside one recovery chain.
///
/// Runtime only: never persisted and never encoded, so a stale recovery callback
/// can be cancelled by comparing `requestGeneration` instead of guessing.
@immutable
class PlaybackAttemptContext {
  const PlaybackAttemptContext({
    required this.requestGeneration,
    required this.playlistId,
    required this.logicalChannelId,
    required this.sourceId,
    required this.attemptNumber,
    required this.stableMediaIdentity,
  });

  /// Unique per playback request/recovery chain.
  final String requestGeneration;
  final String playlistId;
  final String logicalChannelId;
  final String sourceId;

  /// Starts at 1 and increments for every retry or advance.
  final int attemptNumber;

  /// `logicalChannelId` for live TV, otherwise the existing media identity.
  final String stableMediaIdentity;
}

/// A user-facing channel: one or more members associated explicitly by the user.
///
/// The first member is the preferred metadata and playlist owner. Identity is
/// selected by the user's `preferredLogicalId`, never derived from a stream URL.
@immutable
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

  /// Historical preference only: removing a source clears a reference to it,
  /// while disabling a source deliberately keeps the reference intact.
  final String? lastSuccessfulSourceId;
}

/// Two or more members the user declared to be the same channel.
@immutable
class ChannelAssociation {
  const ChannelAssociation({required this.memberIds});

  final List<String> memberIds;
}

/// Per-channel user state, kept separate from parsed members so a refresh
/// cannot overwrite favorites, ordering or failover settings.
@immutable
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

/// One entry of the live watch history.
@immutable
class ChannelWatchRecord {
  const ChannelWatchRecord({required this.channelId, required this.watchedAt});

  final String channelId;
  final DateTime watchedAt;
}

/// The persisted live catalog: playlists, their members, the sources parsed from
/// them, the user's associations and preferences, and the member-to-logical
/// channel mapping.
///
/// `schemaVersion` is the persisted format version and gates decoding.
@immutable
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

/// A safe, non-sensitive diagnostic about parsing, resolution or refresh.
///
/// `code` is one of the canonical `CatalogIssueCode` values; `message` must never
/// carry a credential or a sensitive query value.
@immutable
class CatalogIssue {
  const CatalogIssue({required this.code, required this.message, this.line});

  final String code;
  final String message;
  final int? line;
}

/// A built view of the catalog, never a second source of truth.
///
/// `revision` is repository-instance state: it starts at 1 after load and
/// increments once per successfully persisted mutation. `generatedAt` is
/// snapshot-build time in UTC, and `issues` holds only current issues.
@immutable
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

/// Entry point for reading persisted live catalog state.
///
/// Absent or empty stored text yields the canonical empty v1 state; anything
/// else is decoded by [LiveCatalogStateCodec], which throws instead of returning
/// a silently cleared catalog. A migration therefore never rewrites the existing
/// `ccloud.favorites` / `ccloud.history` preference keys either: it only reads
/// the live catalog key it owns.
class LiveCatalogMigration {
  static LiveCatalogState migrate(String? raw) {
    if (raw == null || raw.isEmpty) return const LiveCatalogState();
    return LiveCatalogStateCodec.decode(raw);
  }

  static String encode(LiveCatalogState state) =>
      LiveCatalogStateCodec.encode(state);
}
