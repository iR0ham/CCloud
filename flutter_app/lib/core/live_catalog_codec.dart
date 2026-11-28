import 'dart:convert';

import 'live_contracts.dart';

/// Reads and writes the persisted schema-v1 [LiveCatalogState].
///
/// [LiveCatalogMigration] in `live_contracts.dart` is the entry point callers
/// use; this is the codec behind it. The rules come from the multi-source
/// contract:
///
/// * `schemaVersion` is prefighted before any record is decoded, and only
///   version 1 is understood;
/// * the canonical persisted text form of a timestamp is RFC 3339 UTC with
///   exactly three fractional digits, which is what
///   [DateTime.toIso8601String] emits; decoding also accepts the
///   seconds-precision form written by the frozen v1 fixture, so a port that
///   reads an older document still normalizes it, while only the canonical form
///   is ever written;
/// * v1 is additive, so a missing `recentWatches` decodes as an empty array, a
///   missing `sourcePolicy` as the standard policy, and a missing source
///   `rendererCapability` as `Not Yet Verified`, while new writes always include
///   all three;
/// * `rendererCapability` accepts only the four `RendererSupport` labels;
/// * a missing `streamUrl` decodes as empty only when `streamSecretRef` is
///   present, and encoding omits `streamUrl` whenever that reference exists, so
///   a signed address never reaches shared preferences;
/// * malformed JSON, an invalid field type and a future schema version all
///   throw. Nothing here ever returns a silently cleared state, because an
///   accidental empty write would destroy the user's playlists, associations and
///   preferences on the next save.
///
/// Encoding is total for [supportedSchemaVersion] and rejects every other
/// schema version, mirroring the decode preflight, so this codec can never write
/// a document it would then refuse to read back. Record *values* are still not
/// revalidated on write: the repository only ever hands this codec records it
/// built from decoded data, so validating twice would add no safety while making
/// a write path able to throw for a reason the read path already rejected.
class LiveCatalogStateCodec {
  /// The only persisted schema version this build can read.
  static const int supportedSchemaVersion = 1;

  static LiveCatalogState decode(String raw) {
    // `jsonDecode` throws FormatException for malformed text, which is exactly
    // the fail-closed behaviour the contract asks for.
    final Map<String, Object?> json = _object(jsonDecode(raw), 'live catalog state');
    if (json['schemaVersion'] != supportedSchemaVersion) {
      throw const FormatException('Unsupported live catalog schema');
    }
    return LiveCatalogState(
      schemaVersion: supportedSchemaVersion,
      playlists: _array(json['playlists'], 'playlists')
          .map(_playlist)
          .toList(growable: false),
      members: _array(json['members'], 'members')
          .map(_member)
          .toList(growable: false),
      sources: _array(json['sources'], 'sources')
          .map(_source)
          .toList(growable: false),
      associations: _array(json['associations'], 'associations')
          .map(_association)
          .toList(growable: false),
      preferences: _array(json['preferences'], 'preferences')
          .map(_preference)
          .toList(growable: false),
      // Additive: v1 documents written before recent watches existed decode as
      // an empty history instead of failing.
      recentWatches: json['recentWatches'] == null
          ? const <ChannelWatchRecord>[]
          : _array(json['recentWatches'], 'recentWatches')
              .map(_watch)
              .toList(growable: false),
      logicalIdByMemberId: _stringMap(
        json['logicalIdByMemberId'],
        'logicalIdByMemberId',
      ),
    );
  }

  static String encode(LiveCatalogState state) {
    // Symmetric with the decode preflight, and with the same message, so no port
    // can emit a document its own reader would reject.
    if (state.schemaVersion != supportedSchemaVersion) {
      throw const FormatException('Unsupported live catalog schema');
    }
    return jsonEncode(<String, Object?>{
      'schemaVersion': supportedSchemaVersion,
      'playlists': state.playlists.map(_playlistJson).toList(growable: false),
      'members': state.members.map(_memberJson).toList(growable: false),
      'sources': state.sources.map(_sourceJson).toList(growable: false),
      'associations': state.associations
          .map(_associationJson)
          .toList(growable: false),
      'preferences': state.preferences
          .map(_preferenceJson)
          .toList(growable: false),
      'recentWatches': state.recentWatches
          .map(_watchJson)
          .toList(growable: false),
      'logicalIdByMemberId': Map<String, String>.of(state.logicalIdByMemberId),
    });
  }

  // MARK: - Records

