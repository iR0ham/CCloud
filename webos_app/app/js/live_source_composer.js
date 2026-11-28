/* Behaviour-neutral live row composer (webOS, task B4-3 slice S1).
 *
 * The Swift half is `Sources/Core/LiveSourceComposer.swift`, the Dart half is
 * `flutter_app/lib/core/live_source_composer.dart`, and all three read the same bytes from
 * `Tests/fixtures/live-composer/composer_cases.json`. S1 adds the join without adding a call site: no screen
 * imports this file yet, and `js/screens/live.js` still renders the fetch's own list. What it answers is the
 * question S2 has to ask at that screen — "today's built-in row list, plus whatever the stored catalog would
 * contribute, in the row type the screen already renders" — and it must answer it with today's list identical
 * whenever the stored document is absent, empty, or unreadable. That neutrality claim, not the merge, is what
 * the suites here pin.
 *
 * The row type is `api.js`'s `normChannel` output (`api.js:326-344`): a flat object carrying `nanoid`, `name`,
 * `streams`, `languages`, `country`, `isGeoBlocked` and the three derived fields the live screen reads
 * (`stringId`, `primaryStream`, `languageLabel`). `builtin_catalog_adapter.js:63-66` already reads `streams`
 * from that shape, so the composer takes and returns the same object rather than a fourth row type.
 *
 * The pipeline, in the order that keeps each stage's contract intact:
 *
 * 1. `CC.unifiedCatalog.registerBuiltIn` turns the host rows into members and sources. That adapter is the only
 *    bridge between the built-in list and the catalog, so the composer calls it rather than restating its
 *    recipes.
 * 2. Registered members are appended to the stored rows, deduplicated by the provider identity the adapter
 *    writes (`playlistId` + `providerNamespace` + `providerChannelId`) rather than by `memberId`. A stored row
 *    always wins, so a document that already carries the built-in half keeps its own ids — which is also what
 *    lets the shared fixture name a built-in member literally instead of making three ports reproduce a
 *    `stableKeyHash` digest. A folded member's sources are retargeted onto the survivor, because the view drops
 *    a source whose member is unknown (`unified_catalog.js:114`), and deduplicated by (member, address) rather
 *    than `sourceId`.
 * 3. An enabled `builtin:live` playlist record is injected only when the state carries none. Without a record
 *    the view hides every built-in member (`unified_catalog.js:78` gates members on an enabled playlist), so the
 *    list a user has always seen would vanish. The injection is forced by neutrality, and it is not the open
 *    owner decision about an enable-flag default: a record the user did write is never overwritten.
 * 4. `CC.unifiedCatalog.build` is called, not reimplemented. Grouping, association order and source priority are
 *    its rules; the composer reads them out of its result instead of deriving them a second time.
 * 5. The result is projected back onto host rows. A channel containing a built-in member adds its addresses to
 *    that row; a channel with no built-in half becomes one new row.
 *
 * Two asymmetries inside step 5 are deliberate:
 *
 * * An anchored row keeps its own stream text. The catalog stores a canonicalized address, which can differ in
 *   case or default port from what the provider wrote, and today's player is handed the provider's text
 *   (`screens/live.js:67`) — so normalizing it here would be exactly the behaviour change S2 must decide on.
 *   Deduplication compares canonical forms, so a re-spelled origin does not become a second entry.
 * * A credential-bearing address is refused only among the addresses being added. One already in the built-in
 *   list is today's behavior; one arriving from the catalog would be a new plaintext address handed to the
 *   player and reachable through the copy-address action, so it is dropped and counted instead.
 *
 * `issues` carries §18.5's measurement rather than a verdict. The composer must not fold-normalize built-in
 * names, so `nameKey(name)` and the same fold over `displayName(name)` are allowed to differ; each difference is
 * reported as one `builtinFoldGap`, spelled through `CC.playlistContracts.issue` so the record has the same
 * three fields a parse diagnostic has. That is a known-gap count for the reports, never a production failure,
 * and with no call site yet it cannot fail anything.
 *
 * Ordering is the host comparator (`api.js:316`: lowercased `<`), never the catalog's `userOrder`-then-
 * appearance order, which is invariant I3. The built-in prefix keeps the order the fetch already produced and new
 * rows are inserted where that comparator puts them, so the function is a literal identity when the state adds
 * nothing. Sorting the whole list instead would let Chromium 68's unstable `Array.prototype.sort` swap two
 * same-named rows between refreshes, which is a behaviour change hiding inside a "no-op" path.
 *
 * S1 needs no storage, so none is touched: the caller passes the state the persistence seam already loaded, and
 * keeping `CC.store` out of this file is what lets the whole module be exercised in a sealed scope with no
 * `localStorage` at all. ES2017 idiom, same ceiling as `unified_catalog.js` and `live_catalog_store.js`: `var`,
 * function expressions, explicit index loops, no host APIs, and every sibling module read at call time rather
 * than captured at load time.
 */
