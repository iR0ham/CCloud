/* Logical channel identity (webOS).
 *
 * This is the JavaScript half of a three-port contract. The Dart original lives in
 * `flutter_app/lib/core/channel_identity.dart`, the Swift port in `Sources/Core/LiveTVChannelIdentity.swift`,
 * and `Tests/live-foundation/main.swift` plus `flutter_app/test/channel_identity_test.dart` pin the same
 * verdicts this suite repeats. The scoring table, the ambiguity floor and the five error codes are therefore
 * wire-visible behaviour: a user who merges two rows on the Mac must see one channel on a phone and one
 * channel on a TV, and a refusal must carry the same code on every platform.
 *
 * The load-bearing invariant is that similarity never decides anything. `findCandidate` is a suggestion for a
 * screen; a logical ID only moves when a user asks through `associate`, because the whole point of Multi-Source
 * is that two playlists disagreeing about a station is a fact about the playlists rather than a bug to hide.
 *
 * Written in plain ES2017 (`var`, function expressions, string concatenation, explicit index loops) because the
 * runtime is webOS 4 / Chromium 68, and `Tests/webos/channel_identity.test.js` enforces that ceiling by
 * scanning this file's text. `node --check`, which is all CI runs, accepts newer syntax happily. See
 * `webos_app/app/js/playlist_contracts.js:14` for the same rule.
 *
 * JavaScript has no value types, so purity is a written discipline rather than a language guarantee: every
 * function here returns fresh arrays and a fresh `logicalIdByMemberId` map, and the only rows that are
 * replaced rather than shared are the sources whose `channelId` moves. That is what lets a refused request
 * leave nothing behind and what makes `separate` able to undo `associate`. Rows that are carried over are
 * carried by reference on purpose, exactly as Dart's unmodifiable views do: a channel's identity fields are
 * never edited in place by any port.
 */
window.CC = window.CC || {};