  static PlaylistRecord _playlist(Object? value) {
    final Map<String, Object?> json = _object(value, 'playlist');
    return PlaylistRecord(
      playlistId: _string(json['playlistId'], 'playlist.playlistId'),
      name: _string(json['name'], 'playlist.name'),
      sourceType: _enum<PlaylistSourceType>(
        json['sourceType'],
        PlaylistSourceType.values,
        'playlist.sourceType',
      ),
      locationRef: _string(json['locationRef'], 'playlist.locationRef'),
      enabled: _bool(json['enabled'], 'playlist.enabled'),
      createdAt: _date(json['createdAt'], 'playlist.createdAt'),
      lastUpdatedAt: _optDate(json['lastUpdatedAt'], 'playlist.lastUpdatedAt'),
      lastSuccessfulRefresh: _optDate(
        json['lastSuccessfulRefresh'],
        'playlist.lastSuccessfulRefresh',
      ),
      refreshStatus: _optEnum<PlaylistRefreshStatus>(
        json['refreshStatus'],
        PlaylistRefreshStatus.values,
        'playlist.refreshStatus',
        PlaylistRefreshStatus.idle,
      ),
      lastErrorCode: _optString(json['lastErrorCode'], 'playlist.lastErrorCode'),
      channelCount: _optInt(json['channelCount'], 'playlist.channelCount', 0),
      parsingVersion: _optInt(json['parsingVersion'], 'playlist.parsingVersion', 1),
    );
  }

  static Map<String, Object?> _playlistJson(PlaylistRecord record) {
    return <String, Object?>{
      'playlistId': record.playlistId,
      'name': record.name,
      'sourceType': record.sourceType.name,
      'locationRef': record.locationRef,
      'enabled': record.enabled,
      'createdAt': _dateText(record.createdAt),
      'lastUpdatedAt': _optDateText(record.lastUpdatedAt),
      'lastSuccessfulRefresh': _optDateText(record.lastSuccessfulRefresh),
      'refreshStatus': record.refreshStatus.name,
      'lastErrorCode': record.lastErrorCode,
      'channelCount': record.channelCount,
      'parsingVersion': record.parsingVersion,
    };
  }

  static ChannelMember _member(Object? value) {
    final Map<String, Object?> json = _object(value, 'member');
    return ChannelMember(
      memberId: _string(json['memberId'], 'member.memberId'),
      playlistId: _string(json['playlistId'], 'member.playlistId'),
      providerNamespace: _string(
        json['providerNamespace'],
        'member.providerNamespace',
      ),
      providerChannelId: _string(
        json['providerChannelId'],
        'member.providerChannelId',
      ),
      displayName: _string(json['displayName'], 'member.displayName'),
      normalizedName: _string(json['normalizedName'], 'member.normalizedName'),
      ordinal: _int(json['ordinal'], 'member.ordinal'),
      logoUrl: _optString(json['logoUrl'], 'member.logoUrl'),
      group: _optString(json['group'], 'member.group'),
      countryCode: _optString(json['countryCode'], 'member.countryCode'),
      languages: _optStringList(json['languages'], 'member.languages'),
      tvgId: _optString(json['tvgId'], 'member.tvgId'),
    );
  }

  static Map<String, Object?> _memberJson(ChannelMember member) {
    return <String, Object?>{
      'memberId': member.memberId,
      'playlistId': member.playlistId,
      'providerNamespace': member.providerNamespace,
      'providerChannelId': member.providerChannelId,
      'displayName': member.displayName,
      'normalizedName': member.normalizedName,
      'ordinal': member.ordinal,
      'logoUrl': member.logoUrl,
      'group': member.group,
      'countryCode': member.countryCode,
      'languages': List<String>.of(member.languages),
      'tvgId': member.tvgId,
    };
  }

  static ChannelSourceRecord _source(Object? value) {
    final Map<String, Object?> json = _object(value, 'source');
    final String? streamSecretRef = _optString(
      json['streamSecretRef'],
      'source.streamSecretRef',
    );
    final Object? streamUrl = json['streamUrl'];
    if (streamUrl == null && streamSecretRef == null) {
      throw const FormatException(
        'live catalog source.streamUrl is required unless the address is held '
        'in a streamSecretRef',
      );
    }
    return ChannelSourceRecord(
      sourceId: _string(json['sourceId'], 'source.sourceId'),
      channelId: _string(json['channelId'], 'source.channelId'),
      memberId: _string(json['memberId'], 'source.memberId'),
      playlistId: _string(json['playlistId'], 'source.playlistId'),
      providerNamespace: _string(
        json['providerNamespace'],
        'source.providerNamespace',
      ),
      label: _string(json['label'], 'source.label'),
      protocolHint: _string(json['protocolHint'], 'source.protocolHint'),
      rendererCapability: _optCapability(
        json['rendererCapability'],
        'source.rendererCapability',
      ),
      origin: _enum<SourceOrigin>(
        json['origin'],
        SourceOrigin.values,
        'source.origin',
      ),
      priority: _int(json['priority'], 'source.priority'),
      enabled: _bool(json['enabled'], 'source.enabled'),
      health: _enum<SourceHealth>(
        json['health'],
        SourceHealth.values,
        'source.health',
      ),
      streamUrl: streamUrl == null ? '' : _string(streamUrl, 'source.streamUrl'),
      streamSecretRef: streamSecretRef,
      lastSuccessfulPlaybackAt: _optDate(
        json['lastSuccessfulPlaybackAt'],
        'source.lastSuccessfulPlaybackAt',
      ),
      lastFailedPlaybackAt: _optDate(
        json['lastFailedPlaybackAt'],
        'source.lastFailedPlaybackAt',
      ),
      lastErrorCode: _optString(json['lastErrorCode'], 'source.lastErrorCode'),
    );
  }