window.CC = window.CC || {};

(function () {
  var CC = window.CC;

  // Mirrors `LiveSourceComposer.builtInPlaylistId` / `builtInProviderNamespace` and the Dart
  // `LiveSourceComposer` constants, and the two values `js/screens/live.js` will pass in S2.
  var BUILT_IN_PLAYLIST_ID = 'builtin:live';
  var BUILT_IN_PROVIDER_NAMESPACE = 'famelack';

  // `secretStorageUnavailable` is `playlist_parser.js`'s own refusal word, reused so one condition has one name
  // across the parse and display paths. `builtinFoldGap` is the only code this file owns. Both are counted by
  // name in the shared fixture, on all three ports.
  var ISSUE_SECRET_REFUSAL = 'secretStorageUnavailable';
  var ISSUE_FOLD_GAP = 'builtinFoldGap';
  var FOLD_GAP_MESSAGE = 'Built-in name keeps a quality token, so its match key differs from the playlist-path display name';
  // No address text in the message: an issue list is allowed to reach a log, and the whole point of the refusal
  // is that the credential does not travel.
  var SECRET_MESSAGE = 'Credential-bearing address withheld from the composed row list';

  // The built-in record is a view precondition, not an event, so its timestamp is the epoch rather than the
  // clock: an impure value would make the composed output differ between two runs of the same bytes, which
  // would break the determinism the shared fixture pins.
  var EPOCH = '1970-01-01T00:00:00.000Z';
  var UNKNOWN_LANGUAGE = 'نامشخص';

  function hasOwn(map, key) {
    return Object.prototype.hasOwnProperty.call(map, key);
  }

  function text(value) {
    return typeof value === 'string' ? value : '';
  }

  function stringList(value) {
    if (!Array.isArray(value)) return [];
    var out = [];
    for (var i = 0; i < value.length; i++) {
      if (typeof value[i] === 'string') out.push(value[i]);
    }
    return out;
  }

  // Sibling modules are read at call time, not captured at load time: `index.html` decides the real load order
  // on a TV, and a stale local binding here would make that order a second thing to get right.
  function parser() {
    return CC.playlistParser;
  }

  function contracts() {
    return CC.playlistContracts;
  }

  function catalog() {
    return CC.unifiedCatalog;
  }

  // The parse layer's own issue shape (`playlist_contracts.js:690`), so a screen or a log that already prints a
  // diagnostic needs no special case for one produced here.
  function makeIssue(code, message) {
    return contracts().issue(code, message, null);
  }

  // One issue per built-in row whose raw name folds differently from its noise-stripped display name. This is the
  // measurement §18.5 asks for in place of a normalization: the built-in path keeps provider text verbatim
  // (`builtin_catalog_adapter.js:24-28`), so such a row can never produce a merge candidate for a clean-named
  // parsed sibling. The gap stays open (task B4 owns it); what changes is that it is now counted.
  function foldGapIssues(rows) {
    var issues = [];
    var rules = parser();
    for (var i = 0; i < rows.length; i++) {
      var name = text(rows[i] && rows[i].name);
      if (rules.nameKey(name) === rules.nameKey(rules.displayName(name))) continue;
      issues.push(makeIssue(ISSUE_FOLD_GAP, FOLD_GAP_MESSAGE));
    }
    return issues;
  }

  function providerKey(member) {
    return text(member.playlistId) + '\n' + text(member.providerNamespace) + '\n' + text(member.providerChannelId);
  }

  function addressKey(source) {
    return text(source.memberId) + '\n' + text(source.streamUrl).trim().toLowerCase();
  }

  function isBuiltInMember(member) {
    return text(member.playlistId) === BUILT_IN_PLAYLIST_ID &&
      text(member.providerNamespace) === BUILT_IN_PROVIDER_NAMESPACE;
  }

  /**
   * Members and sources the document does not already carry, plus the built-in playlist record if absent.
   *
   * Appending rather than replacing keeps every id the state refers to through `logicalIdByMemberId` and
   * `associations` valid, so the view's grouping — which is the user's own decision — survives the join. Nothing
   * in the stored state is mutated: the seam's returned object stays exactly what it was, because a caller that
   * later saves it must save what it loaded, not what one display pass invented.
   */
  function mergeState(stored, registered, builtInCount) {
    // Provider identity, not `memberId`, decides whether two rows are the same station. A registered member whose
    // provider key is already in the document is that station, so the stored row keeps its own id and the minted
    // one disappears.
    var storedMembers = Array.isArray(stored.members) ? stored.members : [];
    var survivorByProviderKey = {};
    for (var s = 0; s < storedMembers.length; s++) {
      survivorByProviderKey[providerKey(storedMembers[s])] = text(storedMembers[s].memberId);
    }

    // Registered member id -> the stored id that already describes the same station. Kept separate from the
    // provider-key map above so one lookup never has to guess which of the two namespaces a key belongs to.
    var foldedMember = {};
    var members = storedMembers.slice();
    var registeredMembers = Array.isArray(registered.members) ? registered.members : [];
    for (var m = 0; m < registeredMembers.length; m++) {
      var member = registeredMembers[m];
      var key = providerKey(member);
      var existing = hasOwn(survivorByProviderKey, key) ? survivorByProviderKey[key] : null;
      if (existing) {
        foldedMember[text(member.memberId)] = existing;
        continue;
      }
      survivorByProviderKey[key] = text(member.memberId);
      members.push(member);
    }

    // A source follows the member it was registered from, so a folded member's addresses are retargeted onto the
    // survivor instead of being dropped: `unified_catalog.js:114` discards a source whose member is unknown, and
    // one new Famelack URL would otherwise vanish whenever the stored document already named that station. Both
    // id fields move together because the record is meant to describe the surviving member; the view groups by
    // member, so the remap only keeps this ephemeral state internally consistent.
    //
    // The dedup key is (member, canonical address) rather than `sourceId`: the same address under two spellings of
    // the row id is one address, and appending it twice would duplicate a playable source in the channel the user
    // sees.
    var storedSources = Array.isArray(stored.sources) ? stored.sources : [];
    var seenAddresses = {};
    for (var a = 0; a < storedSources.length; a++) seenAddresses[addressKey(storedSources[a])] = true;
    var sources = storedSources.slice();
    var registeredSources = Array.isArray(registered.sources) ? registered.sources : [];
    for (var r = 0; r < registeredSources.length; r++) {
      var source = registeredSources[r];
      var survivor = hasOwn(foldedMember, text(source.memberId)) ? foldedMember[text(source.memberId)] : null;
      var record = source;
      if (survivor) {
        record = shallowCopy(source);
        record.memberId = survivor;
        record.channelId = survivor;
      }
      var address = addressKey(record);
      if (hasOwn(seenAddresses, address)) continue;
      seenAddresses[address] = true;
      sources.push(record);
    }

    var storedPlaylists = Array.isArray(stored.playlists) ? stored.playlists : [];
    var playlists = storedPlaylists.slice();
    var hasBuiltInRecord = false;
    for (var p = 0; p < storedPlaylists.length; p++) {
      if (text(storedPlaylists[p].playlistId) === BUILT_IN_PLAYLIST_ID) hasBuiltInRecord = true;
    }
    if (!hasBuiltInRecord) {
      // See the header: an enabled record is what keeps today's list visible. This is a row of the same shape the
      // codec writes (`playlist_contracts.js`'s playlist list), built here rather than stored anywhere.
      playlists.push({
        playlistId: BUILT_IN_PLAYLIST_ID,
        name: 'CCloud',
        sourceType: 'builtIn',
        locationRef: BUILT_IN_PLAYLIST_ID,
        enabled: true,
        createdAt: EPOCH,
        lastUpdatedAt: null,
        lastSuccessfulRefresh: null,
        refreshStatus: 'ready',
        lastErrorCode: null,
        channelCount: builtInCount,
        parsingVersion: 1
      });
    }

    return {
      schemaVersion: stored.schemaVersion,
      playlists: playlists,
      members: members,
      sources: sources,
      associations: Array.isArray(stored.associations) ? stored.associations : [],
      preferences: Array.isArray(stored.preferences) ? stored.preferences : [],
      recentWatches: Array.isArray(stored.recentWatches) ? stored.recentWatches : [],
      logicalIdByMemberId: stored.logicalIdByMemberId || {}
    };
  }

  function shallowCopy(value) {
    var out = {};
    var keys = Object.keys(value);
    for (var i = 0; i < keys.length; i++) out[keys[i]] = value[keys[i]];
    return out;
  }

  /**
   * The built-in row each merged member was registered from, as an index into the caller's list.
   *
   * Matching uses the fields the adapter itself wrote — `displayName` is the row's name verbatim and `tvgId` its
   * trimmed provider id — because re-deriving the `name:`-prefix fallback here would put a second copy of that
   * recipe in the codebase, which is how a refresh ends up with two members for one station.
   */
  function anchorIndexes(built, members) {
    var rowsByTvgId = {};
    var rowsByName = {};
    for (var i = 0; i < built.length; i++) {
      var trimmed = text(built[i] && built[i].nanoid).trim();
      var name = text(built[i] && built[i].name);
      if (trimmed !== '' && !hasOwn(rowsByTvgId, trimmed)) rowsByTvgId[trimmed] = i;
      if (!hasOwn(rowsByName, name)) rowsByName[name] = i;
    }

    var anchored = {};
    for (var m = 0; m < members.length; m++) {
      var member = members[m];
      if (!isBuiltInMember(member) || hasOwn(anchored, member.memberId)) continue;
      var tvgId = member.tvgId === null || member.tvgId === undefined ? null : text(member.tvgId);
      if (tvgId !== null && hasOwn(rowsByTvgId, tvgId)) {
        anchored[member.memberId] = rowsByTvgId[tvgId];
      } else if (hasOwn(rowsByName, text(member.displayName))) {
        anchored[member.memberId] = rowsByName[text(member.displayName)];
      }
    }
    return anchored;
  }

  function smallestAnchor(memberIds, anchored) {
    var best = null;
    for (var i = 0; i < memberIds.length; i++) {
      if (!hasOwn(anchored, memberIds[i])) continue;
      var index = anchored[memberIds[i]];
      if (best === null || index < best) best = index;
    }
    return best;
  }

  /**
   * The addresses a channel contributes that are new, playable-shaped, and credential-free.
   *
   * `known` grows as it is consumed, so two sources spelling one address contribute it once even when they arrive
   * in the same pass.
   */
  function contributedUrls(sources, known, issues) {
    var urls = [];
    var rules = parser();
    for (var i = 0; i < sources.length; i++) {
      var source = sources[i];
      // A disabled source stays in the channel's own list — the user manages it there — but this output is the
      // playable row list, and eligibility is `enabled`. Adding a turned-off address here would undo the toggle.
      if (source.enabled === false) continue;
      // A secret-backed source carries no address in the document at all, so there is nothing to add and no
      // refusal to report; the recovery chain resolves it through the secret store in Phase C.
      if (source.streamSecretRef) continue;
      var trimmed = text(source.streamUrl).trim();
      if (trimmed === '') continue;
      var canonical = rules.canonicalStreamUrl(trimmed);
      if (canonical === null) continue;
      if (rules.isSensitiveUrl(trimmed)) {
        issues.push(makeIssue(ISSUE_SECRET_REFUSAL, SECRET_MESSAGE));
        continue;
      }
      var key = canonical.toLowerCase();
      if (hasOwn(known, key)) continue;
      known[key] = true;
      urls.push(trimmed);
    }
    return urls;
  }

  // `api.js:333-334` picks the address the player is handed: the first HLS entry, otherwise the first address.
  // Restating that one rule is what keeps a composer-minted row renderable by the screen that already exists,
  // and the suite pins the restatement so a future change to `normChannel` shows up as a RED here.
  function primaryStreamOf(urls) {
    for (var i = 0; i < urls.length; i++) {
      if (urls[i].toLowerCase().indexOf('.m3u8') >= 0) return urls[i];
    }
    return urls.length > 0 ? urls[0] : '';
  }

  // Late-bound for the same reason `CC.liveCountryName` is: the Persian language table belongs to `api.js`
  // (`api.js:356-368`, exported below it as `CC.liveLanguageName`), and a second copy here would be a table that
  // can drift. With no table loaded there is nothing to name, so the answer is the same "unknown" label the
  // host row uses rather than a guessed one.
  function languageLabelOf(languages) {
    var label = '';
    var name = CC.liveLanguageName;
    if (typeof name === 'function') {
      for (var i = 0; i < languages.length; i++) {
        var value = name(languages[i]);
        if (typeof value === 'string' && value.length > 0) label += (label.length > 0 ? '، ' : '') + value;
      }
    }
    return label.length > 0 ? label : UNKNOWN_LANGUAGE;
  }

  /**
   * A catalog channel with no built-in half becomes one row carrying exactly what the catalog states.
   *
   * The row identity is the logical channel id, so it is never empty and the display layer's key stays unique. A
   * streamless channel yields no row: `api.js:315` already refuses a streamless entry, so a channel that cannot
   * play anything would be a new dead cell rather than preserved behaviour.
   */
  function rowForChannel(channel, issues) {
    var urls = contributedUrls(channel.sources || [], {}, issues);
    if (urls.length === 0) return null;
    var languages = stringList(channel.languages);
    var name = text(channel.displayName);
    var id = text(channel.channelId);
    // The host row holds a plain string and the adapter uppercases it for comparison; the catalog's comparable
    // form is uppercase-or-null, and an unknown country must not render as a country named "".
    var country = channel.countryCode === null || channel.countryCode === undefined ? '' : text(channel.countryCode);
    return {
      nanoid: id,
      name: name,
      streams: urls,
      languages: languages,
      country: country,
      // Nothing in the catalog models a geo-block at all — a member carries no such field — and the adapter's
      // answer to a claim it has no evidence for is null rather than a guess. A row the provider never described
      // cannot be rendered as blocked.
      isGeoBlocked: false,
      stringId: id !== '' ? id : name + '-' + country,
      primaryStream: primaryStreamOf(urls),
      languageLabel: languageLabelOf(languages)
    };
  }

  /**
   * The anchor row, plus only the addresses it does not already list, in catalog priority order.
   *
   * Every other field stays the anchor's own: no catalog member can state a geo-block for a row the provider
   * already described, and inheriting one would be an invention. A copy is made rather than a push, so the
   * caller's row list survives the call and a screen may keep rendering it.
   */
  function unionRow(anchor, channel, issues) {
    var existing = stringList(anchor.streams);
    var known = {};
    var rules = parser();
    for (var i = 0; i < existing.length; i++) {
      var canonical = rules.canonicalStreamUrl(existing[i]);
      if (canonical !== null) known[canonical.toLowerCase()] = true;
    }
    var extra = contributedUrls(channel.sources || [], known, issues);
    if (extra.length === 0) return anchor;
    var out = shallowCopy(anchor);
    var streams = existing.concat(extra);
    out.streams = streams;
    // `normChannel` already chose a primary for a row that had one, and appending cannot displace it. The only
    // case this touches is a row that arrived with no usable address, where leaving the derived field empty would
    // hand the screen a cell that toasts "no stream" while holding a playable URL.
    if (!anchor.primaryStream) out.primaryStream = primaryStreamOf(streams);
    return out;
  }

  /**
   * Host-comparator order among the new rows: the lowercased `<` of `api.js:316` (invariant I3 forbids unifying
   * collation across ports).
   *
   * Index-decorated because a Chromium 68 `Array.prototype.sort` is not documented stable, and two rows sharing a
   * name arriving in the opposite order between refreshes is a visible shuffle for no reason.
   */
  function sortByHostName(rows) {
    var indexes = [];
    for (var i = 0; i < rows.length; i++) indexes.push(i);
    indexes.sort(function (left, right) {
      var a = text(rows[left].name).toLowerCase();
      var b = text(rows[right].name).toLowerCase();
      if (a === b) return left < right ? -1 : 1;
      return a < b ? -1 : 1;
    });
    var out = [];
    for (var k = 0; k < indexes.length; k++) out.push(rows[indexes[k]]);
    return out;
  }

  /**
   * Place each new row where the host comparator puts it, leaving the built-in prefix untouched.
   *
   * Ties go to the built-in row, so a minted row can never overtake a same-named row the user already sees.
   */
  function insertMinted(minted, rows) {
    if (minted.length === 0) return rows;
    var out = [];
    var next = 0;
    for (var i = 0; i < rows.length; i++) {
      var rowName = text(rows[i].name).toLowerCase();
      while (next < minted.length && text(minted[next].name).toLowerCase() < rowName) {
        out.push(minted[next]);
        next += 1;
      }
      out.push(rows[i]);
    }
    for (var t = next; t < minted.length; t++) out.push(minted[t]);
    return out;
  }

  /**
   * Join today's built-in rows with whatever the state would contribute.
   *
   * `input` is `{ channels, state }`. A missing state means "no usable document" — absent, undecodable, or
   * refused by the persistence seam. That is the identity case: the caller's own array comes back, which makes
   * corrupt-document neutrality a property of this function rather than a promise about its caller.
   */
  function compose(input) {
    var settings = input || {};
    // The neutrality case returns the caller's array, not a copy: a screen that keeps its list keeps the same
    // list, and the suite pins that no element was replaced.
    var built = Array.isArray(settings.channels) ? settings.channels : [];
    var state = settings.state === null || settings.state === undefined ? null : settings.state;

    // The fold gap is a fact about the built-in names, not about the join, so it is measured on every path.
    var issues = foldGapIssues(built);
    if (state === null) return { rows: built, issues: issues };

    var registered = catalog().registerBuiltIn(built, {
      playlistId: BUILT_IN_PLAYLIST_ID,
      providerNamespace: BUILT_IN_PROVIDER_NAMESPACE
    });
    var merged = mergeState(state, registered, built.length);
    var view = catalog().build(merged);
    var anchored = anchorIndexes(built, merged.members);

    // Which built-in row, if any, each channel belongs to. A channel reaches a row through the member the
    // adapter minted from it, so the join follows recorded identity rather than name similarity.
    var channelForRow = {};
    for (var c = 0; c < view.length; c++) {
      var index = smallestAnchor(view[c].memberIds || [], anchored);
      if (index === null) continue;
      // One channel per built row. A second channel claiming the same row would otherwise duplicate it, and
      // duplicating a row the user has always seen once is not something a display layer may do.
      if (!hasOwn(channelForRow, index)) channelForRow[index] = view[c];
    }

    var rows = [];
    for (var i = 0; i < built.length; i++) {
      var channel = hasOwn(channelForRow, i) ? channelForRow[i] : null;
      rows.push(channel === null ? built[i] : unionRow(built[i], channel, issues));
    }

    var claimed = {};
    var claimedKeys = Object.keys(channelForRow);
    for (var k = 0; k < claimedKeys.length; k++) claimed[text(channelForRow[claimedKeys[k]].channelId)] = true;
    var minted = [];
    for (var v = 0; v < view.length; v++) {
      if (hasOwn(claimed, text(view[v].channelId))) continue;
      var row = rowForChannel(view[v], issues);
      if (row) minted.push(row);
    }

    return { rows: insertMinted(sortByHostName(minted), rows), issues: issues };
  }

  CC.liveSourceComposer = {
    builtInPlaylistId: BUILT_IN_PLAYLIST_ID,
    builtInProviderNamespace: BUILT_IN_PROVIDER_NAMESPACE,
    issueSecretRefusal: ISSUE_SECRET_REFUSAL,
    issueFoldGap: ISSUE_FOLD_GAP,
    compose: compose
  };
})();
