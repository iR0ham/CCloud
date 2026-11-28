/* Unified catalog view (webOS).
 *
 * This is the JavaScript half of `flutter_app/lib/core/unified_catalog.dart` and
 * `Sources/Core/UnifiedLiveCatalog.swift`. It is the single place the persisted state becomes the list a user
 * sees, and it is a projection rather than a second source of truth: it mutates nothing, returns fresh values,
 * and the caller may rebuild it after every edit.
 *
 * Two consequences of that framing, asserted here exactly as the Dart and Swift suites assert them:
 *
 * * A disabled playlist disappears from the view while its member and source rows stay in the state, so
 *   re-enabling restores precisely what the user had.
 * * A disabled *source* stays in its channel's `sources` list, because the user manages it. Playback
 *   eligibility is `enabled`, and that filter belongs to the recovery chain (Phase C), not to the view.
 *
 * The identity mapping is read from `CC.channelIdentity` rather than re-derived, because "which logical channel
 * owns this member" is one rule with one owner on every port. The default source policy is read from
 * `CC.playlistContracts.standardSourcePolicy()` for the same reason: a fourth hardcoded policy is a fourth
 * number that can drift.
 *
 * ES2017 idiom, same ceiling as `channel_identity.js`: `var`, function expressions, explicit index loops, no
 * storage, no network, no DOM. Task B4-J registers this file in `index.html` after `channel_identity.js`.
 */
window.CC = window.CC || {};