  static Map<String, Object?> _sourceJson(ChannelSourceRecord source) {
    return <String, Object?>{
      'sourceId': source.sourceId,
      'channelId': source.channelId,
      'memberId': source.memberId,
      'playlistId': source.playlistId,
      'providerNamespace': source.providerNamespace,
      'label': source.label,
      // The omission rule: a secret-backed source persists only the reference,
      // never the address it points at.
      if (source.streamSecretRef == null) 'streamUrl': source.streamUrl,
      'streamSecretRef': source.streamSecretRef,
      'protocolHint': source.protocolHint,
      'rendererCapability': source.rendererCapability,
      'origin': source.origin.name,
      'priority': source.priority,
      'enabled': source.enabled,
      'health': source.health.name,
      'lastSuccessfulPlaybackAt': _optDateText(source.lastSuccessfulPlaybackAt),
      'lastFailedPlaybackAt': _optDateText(source.lastFailedPlaybackAt),
      'lastErrorCode': source.lastErrorCode,
    };
  }

  static ChannelAssociation _association(Object? value) {
    final Map<String, Object?> json = _object(value, 'association');
    return ChannelAssociation(
      memberIds: _stringList(json['memberIds'], 'association.memberIds'),
    );
  }

  static Map<String, Object?> _associationJson(ChannelAssociation association) {
    return <String, Object?>{
      'memberIds': List<String>.of(association.memberIds),
    };
  }

  static ChannelPreference _preference(Object? value) {
    final Map<String, Object?> json = _object(value, 'preference');
    return ChannelPreference(
      channelId: _string(json['channelId'], 'preference.channelId'),
      favorite: _optBool(json['favorite'], 'preference.favorite', false),
      hidden: _optBool(json['hidden'], 'preference.hidden', false),
      category: _optString(json['category'], 'preference.category'),
      userOrder: _nullableInt(json['userOrder'], 'preference.userOrder'),
      automaticFailoverEnabled: _optBool(
        json['automaticFailoverEnabled'],
        'preference.automaticFailoverEnabled',
        true,
      ),
      // Additive: a preference written before source policies existed receives
      // the standard policy rather than failing.
      sourcePolicy: _optPolicy(json['sourcePolicy'], 'preference.sourcePolicy'),
      lastSuccessfulSourceId: _optString(
        json['lastSuccessfulSourceId'],
        'preference.lastSuccessfulSourceId',
      ),
    );
  }

  static Map<String, Object?> _preferenceJson(ChannelPreference preference) {
    return <String, Object?>{
      'channelId': preference.channelId,
      'favorite': preference.favorite,
      'hidden': preference.hidden,
      'category': preference.category,
      'userOrder': preference.userOrder,
      'automaticFailoverEnabled': preference.automaticFailoverEnabled,
      'sourcePolicy': _policyJson(preference.sourcePolicy),
      'lastSuccessfulSourceId': preference.lastSuccessfulSourceId,
    };
  }

  static ChannelWatchRecord _watch(Object? value) {
    final Map<String, Object?> json = _object(value, 'recentWatch');
    return ChannelWatchRecord(
      channelId: _string(json['channelId'], 'recentWatch.channelId'),
      watchedAt: _date(json['watchedAt'], 'recentWatch.watchedAt'),
    );
  }

  static Map<String, Object?> _watchJson(ChannelWatchRecord watch) {
    return <String, Object?>{
      'channelId': watch.channelId,
      'watchedAt': _dateText(watch.watchedAt),
    };
  }

  static SourcePolicy _policy(Object? value, String field) {
    final Map<String, Object?> json = _object(value, field);
    const SourcePolicy standard = SourcePolicy();
    return SourcePolicy(
      maxAutomaticAttempts: _optInt(
        json['maxAutomaticAttempts'],
        '$field.maxAutomaticAttempts',
        standard.maxAutomaticAttempts,
      ),
      sameSourceRetries: _optInt(
        json['sameSourceRetries'],
        '$field.sameSourceRetries',
        standard.sameSourceRetries,
      ),
      connectTimeoutMs: _optInt(
        json['connectTimeoutMs'],
        '$field.connectTimeoutMs',
        standard.connectTimeoutMs,
      ),
      backoffMs: _optIntList(
        json['backoffMs'],
        '$field.backoffMs',
        standard.backoffMs,
      ),
      failedCooldownSeconds: _optInt(
        json['failedCooldownSeconds'],
        '$field.failedCooldownSeconds',
        standard.failedCooldownSeconds,
      ),
      bufferingThresholdMs: _optInt(
        json['bufferingThresholdMs'],
        '$field.bufferingThresholdMs',
        standard.bufferingThresholdMs,
      ),
    );
  }

