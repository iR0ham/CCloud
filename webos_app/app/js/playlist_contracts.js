/* Schema-v1 live catalog records, codec and additive migration (webOS).
 *
 * This is the JavaScript half of a three-port contract. The Dart original lives in
 * `flutter_app/lib/core/live_catalog_codec.dart` + `live_contracts.dart`, the Swift
 * port in `Sources/Core/LiveTVContracts.swift` + `LiveTVCatalogCodec.swift`, and the
 * frozen document both must read is
 * `Tests/fixtures/migration/catalog-v1.json`. Field names, JSON keys and the accepted
 * enum labels are therefore not free choices: a rename on one port is a persistence
 * break on the other two. Key insertion order below mirrors the Dart writers on
 * purpose, so a later cross-language agreement test may compare encoded text as well
 * as parsed values (the Swift port declares `ChannelMember.ordinal` last, which is
 * legal but means value comparison is the reliable form of agreement).
 *
 * Written in plain ES2017 (`var`, function expressions, no arrow functions, template
 * literals, `let`/`const`, optional chaining or nullish coalescing), because the
 * runtime is webOS 4 / Chromium 68 — see `webos_app/app/js/util.js:1`, whose
 * `new Date().toISOString()` at `store.js:70` is exactly the canonical timestamp form
 * this codec pins. `Tests/webos/live_contracts.test.js` enforces that ceiling by
 * scanning this file's text, because `node --check` accepts newer syntax happily.
 *
 * This module never touches `localStorage`: loading and saving the catalog belongs to
 * task B4-J, and a contract layer that reaches for storage cannot be tested without a
 * device. Nothing here is read by the current screens yet either, so shipping it
 * cannot change today's behaviour.
 *
 * Rules, in the order they are applied (identical to the Dart codec):
 *
 * * `schemaVersion` is prefighted before a single record is decoded. A missing,
 *   non-integer or boolean value is malformed data; a valid integer this build does not
 *   know is a version problem reported as exactly `Unsupported live catalog schema`,
 *   the message the Dart codec throws, so one string matches across ports. Encoding
 *   refuses every other version for the same reason: no port may write a document its
 *   own reader rejects.
 * * timestamps are stored as text, and only two forms are accepted — the canonical RFC
 *   3339 UTC form with three fractional digits (`2026-01-01T00:00:00.000Z`, what
 *   `toISOString()` and Dart `toIso8601String()` write) and the seconds-precision form
 *   the frozen fixture uses (`2026-01-01T00:00:00Z`). Both normalize to the canonical
 *   form, on read and again on write. The other two ports get that guarantee from a
 *   real `Date`/`DateTime` type; this port has only strings, so it checks explicitly.
 * * v1 is additive: an absent or null `recentWatches` decodes as an empty array, an
 *   absent `sourcePolicy` as the standard policy, an absent source `rendererCapability`
 *   as `Not Yet Verified`, while every write includes all three. A value that is
 *   present is never replaced, whatever it holds: silently defaulting a mistyped field
 *   would rewrite user intent into a capability no renderer verified.
 * * a source keeps either an address or a secret reference. `streamUrl` decodes as
 *   empty only when `streamSecretRef` exists, and encoding omits the `streamUrl` key
 *   entirely in that case, so a signed address never reaches device storage.
 * * malformed JSON, a wrong field type and an unknown enum label all throw. Nothing
 *   here returns a silently cleared state, because an accidental empty write would
 *   destroy the user's playlists, associations and preferences on the next save.
 */
window.CC = window.CC || {};

