/* Built-in catalog adapter (webOS).
 *
 * This is the JavaScript half of `flutter_app/lib/core/builtin_catalog_adapter.dart` and
 * `Sources/Core/BuiltInLiveCatalogAdapter.swift`. The built-in Iran list already exists as runtime channel rows
 * (`webos_app/app/js/api.js` `normChannel`, fetched by `webos_app/app/js/feed.js`), and this adapter is the only
 * bridge that lets those rows live in the multi-source catalog. Its whole job is to add nothing: no channel the
 * provider does not state, no capability a player has not proven, no logo the dataset does not carry.
 *
 * Identity uses the same recipes as `CC.playlistParser.registerParsedPlaylist`, because a built-in row and a
 * parsed playlist row from the same provider are the same member — that is what lets a user add an external
 * playlist that re-lists IRIB 1 without the list doubling. `memberId` and `sourceId` therefore come from the
 * shared `stableKeyHash`, not from a second digest of the same idea.
 *
 * Deliberate choices, each of which the Dart and Swift ports reproduce:
 *
 * * A row without a provider ID still needs a stable one, so the name-fold becomes the provider ID under the
 *   `name:` prefix. It is provider-namespaced, so it can never collide with a real ID.
 * * Rows sharing a provider ID merge into one member with gapless priorities rather than producing a duplicate.
 * * No logo is invented: the built-in dataset carries none, so `logoUrl` stays null and a name+country pair is
 *   scored 75 rather than pretending to be 85.
 * * Credential-bearing addresses are refused, not stored. There is no verified secret store on webOS (see
 *   `playlist_parser.js:1010`), so a refused address simply disappears; the property that matters is that the
 *   caller can never see a credential in persisted text.
 * * Display names arrive exactly as the provider stated them. `CC.playlistParser.displayName` is the
 *   playlist-parse path's noise strip and is not applied here, so a built-in row whose own name carries a
 *   `(720p)`-style token yields no merge candidate for a clean-named sibling. That is the same known gap
 *   recorded for the Swift port in `Tests/live-foundation/main.swift`; candidates only ever suggest, so it
 *   under-suggests rather than mis-merges, and task B4 owns closing it.
 *
 * `registerBuiltIn` is attached to `CC.unifiedCatalog`, the namespace task B4-J's screens already call for the
 * list, so the built-in bridge never becomes a second entry point a screen has to remember.
 *
 * ES2017 idiom, same ceiling as `channel_identity.js`: `var`, function expressions, explicit index loops, no
 * storage, no network, no DOM, and no `new URL()`.
 */
window.CC = window.CC || {};

(function () {
  var CC = window.CC;

  function text(value) {
    return typeof value === 'string' ? value : '';
  }

  function hasOwn(map, key) {
    return Object.prototype.hasOwnProperty.call(map, key);
  }

  function toSet(values) {
    var out = {};
    for (var i = 0; i < values.length; i++) out[values[i]] = true;
    return out;
  }

  // A blank country is *unknown*, not a country named `""`: the comparison layer must be able to tell the two
  // apart, because an unknown value can neither match nor conflict. `api.js` only trims and passes the provider
  // text through, so the same normalization the comparison layer uses is applied here.
  function comparableCountry(value) {
    var trimmed = text(value).trim().toUpperCase();
    return trimmed === '' ? null : trimmed;
  }

  function streamList(channel) {
    var rows = channel && channel.streams;
    return Array.isArray(rows) ? rows : [];
  }

  // What the built-in rows contribute: members, their sources, and the untouched runtime row list.
  //
  // `channels` is returned as the caller passed it, so the player keeps working from the same rows while the
  // catalog gains its member and source records. Dart wraps that list as unmodifiable and Swift gets a copy
  // because its arrays are value types; JavaScript has neither, so the honest equivalent is the same reference
  // with the ownership written down: this function never edits a row.
  function registerBuiltIn(channels, options) {
    var parser = CC.playlistParser;
    var settings = options || {};
    var playlistId = text(settings.playlistId);
    var providerNamespace = text(settings.providerNamespace);
    var rows = Array.isArray(channels) ? channels : [];

    var members = [];
    var sources = [];
    var seenMemberIds = {};
    var priorityByMember = {};
    var seenUrlsByMember = {};

    for (var i = 0; i < rows.length; i++) {
      var channel = rows[i];
      var trimmedId = text(channel && channel.nanoid).trim();
      var name = text(channel && channel.name);
      var normalizedName = parser.nameKey(name);
      var languages = channel && Array.isArray(channel.languages) ? channel.languages : [];
      var providerChannelId = trimmedId === '' ? 'name:' + normalizedName : trimmedId;
      var memberId = 'member:' + parser.stableKeyHash(
        playlistId + '\nprovider\n' + providerNamespace + '\n' + providerChannelId
      );

      // The set is the dedup: a second Famelack row carrying the same provider ID contributes its URLs to the
      // member that already exists instead of minting a duplicate station.
      if (!hasOwn(seenMemberIds, memberId)) {
        seenMemberIds[memberId] = true;
        members.push({
          memberId: memberId,
          playlistId: playlistId,
          providerNamespace: providerNamespace,
          providerChannelId: providerChannelId,
          displayName: name,
          normalizedName: normalizedName,
          // Ordinal is the catalog position, taken when the member is appended. Reading `i` instead would leave
          // a hole for every merged duplicate row and reorder the list on refresh.
          ordinal: members.length,
          logoUrl: null,
          group: null,
          countryCode: comparableCountry(channel && channel.country),
          languages: languages.slice(),
          tvgId: trimmedId === '' ? null : trimmedId
        });
      }

      var seenKey = memberId;
      if (!hasOwn(seenUrlsByMember, seenKey)) seenUrlsByMember[seenKey] = {};
      var seenUrls = seenUrlsByMember[seenKey];
      var priority = hasOwn(priorityByMember, seenKey) ? priorityByMember[seenKey] : 0;
      var urls = streamList(channel);

      for (var u = 0; u < urls.length; u++) {
        var canonical = parser.canonicalStreamUrl(urls[u]);
        if (!canonical) continue;
        // Remembered before the credential test, so two spellings of one refused address are refused once and
        // the priority sequence stays gapless.
        if (hasOwn(seenUrls, canonical)) continue;
        seenUrls[canonical] = true;
        if (parser.isSensitiveUrl(canonical)) continue;

        sources.push({
          sourceId: 'source:' + parser.stableKeyHash(memberId + '\nurl\n' + canonical),
          // Rule 4 again: a built-in row is its own channel until the user associates it.
          channelId: memberId,
          memberId: memberId,
          playlistId: playlistId,
          providerNamespace: providerNamespace,
          label: priority === 0 ? 'منبع اصلی' : 'منبع ' + parser.persianDigits(priority + 1),
          streamUrl: canonical,
          streamSecretRef: null,
          protocolHint: parser.protocolHint(canonical),
          // Parsing a row is not evidence about a decoder: nothing here claims support.
          rendererCapability: 'Not Yet Verified',
          origin: 'playlist',
          priority: priority,
          enabled: true,
          health: 'unverified',
          lastSuccessfulPlaybackAt: null,
          lastFailedPlaybackAt: null,
          lastErrorCode: null
        });
        priority += 1;
      }

      priorityByMember[seenKey] = priority;
    }

    return { members: members, sources: sources, channels: rows };
  }

  CC.unifiedCatalog = CC.unifiedCatalog || {};
  CC.unifiedCatalog.registerBuiltIn = registerBuiltIn;
})();