  static SourcePolicy _optPolicy(Object? value, String field) {
    return value == null ? const SourcePolicy() : _policy(value, field);
  }

  static Map<String, Object?> _policyJson(SourcePolicy policy) {
    return <String, Object?>{
      'maxAutomaticAttempts': policy.maxAutomaticAttempts,
      'sameSourceRetries': policy.sameSourceRetries,
      'connectTimeoutMs': policy.connectTimeoutMs,
      'backoffMs': List<int>.of(policy.backoffMs),
      'failedCooldownSeconds': policy.failedCooldownSeconds,
      'bufferingThresholdMs': policy.bufferingThresholdMs,
    };
  }

  // MARK: - Field readers

  static Map<String, Object?> _object(Object? decoded, String field) {
    if (decoded is! Map) {
      throw FormatException('live catalog $field must be a JSON object');
    }
    return decoded.cast<String, Object?>();
  }

  static List<Object?> _array(Object? value, String field) {
    if (value is! List) {
      throw FormatException('live catalog $field must be a list');
    }
    return value;
  }

  static Map<String, String> _stringMap(Object? value, String field) {
    final Map<String, Object?> json = _object(value, field);
    final Map<String, String> result = <String, String>{};
    for (final MapEntry<String, Object?> entry in json.entries) {
      result[entry.key] = _string(entry.value, '$field.${entry.key}');
    }
    return result;
  }

  static String _string(Object? value, String field) {
    if (value is! String) {
      throw FormatException('live catalog $field must be a string');
    }
    return value;
  }

  static String? _optString(Object? value, String field) {
    return value == null ? null : _string(value, field);
  }

  static int _int(Object? value, String field) {
    if (value is! int) {
      throw FormatException('live catalog $field must be an integer');
    }
    return value;
  }

  static int _optInt(Object? value, String field, int fallback) {
    return value == null ? fallback : _int(value, field);
  }

  static int? _nullableInt(Object? value, String field) {
    return value == null ? null : _int(value, field);
  }

  static bool _bool(Object? value, String field) {
    if (value is! bool) {
      throw FormatException('live catalog $field must be a boolean');
    }
    return value;
  }

  static bool _optBool(Object? value, String field, bool fallback) {
    return value == null ? fallback : _bool(value, field);
  }

  static List<String> _stringList(Object? value, String field) {
    if (value is! List) {
      throw FormatException('live catalog $field must be a list of strings');
    }
    return value.map((Object? item) => _string(item, field)).toList(growable: false);
  }

  static List<String> _optStringList(Object? value, String field) {
    return value == null ? const <String>[] : _stringList(value, field);
  }

  static List<int> _intList(Object? value, String field) {
    if (value is! List) {
      throw FormatException('live catalog $field must be a list of integers');
    }
    return value.map((Object? item) => _int(item, field)).toList(growable: false);
  }

  static List<int> _optIntList(Object? value, String field, List<int> fallback) {
    return value == null ? fallback : _intList(value, field);
  }

  static DateTime _date(Object? value, String field) {
    final String text = _string(value, field);
    try {
      return DateTime.parse(text);
    } on FormatException {
      throw FormatException('live catalog $field is not an RFC 3339 timestamp: $text');
    }
  }

  static DateTime? _optDate(Object? value, String field) {
    return value == null ? null : _date(value, field);
  }

  static T _enum<T extends Enum>(Object? value, List<T> values, String field) {
    final String name = _string(value, field);
    for (final T candidate in values) {
      if (candidate.name == name) return candidate;
    }
    throw FormatException('live catalog $field is not a known value: $name');
  }

  static T _optEnum<T extends Enum>(
    Object? value,
    List<T> values,
    String field,
    T fallback,
  ) {
    return value == null ? fallback : _enum<T>(value, values, field);
  }

  static String _capability(Object? value, String field) {
    final String label = _string(value, field);
    if (!rendererSupportValues.contains(label)) {
      throw FormatException('live catalog $field is not a RendererSupport value: $label');
    }
    return label;
  }

  static String _optCapability(Object? value, String field) {
    return value == null ? 'Not Yet Verified' : _capability(value, field);
  }

  // MARK: - Field writers

  static String _dateText(DateTime value) => value.toUtc().toIso8601String();

  static String? _optDateText(DateTime? value) =>
      value?.toUtc().toIso8601String();
}