(function () {
  var CC = window.CC;

  var SUPPORTED_SCHEMA_VERSION = 1;
  var UNSUPPORTED_SCHEMA_MESSAGE = 'Unsupported live catalog schema';

  var RENDERER_SUPPORT_VALUES = [
    'Supported',
    'Partially Supported',
    'Unsupported',
    'Not Yet Verified'
  ];
  var CAPABILITY_NOT_YET_VERIFIED = 'Not Yet Verified';
  var PLAYLIST_SOURCE_TYPES = ['builtIn', 'remoteUrl', 'localFile'];
  var PLAYLIST_REFRESH_STATUSES = ['idle', 'refreshing', 'ready', 'error'];
  var SOURCE_HEALTH_VALUES = ['unverified', 'available', 'failed', 'disabled'];
  var SOURCE_ORIGIN_VALUES = ['playlist', 'user'];

  // Canonical form, plus the one legacy form that must still load. Deliberately an
  // explicit shape rather than `new Date(text)`, which also accepts "2026-01-01",
  // "2026-01-01 00:00:00" and "01/02/2026" — spellings no writer in this contract produces —
  // alongside vendor forms the three ports would disagree on. Dart's `DateTime.parse` covers
  // some of the same ground (it takes a date-only value and reads a zone-less timestamp as
  // local time), so a shared parser cannot express the rule; each port states it.
  //
  // Day count per month, index 0 = January. February is widened by `isLeapYear` at the
  // call site rather than stored as two arrays, so the leap rule is stated once.
  var DAYS_IN_MONTH = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

  function isLeapYear(year) {
    return year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
  }

  var TIMESTAMP_PATTERN =
    /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{3})?(Z|[+-]\d{2}:\d{2})$/;

  function fail(message) {
    throw new Error('live catalog ' + message);
  }

  function isPresent(value) {
    return value !== undefined && value !== null;
  }

  function isInteger(value) {
    return typeof value === 'number' && isFinite(value) && Math.floor(value) === value;
  }

  function isPlainObject(value) {
    return value !== null && typeof value === 'object' && !Array.isArray(value);
  }

  function requireObject(value, field) {
    if (!isPlainObject(value)) fail(field + ' must be a JSON object');
    return value;
  }

  function requireArray(value, field) {
    if (!Array.isArray(value)) fail(field + ' must be a list');
    return value;
  }

  function requireString(value, field) {
    if (typeof value !== 'string') fail(field + ' must be a string');
    return value;
  }

  function optionalString(value, field) {
    return isPresent(value) ? requireString(value, field) : null;
  }

  function requireInteger(value, field) {
    if (!isInteger(value)) fail(field + ' must be an integer');
    return value;
  }

  function optionalInteger(value, field, fallback) {
    return isPresent(value) ? requireInteger(value, field) : fallback;
  }

  function nullableInteger(value, field) {
    return isPresent(value) ? requireInteger(value, field) : null;
  }

  function requireBoolean(value, field) {
    if (typeof value !== 'boolean') fail(field + ' must be a boolean');
    return value;
  }

  function optionalBoolean(value, field, fallback) {
    return isPresent(value) ? requireBoolean(value, field) : fallback;
  }

  function requireStringList(value, field) {
    if (!Array.isArray(value)) fail(field + ' must be a list of strings');
    var out = [];
    for (var i = 0; i < value.length; i += 1) {
      out.push(requireString(value[i], field));
    }
    return out;
  }

  function optionalStringList(value, field) {
    return isPresent(value) ? requireStringList(value, field) : [];
  }

  function requireIntegerList(value, field) {
    if (!Array.isArray(value)) fail(field + ' must be a list of integers');
    var out = [];
    for (var i = 0; i < value.length; i += 1) {
      out.push(requireInteger(value[i], field));
    }
    return out;
  }

  function requireEnum(value, values, field) {
    var name = requireString(value, field);
    if (values.indexOf(name) === -1) fail(field + ' is not a known value: ' + name);
    return name;
  }

  function optionalEnum(value, values, field, fallback) {
    return isPresent(value) ? requireEnum(value, values, field) : fallback;
  }

  function requireCapability(value, field) {
    var label = requireString(value, field);
    if (RENDERER_SUPPORT_VALUES.indexOf(label) === -1) {
      fail(field + ' is not a RendererSupport value: ' + label);
    }
    return label;
  }

  function optionalCapability(value, field) {
    return isPresent(value) ? requireCapability(value, field) : CAPABILITY_NOT_YET_VERIFIED;
  }

  function requireTimestamp(value, field) {
    var text = requireString(value, field);
    if (!TIMESTAMP_PATTERN.test(text)) {
      fail(field + ' is not an RFC 3339 timestamp: ' + text);
    }
    // The pattern fixes the shape; the bounds below are what make the shape mean a real
    // instant. `new Date` is deliberately not trusted for this, because it answers
    // out-of-range components by rolling them forward — "2026-02-31T00:00:00Z" becomes
    // 3 March — and a rolled-over timestamp silently moves a date the user wrote. The rule
    // is therefore stated by this port instead of inherited from whichever date parser the
    // device happens to ship.
    //
    // The sibling ports do not currently reach the same verdict by default. Dart's
    // `DateTime.parse` documents that it "accepts out-of-range component values and
    // interprets them as overflows into the next larger component" (`2020-01-42` becoming
    // `2020-02-11`), which is the same rollover `new Date` performs, and the same page names
    // `DateFormat.parseStrict` from `package:intl` as the way to reject them — a dependency
    // this catalog codec deliberately does not carry. So this port states the rule, the Swift
    // codec carries the equivalent component check (see `LiveCatalogDate.date(from:)`,
    // `Sources/Core/LiveTVCatalogCodec.swift`), and closing the Dart half is recorded as task
    // B3 cross-port agreement work rather than silently assumed here.
    var hour = parseInt(text.slice(11, 13), 10);
    var minute = parseInt(text.slice(14, 16), 10);
    var second = parseInt(text.slice(17, 19), 10);
    if (hour > 23 || minute > 59 || second > 59) {
      fail(field + ' is not an RFC 3339 timestamp: ' + text);
    }
    var year = parseInt(text.slice(0, 4), 10);
    var month = parseInt(text.slice(5, 7), 10);
    var day = parseInt(text.slice(8, 10), 10);
    if (month < 1 || month > 12) {
      fail(field + ' is not a real calendar instant: ' + text);
    }
    var daysInMonth = month === 2 && isLeapYear(year) ? 29 : DAYS_IN_MONTH[month - 1];
    if (day < 1 || day > daysInMonth) {
      fail(field + ' is not a real calendar instant: ' + text);
    }
    var date = new Date(text);
    if (isNaN(date.getTime())) fail(field + ' is not a real calendar instant: ' + text);
    return date.toISOString();
  }

  function optionalTimestamp(value, field) {
    return isPresent(value) ? requireTimestamp(value, field) : null;
  }

  function requireStringMap(value, field) {
    var json = requireObject(value, field);
    var keys = Object.keys(json);
    var out = {};
    for (var i = 0; i < keys.length; i += 1) {
      out[keys[i]] = requireString(json[keys[i]], field + '.' + keys[i]);
    }
    return out;
  }

  // ---- canonical defaults ----------------------------------------------------

  function standardSourcePolicy() {
    // A fresh object every call: a shared literal would let one caller's tuning
    // rewrite the default that every other channel inherits.
    return {
      maxAutomaticAttempts: 3,
      sameSourceRetries: 2,
      connectTimeoutMs: 15000,
      backoffMs: [500, 1500, 4000],
      failedCooldownSeconds: 600,
      bufferingThresholdMs: 30000
    };
  }

  function emptyState() {
    return {
      schemaVersion: SUPPORTED_SCHEMA_VERSION,
      playlists: [],
      members: [],
      sources: [],
      associations: [],
      preferences: [],
      recentWatches: [],
      logicalIdByMemberId: {}
    };
  }

  // ---- record readers -------------------------------------------------------

  function readPlaylist(value) {
    var json = requireObject(value, 'playlist');
    return {
      playlistId: requireString(json.playlistId, 'playlist.playlistId'),
      name: requireString(json.name, 'playlist.name'),
      sourceType: requireEnum(json.sourceType, PLAYLIST_SOURCE_TYPES, 'playlist.sourceType'),
      locationRef: requireString(json.locationRef, 'playlist.locationRef'),
      enabled: requireBoolean(json.enabled, 'playlist.enabled'),
      createdAt: requireTimestamp(json.createdAt, 'playlist.createdAt'),
      lastUpdatedAt: optionalTimestamp(json.lastUpdatedAt, 'playlist.lastUpdatedAt'),
      lastSuccessfulRefresh: optionalTimestamp(
        json.lastSuccessfulRefresh,
        'playlist.lastSuccessfulRefresh'
      ),
      refreshStatus: optionalEnum(
        json.refreshStatus,
        PLAYLIST_REFRESH_STATUSES,
        'playlist.refreshStatus',
        'idle'
      ),
      lastErrorCode: optionalString(json.lastErrorCode, 'playlist.lastErrorCode'),
      channelCount: optionalInteger(json.channelCount, 'playlist.channelCount', 0),
      parsingVersion: optionalInteger(json.parsingVersion, 'playlist.parsingVersion', 1)
    };
  }

  function readMember(value) {
    var json = requireObject(value, 'member');
    return {
      memberId: requireString(json.memberId, 'member.memberId'),
      playlistId: requireString(json.playlistId, 'member.playlistId'),
      providerNamespace: requireString(json.providerNamespace, 'member.providerNamespace'),
      providerChannelId: requireString(json.providerChannelId, 'member.providerChannelId'),
      displayName: requireString(json.displayName, 'member.displayName'),
      normalizedName: requireString(json.normalizedName, 'member.normalizedName'),
      ordinal: requireInteger(json.ordinal, 'member.ordinal'),
      logoUrl: optionalString(json.logoUrl, 'member.logoUrl'),
      group: optionalString(json.group, 'member.group'),
      countryCode: optionalString(json.countryCode, 'member.countryCode'),
      languages: optionalStringList(json.languages, 'member.languages'),
      tvgId: optionalString(json.tvgId, 'member.tvgId')
    };
  }

  function readSource(value) {
    var json = requireObject(value, 'source');
    var secretRef = optionalString(json.streamSecretRef, 'source.streamSecretRef');
    var streamUrl;
    if (!isPresent(json.streamUrl)) {
      if (secretRef === null) {
        throw new Error(
          'live catalog source.streamUrl is required unless the address is held in ' +
            'a streamSecretRef'
        );
      }
      // The address lives in a secret store; the document carries only the
      // reference, so an empty string here is honest rather than a default.
      streamUrl = '';
    } else {
      streamUrl = requireString(json.streamUrl, 'source.streamUrl');
    }
    return {
      sourceId: requireString(json.sourceId, 'source.sourceId'),
      channelId: requireString(json.channelId, 'source.channelId'),
      memberId: requireString(json.memberId, 'source.memberId'),
      playlistId: requireString(json.playlistId, 'source.playlistId'),
      providerNamespace: requireString(json.providerNamespace, 'source.providerNamespace'),
      label: requireString(json.label, 'source.label'),
      streamUrl: streamUrl,
      streamSecretRef: secretRef,
      protocolHint: requireString(json.protocolHint, 'source.protocolHint'),
      rendererCapability: optionalCapability(
        json.rendererCapability,
        'source.rendererCapability'
      ),
      origin: requireEnum(json.origin, SOURCE_ORIGIN_VALUES, 'source.origin'),
      priority: requireInteger(json.priority, 'source.priority'),
      enabled: requireBoolean(json.enabled, 'source.enabled'),
      health: requireEnum(json.health, SOURCE_HEALTH_VALUES, 'source.health'),
      lastSuccessfulPlaybackAt: optionalTimestamp(
        json.lastSuccessfulPlaybackAt,
        'source.lastSuccessfulPlaybackAt'
      ),
      lastFailedPlaybackAt: optionalTimestamp(
        json.lastFailedPlaybackAt,
        'source.lastFailedPlaybackAt'
      ),
      lastErrorCode: optionalString(json.lastErrorCode, 'source.lastErrorCode')
    };
  }

  function readAssociation(value) {
    var json = requireObject(value, 'association');
    return { memberIds: requireStringList(json.memberIds, 'association.memberIds') };
  }

  function readPolicy(value, field) {
    var json = requireObject(value, field);
    return {
      maxAutomaticAttempts: optionalInteger(
        json.maxAutomaticAttempts,
        field + '.maxAutomaticAttempts',
        3
      ),
      sameSourceRetries: optionalInteger(json.sameSourceRetries, field + '.sameSourceRetries', 2),
      connectTimeoutMs: optionalInteger(
        json.connectTimeoutMs,
        field + '.connectTimeoutMs',
        15000
      ),
      backoffMs: requireIntegerList(json.backoffMs, field + '.backoffMs'),
      failedCooldownSeconds: optionalInteger(
        json.failedCooldownSeconds,
        field + '.failedCooldownSeconds',
        600
      ),
      bufferingThresholdMs: optionalInteger(
        json.bufferingThresholdMs,
        field + '.bufferingThresholdMs',
        30000
      )
    };
  }

  function readPreference(value) {
    var json = requireObject(value, 'preference');
    return {
      channelId: requireString(json.channelId, 'preference.channelId'),
      favorite: optionalBoolean(json.favorite, 'preference.favorite', false),
      hidden: optionalBoolean(json.hidden, 'preference.hidden', false),
      category: optionalString(json.category, 'preference.category'),
      userOrder: nullableInteger(json.userOrder, 'preference.userOrder'),
      automaticFailoverEnabled: optionalBoolean(
        json.automaticFailoverEnabled,
        'preference.automaticFailoverEnabled',
        true
      ),
      // Additive: a preference written before source policies existed receives the
      // standard policy rather than failing.
      sourcePolicy: isPresent(json.sourcePolicy)
        ? readPolicy(json.sourcePolicy, 'preference.sourcePolicy')
        : standardSourcePolicy(),
      lastSuccessfulSourceId: optionalString(
        json.lastSuccessfulSourceId,
        'preference.lastSuccessfulSourceId'
      )
    };
  }

  function readWatch(value) {
    var json = requireObject(value, 'recentWatch');
    return {
      channelId: requireString(json.channelId, 'recentWatch.channelId'),
      watchedAt: requireTimestamp(json.watchedAt, 'recentWatch.watchedAt')
    };
  }

  // ---- record writers -------------------------------------------------------

  function writePlaylist(record) {
    var json = requireObject(record, 'playlist');
    return {
      playlistId: requireString(json.playlistId, 'playlist.playlistId'),
      name: requireString(json.name, 'playlist.name'),
      sourceType: requireEnum(json.sourceType, PLAYLIST_SOURCE_TYPES, 'playlist.sourceType'),
      locationRef: requireString(json.locationRef, 'playlist.locationRef'),
      enabled: requireBoolean(json.enabled, 'playlist.enabled'),
      createdAt: requireTimestamp(json.createdAt, 'playlist.createdAt'),
      lastUpdatedAt: optionalTimestamp(json.lastUpdatedAt, 'playlist.lastUpdatedAt'),
      lastSuccessfulRefresh: optionalTimestamp(
        json.lastSuccessfulRefresh,
        'playlist.lastSuccessfulRefresh'
      ),
      refreshStatus: requireEnum(
        json.refreshStatus,
        PLAYLIST_REFRESH_STATUSES,
        'playlist.refreshStatus'
      ),
      lastErrorCode: optionalString(json.lastErrorCode, 'playlist.lastErrorCode'),
      channelCount: requireInteger(json.channelCount, 'playlist.channelCount'),
      parsingVersion: requireInteger(json.parsingVersion, 'playlist.parsingVersion')
    };
  }

  function writeMember(record) {
    var json = requireObject(record, 'member');
    return {
      memberId: requireString(json.memberId, 'member.memberId'),
      playlistId: requireString(json.playlistId, 'member.playlistId'),
      providerNamespace: requireString(json.providerNamespace, 'member.providerNamespace'),
      providerChannelId: requireString(json.providerChannelId, 'member.providerChannelId'),
      displayName: requireString(json.displayName, 'member.displayName'),
      normalizedName: requireString(json.normalizedName, 'member.normalizedName'),
      ordinal: requireInteger(json.ordinal, 'member.ordinal'),
      logoUrl: optionalString(json.logoUrl, 'member.logoUrl'),
      group: optionalString(json.group, 'member.group'),
      countryCode: optionalString(json.countryCode, 'member.countryCode'),
      languages: requireStringList(json.languages, 'member.languages'),
      tvgId: optionalString(json.tvgId, 'member.tvgId')
    };
  }

  function writeSource(record) {
    var json = requireObject(record, 'source');
    var secretRef = optionalString(json.streamSecretRef, 'source.streamSecretRef');
    var out = {
      sourceId: requireString(json.sourceId, 'source.sourceId'),
      channelId: requireString(json.channelId, 'source.channelId'),
      memberId: requireString(json.memberId, 'source.memberId'),
      playlistId: requireString(json.playlistId, 'source.playlistId'),
      providerNamespace: requireString(json.providerNamespace, 'source.providerNamespace'),
      label: requireString(json.label, 'source.label')
    };
    // The omission rule: a secret-backed source persists only the reference, never
    // the address it points at, so a signed URL cannot reach a preferences file.
    if (secretRef === null) {
      out.streamUrl = requireString(json.streamUrl, 'source.streamUrl');
    }
    out.streamSecretRef = secretRef;
    out.protocolHint = requireString(json.protocolHint, 'source.protocolHint');
    out.rendererCapability = requireCapability(
      json.rendererCapability,
      'source.rendererCapability'
    );
    out.origin = requireEnum(json.origin, SOURCE_ORIGIN_VALUES, 'source.origin');
    out.priority = requireInteger(json.priority, 'source.priority');
    out.enabled = requireBoolean(json.enabled, 'source.enabled');
    out.health = requireEnum(json.health, SOURCE_HEALTH_VALUES, 'source.health');
    out.lastSuccessfulPlaybackAt = optionalTimestamp(
      json.lastSuccessfulPlaybackAt,
      'source.lastSuccessfulPlaybackAt'
    );
    out.lastFailedPlaybackAt = optionalTimestamp(
      json.lastFailedPlaybackAt,
      'source.lastFailedPlaybackAt'
    );
    out.lastErrorCode = optionalString(json.lastErrorCode, 'source.lastErrorCode');
    return out;
  }

  function writeAssociation(record) {
    var json = requireObject(record, 'association');
    return { memberIds: requireStringList(json.memberIds, 'association.memberIds') };
  }

  function writePreference(record) {
    var json = requireObject(record, 'preference');
    return {
      channelId: requireString(json.channelId, 'preference.channelId'),
      favorite: requireBoolean(json.favorite, 'preference.favorite'),
      hidden: requireBoolean(json.hidden, 'preference.hidden'),
      category: optionalString(json.category, 'preference.category'),
      userOrder: nullableInteger(json.userOrder, 'preference.userOrder'),
      automaticFailoverEnabled: requireBoolean(
        json.automaticFailoverEnabled,
        'preference.automaticFailoverEnabled'
      ),
      sourcePolicy: writePolicy(json.sourcePolicy, 'preference.sourcePolicy'),
      lastSuccessfulSourceId: optionalString(
        json.lastSuccessfulSourceId,
        'preference.lastSuccessfulSourceId'
      )
    };
  }

  function writePolicy(record, field) {
    var json = requireObject(record, field);
    return {
      maxAutomaticAttempts: requireInteger(
        json.maxAutomaticAttempts,
        field + '.maxAutomaticAttempts'
      ),
      sameSourceRetries: requireInteger(json.sameSourceRetries, field + '.sameSourceRetries'),
      connectTimeoutMs: requireInteger(json.connectTimeoutMs, field + '.connectTimeoutMs'),
      backoffMs: requireIntegerList(json.backoffMs, field + '.backoffMs'),
      failedCooldownSeconds: requireInteger(
        json.failedCooldownSeconds,
        field + '.failedCooldownSeconds'
      ),
      bufferingThresholdMs: requireInteger(
        json.bufferingThresholdMs,
        field + '.bufferingThresholdMs'
      )
    };
  }

  function writeWatch(record) {
    var json = requireObject(record, 'recentWatch');
    return {
      channelId: requireString(json.channelId, 'recentWatch.channelId'),
      watchedAt: requireTimestamp(json.watchedAt, 'recentWatch.watchedAt')
    };
  }

  function mapList(list, field, reader) {
    var values = requireArray(list, field);
    var out = [];
    for (var i = 0; i < values.length; i += 1) {
      out.push(reader(values[i]));
    }
    return out;
  }

  // ---- document level -------------------------------------------------------

  function preflightReadVersion(value) {
    // A boolean is rejected here rather than by `isInteger` alone because
    // `Number(true) === 1` would otherwise read a corrupt document as supported.
    // Only the read path makes that distinction: on the other two ports the field is
    // typed an integer by the compiler, so their write path can only ever see an integer
    // and rejects every value that is not the supported one.
    if (!isInteger(value)) fail('schemaVersion must be an integer');
    if (value !== SUPPORTED_SCHEMA_VERSION) throw new Error(UNSUPPORTED_SCHEMA_MESSAGE);
    return value;
  }

  function preflightWriteVersion(value) {
    // Symmetric with the reader for the case that matters: a port must never emit a
    // document its own reader would reject.
    if (value !== SUPPORTED_SCHEMA_VERSION) throw new Error(UNSUPPORTED_SCHEMA_MESSAGE);
    return value;
  }

  function decodeState(raw) {
    if (typeof raw !== 'string') fail('state must be JSON text');
    // No try/catch: malformed text throwing here is the fail-closed behaviour, and a
    // caught parse error would be indistinguishable from an empty catalog.
    var json = JSON.parse(raw);
    requireObject(json, 'state');
    preflightReadVersion(json.schemaVersion);
    return {
      schemaVersion: SUPPORTED_SCHEMA_VERSION,
      playlists: mapList(json.playlists, 'playlists', readPlaylist),
      members: mapList(json.members, 'members', readMember),
      sources: mapList(json.sources, 'sources', readSource),
      associations: mapList(json.associations, 'associations', readAssociation),
      preferences: mapList(json.preferences, 'preferences', readPreference),
      // Additive: a v1 document written before recent watches existed decodes as an
      // empty history instead of failing.
      recentWatches: isPresent(json.recentWatches)
        ? mapList(json.recentWatches, 'recentWatches', readWatch)
        : [],
      logicalIdByMemberId: requireStringMap(
        json.logicalIdByMemberId,
        'logicalIdByMemberId'
      )
    };
  }

  function encodeState(state) {
    var json = requireObject(state, 'state');
    preflightWriteVersion(json.schemaVersion);
    return JSON.stringify({
      schemaVersion: SUPPORTED_SCHEMA_VERSION,
      playlists: mapList(json.playlists, 'playlists', writePlaylist),
      members: mapList(json.members, 'members', writeMember),
      sources: mapList(json.sources, 'sources', writeSource),
      associations: mapList(json.associations, 'associations', writeAssociation),
      preferences: mapList(json.preferences, 'preferences', writePreference),
      recentWatches: mapList(json.recentWatches, 'recentWatches', writeWatch),
      logicalIdByMemberId: requireStringMap(
        json.logicalIdByMemberId,
        'logicalIdByMemberId'
      )
    });
  }

  function migrate(raw) {
    // Absent or empty stored data is the canonical empty v1 state; anything else is
    // decoded, and a document that cannot be understood throws instead of returning a
    // cleared catalog.
    if (raw === null || raw === undefined || raw === '') return emptyState();
    return decodeState(raw);
  }

  // ---- runtime-only and output types ---------------------------------------

  function liveContext(playlistId, logicalChannelId, sourceIds, automaticFailoverEnabled, sourcePolicy) {
    return {
      playlistId: requireString(playlistId, 'context.playlistId'),
      logicalChannelId: requireString(logicalChannelId, 'context.logicalChannelId'),
      // Copied: candidate order *is* the failover specification, so a caller that
      // mutated its own array afterwards must not be able to reorder a running attempt.
      sourceIds: requireStringList(sourceIds, 'context.sourceIds').slice(),
      automaticFailoverEnabled: requireBoolean(
        automaticFailoverEnabled,
        'context.automaticFailoverEnabled'
      ),
      sourcePolicy: writePolicy(sourcePolicy, 'context.sourcePolicy')
    };
  }

  function attemptContext(
    requestGeneration,
    playlistId,
    logicalChannelId,
    sourceId,
    attemptNumber,
    stableMediaIdentity
  ) {
    // Runtime-only identity used to discard callbacks from a superseded player
    // session. It is never encoded: an attempt must not outlive its process, and a
    // stale attempt must never be able to rewrite catalog state.
    return {
      requestGeneration: requireString(requestGeneration, 'attempt.requestGeneration'),
      playlistId: requireString(playlistId, 'attempt.playlistId'),
      logicalChannelId: requireString(logicalChannelId, 'attempt.logicalChannelId'),
      sourceId: requireString(sourceId, 'attempt.sourceId'),
      attemptNumber: requireInteger(attemptNumber, 'attempt.attemptNumber'),
      stableMediaIdentity: requireString(stableMediaIdentity, 'attempt.stableMediaIdentity')
    };
  }

  function issue(code, message, line) {
    return {
      code: requireString(code, 'issue.code'),
      message: requireString(message, 'issue.message'),
      line: line === undefined ? null : requireInteger(line, 'issue.line')
    };
  }

  function writeChannel(value) {
    // A snapshot is the only place a `LogicalChannel` is ever serialized, and its
    // `sources` are the field a secret address could leak from, so the channel's
    // sources go through the same writer the persisted catalog uses instead of being
    // copied through unchecked.
    var json = requireObject(value, 'snapshot.channel');
    return {
      channelId: requireString(json.channelId, 'channel.channelId'),
      displayName: requireString(json.displayName, 'channel.displayName'),
      normalizedName: requireString(json.normalizedName, 'channel.normalizedName'),
      logoUrl: optionalString(json.logoUrl, 'channel.logoUrl'),
      category: optionalString(json.category, 'channel.category'),
      countryCode: optionalString(json.countryCode, 'channel.countryCode'),
      languages: requireStringList(json.languages, 'channel.languages'),
      memberIds: requireStringList(json.memberIds, 'channel.memberIds'),
      sources: mapList(json.sources, 'channel.sources', writeSource),
      favorite: requireBoolean(json.favorite, 'channel.favorite'),
      hidden: requireBoolean(json.hidden, 'channel.hidden'),
      userOrder: nullableInteger(json.userOrder, 'channel.userOrder'),
      automaticFailoverEnabled: requireBoolean(
        json.automaticFailoverEnabled,
        'channel.automaticFailoverEnabled'
      ),
      sourcePolicy: writePolicy(json.sourcePolicy, 'channel.sourcePolicy'),
      lastSuccessfulSourceId: optionalString(
        json.lastSuccessfulSourceId,
        'channel.lastSuccessfulSourceId'
      )
    };
  }

  function snapshot(revision, generatedAt, playlists, channels, issues) {
    return {
      revision: requireInteger(revision, 'snapshot.revision'),
      generatedAt: requireTimestamp(generatedAt, 'snapshot.generatedAt'),
      playlists: mapList(playlists, 'snapshot.playlists', writePlaylist),
      channels: mapList(channels, 'snapshot.channels', writeChannel),
      issues: mapList(issues, 'snapshot.issues', function (value) {
        var json = requireObject(value, 'snapshot.issue');
        return issue(json.code, json.message, json.line);
      })
    };
  }

  CC.playlistContracts = {
    supportedSchemaVersion: SUPPORTED_SCHEMA_VERSION,
    rendererSupportValues: RENDERER_SUPPORT_VALUES.slice(),
    emptyState: emptyState,
    standardSourcePolicy: standardSourcePolicy,
    decodeState: decodeState,
    encodeState: encodeState,
    migrate: migrate,
    liveContext: liveContext,
    attemptContext: attemptContext,
    issue: issue,
    snapshot: snapshot
  };
})();