(function () {
  var CC = window.CC;

  // Candidates at or above this score are the only ones a screen may offer without a warning. The number is
  // the same on all three ports, so a pair that needs confirmation on Android needs confirmation on a TV.
  var AMBIGUITY_FLOOR = 85;

  function text(value) {
    return typeof value === 'string' ? value : '';
  }

  // `hasOwnProperty` is fetched from the prototype rather than called on the map: `logicalIdByMemberId` is
  // decoded from JSON, and a document whose member ID is literally `hasOwnProperty` would otherwise shadow
  // the method. This is the same hazard `playlist_contracts.js` avoids with `Object.create(null)`.
  function hasOwn(map, key) {
    return Object.prototype.hasOwnProperty.call(map, key);
  }

  // Trailing whitespace and a lowercase ISO code are storage noise, not a different country. An absent or
  // blank value is *unknown*, which matters twice: it cannot match, and it cannot conflict.
  function comparableCountry(value) {
    var trimmed = text(value).trim().toUpperCase();
    return trimmed === '' ? null : trimmed;
  }

  // Logos are compared as given (trimmed) and never canonicalized: `irib1.png` and `/logos/irib1.png` are two
  // different statements about provenance, and guessing between them would invent evidence.
  function comparableLogo(value) {
    var trimmed = text(value).trim();
    return trimmed === '' ? null : trimmed;
  }

  function stated(value) {
    return text(value).trim() !== '';
  }

  function candidate(left, right, score, evidence, providerConflict, countryConflict) {
    return {
      leftMemberId: left.memberId,
      rightMemberId: right.memberId,
      score: score,
      evidence: evidence,
      ambiguous: score < AMBIGUITY_FLOOR || providerConflict || countryConflict
    };
  }

  // Provider IDs are only comparable inside one namespace: `famelack/IRIB1` and `iptv-org/IRIB1` are two
  // unrelated strings, so a cross-namespace pair falls through to the name tiers instead of scoring 90+. Two
  // IDs that disagree *within* a namespace is a contradiction, which is why it makes even an 85 ambiguous.
  //
  // Names are compared as stored `normalizedName` values and nothing else. Stripping a display-name token such
  // as `(720p)` is `playlist_parser.js`'s `displayName()` job, applied when the row is read; this layer adds no
  // folding of its own, so the same pair either matches on every port or on none. That shared gap is recorded
  // in `EXECUTION_LOG.md` and owned by task B4.
  function findCandidate(left, right) {
    if (left.memberId === right.memberId) return null;

    var leftName = text(left.normalizedName);
    var namesMatch = leftName !== '' && leftName === text(right.normalizedName);
    var leftCountry = comparableCountry(left.countryCode);
    var rightCountry = comparableCountry(right.countryCode);
    var bothCountry = leftCountry !== null && rightCountry !== null;
    var countryMatch = bothCountry && leftCountry === rightCountry;
    var countryConflict = bothCountry && leftCountry !== rightCountry;
    var leftLogo = comparableLogo(left.logoUrl);
    var rightLogo = comparableLogo(right.logoUrl);
    var logoMatch = leftLogo !== null && rightLogo !== null && leftLogo === rightLogo;

    var bothIds = stated(left.providerChannelId) && stated(right.providerChannelId);
    var namespaceMatch = text(left.providerNamespace) === text(right.providerNamespace);
    var exactProvider =
      bothIds && namespaceMatch && left.providerChannelId === right.providerChannelId;
    // A different namespace says nothing either way, so it is neither exact evidence nor a conflict.
    var providerConflict =
      bothIds && namespaceMatch && left.providerChannelId !== right.providerChannelId;

    if (exactProvider) {
      return candidate(left, right, countryMatch ? 95 : 90, 'exactProviderId', false, countryConflict);
    }
    if (!namesMatch) return null;
    if (countryMatch && logoMatch) {
      return candidate(left, right, 85, 'exactNameCountryLogo', providerConflict, false);
    }
    if (countryMatch) {
      return candidate(left, right, 75, 'exactNameCountry', providerConflict, false);
    }
    if (logoMatch) {
      return candidate(left, right, 70, 'exactNameLogo', providerConflict, countryConflict);
    }
    return candidate(left, right, 50, 'exactNameOnly', providerConflict, countryConflict);
  }

  // An unmapped member is already a channel of its own, whose canonical ID is its member ID (spec rule 4).
  // Treating a missing mapping as "no channel" would make the first merge of a freshly parsed playlist fail.
  function logicalIdOf(state, memberId) {
    var map = state.logicalIdByMemberId || {};
    return hasOwn(map, memberId) ? map[memberId] : memberId;
  }

  // Members of one logical channel, in the order the user's association recorded, falling back to catalog
  // order. Members whose playlist is disabled are still counted here: the association is user data and must
  // survive a disable/enable round trip, even though `unified_catalog.js` hides the channel in the meantime.
  function membersOfLogicalChannel(state, logicalChannelId) {
    var associations = state.associations || [];
    for (var i = 0; i < associations.length; i++) {
      var ids = associations[i].memberIds || [];
      var recorded = [];
      for (var j = 0; j < ids.length; j++) {
        if (logicalIdOf(state, ids[j]) === logicalChannelId) recorded.push(ids[j]);
      }
      if (recorded.length > 1) return recorded;
    }
    var members = state.members || [];
    var out = [];
    for (var k = 0; k < members.length; k++) {
      if (logicalIdOf(state, members[k].memberId) === logicalChannelId) out.push(members[k].memberId);
    }
    return out;
  }

  // The message is the whole contract: Dart throws `ArgumentError('ChannelIdentityError.<code>')` and Swift
  // exposes `ChannelIdentityError.message`, so a screen can key its text on the code rather than on a
  // localized sentence that would drift between ports.
  //
  // Named `guard` rather than mirroring Swift's `require` on purpose: `Tests/webos/channel_identity.test.js`
  // proves this module touches no host API by scanning its code for the text `require(`, and a same-named
  // local helper would make that check unusable for every future module in this directory.
  function guard(condition, code) {
    if (condition) return;
    throw new Error('ChannelIdentityError.' + code);
  }

  function toSet(values) {
    var out = {};
    for (var i = 0; i < values.length; i++) out[values[i]] = true;
    return out;
  }

  function requireKnown(knownSet, memberId) {
    guard(hasOwn(knownSet, memberId), 'unknownMember');
  }

  function knownMemberSet(state) {
    var memberRows = state.members || [];
    var ids = [];
    for (var i = 0; i < memberRows.length; i++) ids.push(memberRows[i].memberId);
    return toSet(ids);
  }

  // Re-parents a source without touching its identity, priority or history. Only `channelId` changes, which is
  // the whole point — an association moves ownership and nothing else. The field list is explicit because
  // JavaScript has no spread and no value copy here: a missing line would silently drop a field, which is why
  // the suite counts the keys of a re-parented source.
  function sourceWithChannel(source, channelId) {
    return {
      sourceId: source.sourceId,
      channelId: channelId,
      memberId: source.memberId,
      playlistId: source.playlistId,
      providerNamespace: source.providerNamespace,
      label: source.label,
      streamUrl: source.streamUrl,
      streamSecretRef: source.streamSecretRef,
      protocolHint: source.protocolHint,
      rendererCapability: source.rendererCapability,
      origin: source.origin,
      priority: source.priority,
      enabled: source.enabled,
      health: source.health,
      lastSuccessfulPlaybackAt: source.lastSuccessfulPlaybackAt,
      lastFailedPlaybackAt: source.lastFailedPlaybackAt,
      lastErrorCode: source.lastErrorCode
    };
  }

  function copyMap(map) {
    var source = map || {};
    var out = {};
    var keys = Object.keys(source);
    for (var i = 0; i < keys.length; i++) out[keys[i]] = source[keys[i]];
    return out;
  }

  function copyList(list) {
    return (list || []).slice();
  }

  // A state built from already-copied collections, so no caller can reach into the previous state through the
  // returned one. Rows are shared by reference; only `sources` and `logicalIdByMemberId` are rebuilt.
  function rebuild(state, sources, associations, mapping) {
    return {
      schemaVersion: state.schemaVersion,
      playlists: copyList(state.playlists),
      members: copyList(state.members),
      sources: sources,
      associations: associations,
      preferences: copyList(state.preferences),
      recentWatches: copyList(state.recentWatches),
      logicalIdByMemberId: mapping
    };
  }

  // Joins `memberIds` into one logical channel owned by `preferredLogicalId`.
  //
  // Validation is complete before anything is built, so a refused request can never leave a half-applied
  // association behind. Member IDs, source IDs, priorities, health, playback history and preferences are
  // carried over untouched, which is what makes an accidental merge reversible with `separate`.
  function associate(state, memberIds, preferredLogicalId) {
    // Counted before deduplication on purpose: "associate these two rows" where the caller repeated one row is
    // the caller's bug, and answering it by silently treating it as a single member would hide it.
    guard(Array.isArray(memberIds) && memberIds.length >= 2, 'fewerThanTwoMembers');
    var seenRequest = [];
    var duplicated = false;
    for (var d = 0; d < memberIds.length; d++) {
      if (seenRequest.indexOf(memberIds[d]) !== -1) duplicated = true;
      seenRequest.push(memberIds[d]);
    }
    guard(!duplicated, 'duplicateMember');

    var memberRows = state.members || [];
    var knownMembers = knownMemberSet(state);
    for (var u = 0; u < memberIds.length; u++) requireKnown(knownMembers, memberIds[u]);

    // The preferred channel is the row the user is acting on; if that is gone, nothing below can be
    // interpreted, so this check comes before the per-member conflict loop.
    var mappingSource = state.logicalIdByMemberId || {};
    guard(hasOwn(mappingSource, preferredLogicalId), 'unknownPreferredLogicalChannel');

    // A member already inside another multi-member channel would have to be taken from it without the user
    // deciding that; a member mapped to itself is unassociated and free to join.
    for (var c = 0; c < memberIds.length; c++) {
      var current = logicalIdOf(state, memberIds[c]);
      if (current === preferredLogicalId) continue;
      guard(membersOfLogicalChannel(state, current).length < 2, 'memberAssociatedElsewhere');
    }

    var selected = toSet(memberIds);
    var keptSet = {};
    var existingGroup = membersOfLogicalChannel(state, preferredLogicalId);
    for (var g = 0; g < existingGroup.length; g++) {
      if (!hasOwn(selected, existingGroup[g])) keptSet[existingGroup[g]] = true;
    }

    // Catalog order for the members already in the channel, then the newcomers in the order the user gave.
    var combined = [];
    for (var m = 0; m < memberRows.length; m++) {
      var id = memberRows[m].memberId;
      if ((hasOwn(selected, id) || hasOwn(keptSet, id)) && logicalIdOf(state, id) === preferredLogicalId) {
        combined.push(id);
      }
    }
    for (var n = 0; n < memberIds.length; n++) {
      if (logicalIdOf(state, memberIds[n]) !== preferredLogicalId) combined.push(memberIds[n]);
    }

    var combinedSet = toSet(combined);
    var mapping = copyMap(mappingSource);
    for (var p = 0; p < combined.length; p++) mapping[combined[p]] = preferredLogicalId;

    var sourceRows = state.sources || [];
    var sources = [];
    for (var s = 0; s < sourceRows.length; s++) {
      sources.push(
        hasOwn(selected, sourceRows[s].memberId)
          ? sourceWithChannel(sourceRows[s], preferredLogicalId)
          : sourceRows[s]
      );
    }

    var associations = [];
    var existingAssociations = state.associations || [];
    for (var a = 0; a < existingAssociations.length; a++) {
      var ids = existingAssociations[a].memberIds || [];
      var absorbed = false;
      for (var q = 0; q < ids.length; q++) {
        if (hasOwn(combinedSet, ids[q])) absorbed = true;
      }
      if (!absorbed) associations.push(existingAssociations[a]);
    }
    associations.push({ memberIds: combined });

    return rebuild(state, sources, associations, mapping);
  }

  // Takes one member out of its channel and gives it the canonical logical ID (its own member ID).
  //
  // The other members keep their channel, so splitting a three-way merge is one user action rather than a
  // rebuild. Preferences stay where they were: the leaving branch inherits nothing, and the settings it had
  // before it joined are still keyed on its own member ID, which is why a merge followed by a split restores
  // what the user had.
  function separate(state, memberId) {
    requireKnown(knownMemberSet(state), memberId);

    var current = logicalIdOf(state, memberId);
    var group = membersOfLogicalChannel(state, current);
    guard(group.length >= 2, 'fewerThanTwoMembers');

    var remaining = [];
    for (var i = 0; i < group.length; i++) {
      if (group[i] !== memberId) remaining.push(group[i]);
    }

    var mapping = copyMap(state.logicalIdByMemberId);
    mapping[memberId] = memberId;

    var sourceRows = state.sources || [];
    var sources = [];
    for (var s = 0; s < sourceRows.length; s++) {
      sources.push(
        sourceRows[s].memberId === memberId ? sourceWithChannel(sourceRows[s], memberId) : sourceRows[s]
      );
    }

    // Two members that were merged only with each other leave nothing to record; three leave a pair that is
    // still an explicit user statement and must survive.
    var associations = [];
    var existingAssociations = state.associations || [];
    for (var a = 0; a < existingAssociations.length; a++) {
      var ids = existingAssociations[a].memberIds || [];
      var leaves = false;
      for (var j = 0; j < ids.length; j++) {
        if (ids[j] === memberId) leaves = true;
      }
      if (!leaves) associations.push(existingAssociations[a]);
    }
    if (remaining.length >= 2) associations.push({ memberIds: remaining });

    return rebuild(state, sources, associations, mapping);
  }

  // `logicalIdOf` and `membersOfLogicalChannel` are public here as they are in Dart and Swift, and
  // `unified_catalog.js` reads them from this namespace rather than re-deriving the mapping rule a second
  // time. `ambiguityFloor` is exposed so a screen warns on the same number the scorer used instead of
  // hardcoding 85.
  CC.channelIdentity = {
    ambiguityFloor: AMBIGUITY_FLOOR,
    findCandidate: findCandidate,
    logicalIdOf: logicalIdOf,
    membersOfLogicalChannel: membersOfLogicalChannel,
    associate: associate,
    separate: separate
  };
})();