(function () {
  var CC = window.CC;

  function hasOwn(map, key) {
    return Object.prototype.hasOwnProperty.call(map, key);
  }

  // Priority first, then the source ID, so two rows sharing a priority still order identically on every
  // platform. The tiebreak is explicit because no port promises a stable sort, and Chromium 68's is the least
  // guaranteed of the three.
  function byPriorityThenSourceId(left, right) {
    if (left.priority !== right.priority) return left.priority < right.priority ? -1 : 1;
    if (left.sourceId === right.sourceId) return 0;
    return left.sourceId < right.sourceId ? -1 : 1;
  }

  function toSet(values) {
    var out = {};
    for (var i = 0; i < values.length; i++) out[values[i]] = true;
    return out;
  }

  // Builds one logical channel per logical ID that has at least one member in an enabled playlist.
  //
  // Channels are ordered by explicit `userOrder` first (ascending, unset last), then by the order their
  // preferred member appears in the catalog, so a list stays stable across refreshes and never reorders itself
  // because a preference was edited for an unrelated channel.
  function build(state) {
    var identity = CC.channelIdentity;
    var playlists = state.playlists || [];
    var members = state.members || [];
    var sourceRows = state.sources || [];
    var preferences = state.preferences || [];
    var associations = state.associations || [];

    var enabledPlaylists = {};
    for (var p = 0; p < playlists.length; p++) {
      if (playlists[p].enabled) enabledPlaylists[playlists[p].playlistId] = true;
    }

    var memberById = {};
    for (var m = 0; m < members.length; m++) memberById[members[m].memberId] = members[m];

    var preferenceByChannel = {};
    for (var f = 0; f < preferences.length; f++) preferenceByChannel[preferences[f].channelId] = preferences[f];

    // Members grouped by logical ID, in catalog appearance order. Disabled playlists contribute nothing, which
    // is also how a member whose playlist row was removed stays out of the view: an absent playlist record is
    // not an enabled one.
    var appearanceOrder = [];
    var memberIdsByChannel = {};
    for (var i = 0; i < members.length; i++) {
      var member = members[i];
      if (!hasOwn(enabledPlaylists, member.playlistId)) continue;
      var logicalId = identity.logicalIdOf(state, member.memberId);
      if (!hasOwn(memberIdsByChannel, logicalId)) {
        memberIdsByChannel[logicalId] = [];
        appearanceOrder.push(logicalId);
      }
      memberIdsByChannel[logicalId].push(member.memberId);
    }

    // An association records the user's own member order, which is what the channel's source list and metadata
    // refer to; catalog order is only the fallback for rows added later. The pass walks `appearanceOrder`
    // rather than an object's keys so both ports pick the same association when two cover one group.
    for (var g = 0; g < appearanceOrder.length; g++) {
      var group = memberIdsByChannel[appearanceOrder[g]];
      if (group.length < 2) continue;
      var visible = toSet(group);
      for (var a = 0; a < associations.length; a++) {
        var ids = associations[a].memberIds || [];
        var ordered = [];
        for (var q = 0; q < ids.length; q++) {
          if (hasOwn(visible, ids[q])) ordered.push(ids[q]);
        }
        if (ordered.length === group.length) {
          memberIdsByChannel[appearanceOrder[g]] = ordered;
          break;
        }
      }
    }

    // Sources follow their member's logical channel, not their stored `channelId`. The mapping is the
    // authoritative user decision, and a row written before an association (or by an older port) may still
    // name its member ID. A source whose member is unknown, or whose member's playlist is disabled, is not
    // shown — and is not deleted, so it returns with the playlist.
    var sourcesByChannel = {};
    for (var s = 0; s < sourceRows.length; s++) {
      var owner = memberById[sourceRows[s].memberId];
      if (!owner) continue;
      var ownerId = identity.logicalIdOf(state, owner.memberId);
      if (!hasOwn(memberIdsByChannel, ownerId)) continue;
      if (!hasOwn(sourcesByChannel, ownerId)) sourcesByChannel[ownerId] = [];
      sourcesByChannel[ownerId].push(sourceRows[s]);
    }
    var groupedKeys = Object.keys(sourcesByChannel);
    for (var k = 0; k < groupedKeys.length; k++) {
      sourcesByChannel[groupedKeys[k]].sort(byPriorityThenSourceId);
    }

    var appearanceIndex = {};
    for (var x = 0; x < appearanceOrder.length; x++) appearanceIndex[appearanceOrder[x]] = x;

    // Explicit tiebreak inside the comparator, because a Chromium 68 sort is not documented to be stable and
    // the ports must agree on the same order rather than on "stable enough".
    var orderedChannels = appearanceOrder.slice().sort(function (left, right) {
      var orderLeft = hasOwn(preferenceByChannel, left) ? preferenceByChannel[left].userOrder : null;
      var orderRight = hasOwn(preferenceByChannel, right) ? preferenceByChannel[right].userOrder : null;
      var placedLeft = orderLeft !== null && orderLeft !== undefined;
      var placedRight = orderRight !== null && orderRight !== undefined;
      if (placedLeft || placedRight) {
        // An unset order is "not manually placed", so it sorts after every placed channel.
        if (!placedLeft) return 1;
        if (!placedRight) return -1;
        if (orderLeft !== orderRight) return orderLeft < orderRight ? -1 : 1;
      }
      if (appearanceIndex[left] === appearanceIndex[right]) return 0;
      return appearanceIndex[left] < appearanceIndex[right] ? -1 : 1;
    });

    var channels = [];
    for (var c = 0; c < orderedChannels.length; c++) {
      var channelKey = orderedChannels[c];
      var memberIds = memberIdsByChannel[channelKey];
      var preferred = memberIds && memberIds.length > 0 ? memberById[memberIds[0]] : null;
      if (!preferred) {
        // Unreachable by construction: a group is created only while walking real members. Skipping the row
        // here instead of throwing keeps the projection total, and keeps the ports identical.
        continue;
      }
      var preference = hasOwn(preferenceByChannel, channelKey) ? preferenceByChannel[channelKey] : null;
      channels.push({
        channelId: channelKey,
        displayName: preferred.displayName,
        normalizedName: preferred.normalizedName,
        logoUrl: preferred.logoUrl !== undefined ? preferred.logoUrl : null,
        // A user's category wins over the provider's group, because the group came from one playlist while
        // the channel may now span several.
        category: preference && preference.category ? preference.category : preferred.group,
        countryCode: preferred.countryCode !== undefined ? preferred.countryCode : null,
        languages: preferred.languages || [],
        memberIds: memberIds,
        sources: hasOwn(sourcesByChannel, channelKey) ? sourcesByChannel[channelKey] : [],
        favorite: preference ? preference.favorite === true : false,
        hidden: preference ? preference.hidden === true : false,
        userOrder: preference && preference.userOrder !== undefined ? preference.userOrder : null,
        // Declaring the fallback in one place keeps "failover is on unless the user said otherwise" a contract
        // value rather than four literals spread across the screens.
        automaticFailoverEnabled: preference ? preference.automaticFailoverEnabled !== false : true,
        sourcePolicy: preference && preference.sourcePolicy
          ? preference.sourcePolicy
          : CC.playlistContracts.standardSourcePolicy(),
        lastSuccessfulSourceId: preference && preference.lastSuccessfulSourceId
          ? preference.lastSuccessfulSourceId
          : null
      });
    }

    return channels;
  }

  // `registerBuiltIn` is attached to this same namespace by `builtin_catalog_adapter.js`, which is the pattern
  // the plan names for the built-in bridge: one namespace a screen can call, two files with one job each.
  CC.unifiedCatalog = {
    build: build
  };
})();
