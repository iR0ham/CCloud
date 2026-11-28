import 'builtin_catalog_adapter.dart';
import 'live_catalog.dart' show liveNameKey, m3uDisplayName;
import 'live_contracts.dart';
import 'models.dart' show LiveTvChannel;
import 'playlist_parser.dart' show canonicalStreamUrl, isSensitiveUrl;
import 'unified_catalog.dart' show buildUnifiedChannels;

// Behaviour-neutral live row composer (task B4-3 slice S1).
//
// The Swift half is `Sources/Core/LiveSourceComposer.swift`, the JavaScript half is
// `webos_app/app/js/live_source_composer.js`, and all three read the same bytes from
// `Tests/fixtures/live-composer/composer_cases.json`. S1 adds the join without adding a call site: nothing in
// the shipping app imports this file yet. What it answers is the question S2 has to ask at the live screens —
// "today's built-in row list, plus whatever the stored catalog would contribute, in the row type the screens
// already render" — and it must answer it with today's list identical whenever the stored document is absent,
// empty, or unreadable. That neutrality claim, not the merge, is what the suites pin.
//
// The pipeline, in the order that keeps each stage's contract intact:
//
// 1. [registerBuiltInChannels] turns the host rows into members and sources. That adapter is the only bridge
//    between the built-in list and the catalog, so the composer calls it rather than restating its recipes.
// 2. Registered members are appended to the stored rows, deduplicated by the provider identity the adapter
//    writes (`playlistId` + `providerNamespace` + `providerChannelId`) rather than by `memberId`. A stored row
//    always wins, so a document that already carries the built-in half keeps its own ids — which is also what
//    lets the shared fixture name a built-in member literally instead of making three ports reproduce a
//    `stableKeyHash` digest. A folded member's sources are retargeted onto the survivor, because the view drops
//    a source whose member is unknown, and deduplicated by (member, address) rather than `sourceId`.
// 3. An enabled `builtin:live` playlist record is injected only when the state carries none. Without a record
//    the view hides every built-in member (`unified_catalog.dart` gates members on an enabled playlist), so the
//    list a user has always seen would vanish. The injection is forced by neutrality, and it is not the open
//    owner decision about an enable-flag default: a record the user did write is never overwritten.
// 4. [buildUnifiedChannels] is called, not reimplemented. Grouping, association order and source priority are
//    its rules; the composer reads them out of its result instead of deriving them a second time.
// 5. The result is projected back onto host rows. A channel containing a built-in member adds its addresses to
//    that row; a channel with no built-in half becomes one new row.
//
// Two asymmetries inside step 5 are deliberate:
//
// * An anchored row keeps its own stream text. The catalog stores a canonicalized address, which can differ in
//   case or default port from what the provider wrote, and today's player is handed the provider's text — so
//   normalizing it here would be exactly the behaviour change S2 must decide on. Deduplication compares
//   canonical forms, so a re-spelled origin does not become a second entry.
// * A credential-bearing address is refused only among the addresses being added. One already in the built-in
//   list is today's behavior; one arriving from the catalog would be a new plaintext address handed to the
//   playback request and shown by the copy-address action, so it is dropped and counted instead.
//
// [issues] carries §18.5's measurement rather than a verdict. The composer must not fold-normalize built-in
// names, so `liveNameKey(name)` and the same fold over `m3uDisplayName(name)` are allowed to differ; each
// difference is reported as one `builtinFoldGap`. That is a known-gap count for the reports, never a production
// failure, and with no call site yet it cannot fail anything.
//
// Ordering is the host comparator, never the catalog's `userOrder`-then-appearance order (invariant I3). The
// built-in prefix keeps the order the fetch already produced and new rows are inserted where that comparator
// puts them, so the function is a literal identity when the state adds nothing. Sorting the whole list instead
// would let an unstable sort swap two same-named rows between refreshes — Dart's `List.sort` is not stable —
// which is a behaviour change hiding inside a "no-op" path.

/// Issue codes the composer emits, spelled like `playlist_parser.dart` spells its own.
///
/// `secretStorageUnavailable` is that parser's existing refusal word, reused so one condition has one name
/// across the parse and display paths. `builtinFoldGap` is the only code this file owns. Both are counted by
/// name in the shared fixture, on all three ports.
abstract final class LiveComposerIssueCode {
  static const String secretRefusal = 'secretStorageUnavailable';
  static const String foldGap = 'builtinFoldGap';
}

/// The built-in list's playlist and provider identity, mirroring the adapter call sites rather than inventing a
/// fourth spelling of either.
abstract final class LiveSourceComposer {
  static const String builtInPlaylistId = 'builtin:live';
  static const String builtInProviderNamespace = 'famelack';
}

/// A composed row list with the diagnostics that explain what it left out.
class ComposedLiveRows {
  const ComposedLiveRows({required this.rows, required this.issues});

  final List<LiveTvChannel> rows;
  final List<CatalogIssue> issues;
}

/// Join today's built-in rows with whatever [state] would contribute, and report the rows only.
///
/// A null [state] means "no usable document" — absent, undecodable, or refused by the persistence seam. That is
/// the identity case: [built] comes back as it went in, which makes corrupt-document neutrality a property of
/// this function rather than a promise about its caller.
List<LiveTvChannel> composeLiveRows(
  List<LiveTvChannel> built,
  LiveCatalogState? state,
) => composeLiveRowsWithIssues(built, state).rows;

/// [composeLiveRows] plus the §18.5 measurements, so one pass answers both questions the suites ask.
///
/// The pinned slice-S1 contract is the rows-only shape above; the shared fixture also counts issues, and the
/// alternatives — a second pass, or dropping the issue assertions on this port — would make the three suites
/// prove different things from one fixture.
ComposedLiveRows composeLiveRowsWithIssues(
  List<LiveTvChannel> built,
  LiveCatalogState? state,
) {
  // The fold gap is a fact about the built-in names, not about the join, so it is measured on every path.
  final issues = _foldGapIssues(built);
  if (state == null) {
    return ComposedLiveRows(rows: built, issues: issues);
  }
  return ComposedLiveRows(rows: _composeRows(built, state, issues), issues: issues);
}

/// One issue per built-in row whose raw name folds differently from its noise-stripped display name.
///
/// This is the measurement §18.5 asks for in place of a normalization: the built-in path keeps provider text
/// verbatim, so such a row can never produce a merge candidate for a clean-named parsed sibling. The gap stays
/// open (task B4 owns it); what changes is that it is now counted.
List<CatalogIssue> _foldGapIssues(List<LiveTvChannel> built) {
  final issues = <CatalogIssue>[];
  for (final row in built) {
    if (liveNameKey(row.name) == liveNameKey(m3uDisplayName(row.name))) continue;
    issues.add(const CatalogIssue(
      code: LiveComposerIssueCode.foldGap,
      message:
          'Built-in name keeps a quality token, so its match key differs from the playlist-path display name',
    ));
  }
  return issues;
}

List<LiveTvChannel> _composeRows(
  List<LiveTvChannel> built,
  LiveCatalogState state,
  List<CatalogIssue> issues,
) {
  final registered = registerBuiltInChannels(
    channels: built,
    playlistId: LiveSourceComposer.builtInPlaylistId,
    providerNamespace: LiveSourceComposer.builtInProviderNamespace,
  );
  final merged = _mergeState(
    stored: state,
    registered: registered,
    builtInCount: built.length,
  );
  final view = buildUnifiedChannels(merged);
  final anchored = _anchorIndexes(built, merged.members);

  // Which built-in row, if any, each channel belongs to. A channel reaches a row through the member the
  // adapter minted from it, so the join follows recorded identity rather than name similarity.
  final channelForRow = <int, LogicalChannel>{};
  for (final channel in view) {
    final index = _smallestAnchor(channel.memberIds, anchored);
    if (index == null) continue;
    // One channel per built row. A second channel claiming the same row would otherwise duplicate it, and
    // duplicating a row the user has always seen once is not something a display layer may do.
    channelForRow.putIfAbsent(index, () => channel);
  }

  final rows = <LiveTvChannel>[];
  for (var index = 0; index < built.length; index++) {
    final row = built[index];
    final channel = channelForRow[index];
    rows.add(channel == null ? row : _unionRow(row, channel, issues));
  }

  final claimed = <String>{
    for (final channel in channelForRow.values) channel.channelId,
  };
  final minted = <LiveTvChannel>[];
  for (final channel in view) {
    if (claimed.contains(channel.channelId)) continue;
    final row = _rowFor(channel, issues);
    if (row != null) minted.add(row);
  }
  return _insertMinted(minted: _sortByHostName(minted), rows: rows);
}

/// The built-in row each merged member was registered from, as an index into the caller's list.
///
/// Matching uses the fields the adapter itself wrote — `displayName` is the row's name verbatim and `tvgId` its
/// trimmed provider id — because re-deriving the `name:`-prefix fallback here would put a second copy of that
/// recipe in the codebase, which is how a refresh ends up with two members for one station.
Map<String, int> _anchorIndexes(
  List<LiveTvChannel> built,
  List<ChannelMember> members,
) {
  final rowsByTvgId = <String, int>{};
  final rowsByName = <String, int>{};
  for (var index = 0; index < built.length; index++) {
    final row = built[index];
    final trimmed = row.nanoid.trim();
    if (trimmed.isNotEmpty) rowsByTvgId.putIfAbsent(trimmed, () => index);
    rowsByName.putIfAbsent(row.name, () => index);
  }

  final anchored = <String, int>{};
  for (final member in members) {
    if (member.playlistId != LiveSourceComposer.builtInPlaylistId ||
        member.providerNamespace != LiveSourceComposer.builtInProviderNamespace ||
        anchored.containsKey(member.memberId)) {
      continue;
    }
    final tvgId = member.tvgId;
    final byId = tvgId == null ? null : rowsByTvgId[tvgId];
    final index = byId ?? rowsByName[member.displayName];
    if (index != null) anchored[member.memberId] = index;
  }
  return anchored;
}

int? _smallestAnchor(List<String> memberIds, Map<String, int> anchored) {
  int? best;
  for (final memberId in memberIds) {
    final index = anchored[memberId];
    if (index == null) continue;
    if (best == null || index < best) best = index;
  }
  return best;
}

/// Members and sources the document does not already carry, plus the built-in playlist record if absent.
///
/// Appending rather than replacing keeps every id the state refers to through `logicalIdByMemberId` and
/// `associations` valid, so the view's grouping — which is the user's own decision — survives the join.
LiveCatalogState _mergeState({
  required LiveCatalogState stored,
  required RegisteredBuiltInCatalog registered,
  required int builtInCount,
}) {
  // Provider identity, not `memberId`, decides whether two rows are the same station. A registered member whose
  // provider key is already in the document is that station, so the stored row keeps its own id and the minted
  // one disappears — which is also what lets the shared fixture name a built-in member literally instead of
  // making three ports reproduce a `stableKeyHash` digest.
  final survivorForRegisteredId = <String, String>{};
  final membersByProviderKey = <String, String>{
    for (final member in stored.members) _providerKey(member): member.memberId,
  };
  final members = <ChannelMember>[...stored.members];
  for (final member in registered.members) {
    final key = _providerKey(member);
    final existing = membersByProviderKey[key];
    if (existing != null) {
      survivorForRegisteredId[member.memberId] = existing;
      continue;
    }
    membersByProviderKey[key] = member.memberId;
    members.add(member);
  }

  // A source follows the member it was registered from, so a folded member's addresses are retargeted onto the
  // survivor instead of being dropped: `buildUnifiedChannels` discards a source whose member is unknown, and one
  // new Famelack URL would otherwise vanish whenever the stored document already named that station. Both id
  // fields move together because the record is meant to describe the surviving member; the view groups by
  // member, not by these fields, so the remap only keeps the ephemeral state internally consistent.
  //
  // The dedup key is (member, canonical address) rather than `sourceId`: the same address under two spellings of
  // the row id is one address, and appending it twice would duplicate a playable source in the channel the user
  // sees.
  final seenAddresses = <String>{
    for (final source in stored.sources) _addressKey(source),
  };
  final sources = <ChannelSourceRecord>[...stored.sources];
  for (final source in registered.sources) {
    final survivor = survivorForRegisteredId[source.memberId];
    final record = survivor == null ? source : _retarget(source, survivor);
    if (!seenAddresses.add(_addressKey(record))) continue;
    sources.add(record);
  }

  final hasBuiltInRecord = stored.playlists.any(
    (PlaylistRecord playlist) =>
        playlist.playlistId == LiveSourceComposer.builtInPlaylistId,
  );
  final playlists = <PlaylistRecord>[...stored.playlists];
  if (!hasBuiltInRecord) {
    playlists.add(PlaylistRecord(
      playlistId: LiveSourceComposer.builtInPlaylistId,
      name: 'CCloud',
      sourceType: PlaylistSourceType.builtIn,
      locationRef: LiveSourceComposer.builtInPlaylistId,
      // See the header: an enabled record is what keeps today's list visible. `createdAt` is the epoch rather
      // than `DateTime.now()` because this record is a view precondition, not an event, and an impure timestamp
      // would make the composed output differ between two runs of the same bytes.
      enabled: true,
      createdAt: DateTime.utc(1970),
      refreshStatus: PlaylistRefreshStatus.ready,
      channelCount: builtInCount,
      parsingVersion: 1,
    ));
  }

  return LiveCatalogState(
    schemaVersion: stored.schemaVersion,
    playlists: List<PlaylistRecord>.unmodifiable(playlists),
    members: List<ChannelMember>.unmodifiable(members),
    sources: List<ChannelSourceRecord>.unmodifiable(sources),
    associations: stored.associations,
    preferences: stored.preferences,
    recentWatches: stored.recentWatches,
    logicalIdByMemberId: stored.logicalIdByMemberId,
  );
}

String _providerKey(ChannelMember member) =>
    '${member.playlistId}\n${member.providerNamespace}\n${member.providerChannelId}';

String _addressKey(ChannelSourceRecord source) =>
    '${source.memberId}\n${source.streamUrl.trim().toLowerCase()}';

/// A copy of [source] that belongs to [memberId], field for field.
///
/// [ChannelSourceRecord] is immutable, and copying each field here rather than round-tripping through the codec
/// keeps the secret-omission rule out of this file: a record that carried a `streamSecretRef` still carries it.
ChannelSourceRecord _retarget(ChannelSourceRecord source, String memberId) =>
    ChannelSourceRecord(
      sourceId: source.sourceId,
      channelId: memberId,
      memberId: memberId,
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
      lastErrorCode: source.lastErrorCode,
    );

/// The anchor row, plus only the addresses it does not already list, in catalog priority order.
///
/// Every other field stays the anchor's own: no catalog member can state a geo-block for a row the provider
/// already described, and inheriting one would be an invention.
LiveTvChannel _unionRow(
  LiveTvChannel anchor,
  LogicalChannel channel,
  List<CatalogIssue> issues,
) {
  final existing = anchor.streams;
  final known = <String>{};
  for (final url in existing) {
    final canonical = canonicalStreamUrl(url);
    if (canonical != null) known.add(canonical.toLowerCase());
  }
  final extra = _contributedUrls(channel.sources, known, issues);
  return extra.isEmpty ? anchor : anchor.copyWithStreams([...existing, ...extra]);
}

/// A catalog channel with no built-in half becomes one row carrying exactly what the catalog states.
///
/// The row identity is the logical channel id, so it is never empty and the display layer's key stays unique. A
/// streamless channel yields no row: today's fetch already refuses a streamless entry, so a channel that cannot
/// play anything would be a new dead cell rather than preserved behaviour.
LiveTvChannel? _rowFor(LogicalChannel channel, List<CatalogIssue> issues) {
  final urls = _contributedUrls(channel.sources, <String>{}, issues);
  if (urls.isEmpty) return null;
  return LiveTvChannel(
    nanoid: channel.channelId,
    name: channel.displayName,
    streams: urls,
    languages: channel.languages,
    // The host row holds a plain string; the catalog's comparable form is uppercase-or-null, and an unknown
    // country must not render as a country named "".
    country: channel.countryCode ?? '',
    // Nothing in the catalog models a geo-block at all — `ChannelMember` carries no such field — and the
    // adapter's answer to a claim it has no evidence for is null rather than a guess. A row the provider never
    // described cannot be rendered as blocked.
    isGeoBlocked: false,
  );
}

/// The addresses a channel contributes that are new, playable-shaped, and credential-free.
///
/// [known] grows as it is consumed, so two sources spelling one address contribute it once even when they arrive
/// in the same pass.
List<String> _contributedUrls(
  List<ChannelSourceRecord> sources,
  Set<String> known,
  List<CatalogIssue> issues,
) {
  final urls = <String>[];
  for (final source in sources) {
    // A disabled source stays in the channel's own list — the user manages it there — but this output is the
    // playable row list, and eligibility is `enabled`. Adding a turned-off address here would undo the toggle.
    if (!source.enabled) continue;
    // A secret-backed source carries no address in the document at all, so there is nothing to add and no
    // refusal to report; the recovery chain resolves it through the secret store in Phase C.
    if (source.streamSecretRef != null) continue;
    final trimmed = source.streamUrl.trim();
    if (trimmed.isEmpty) continue;
    final canonical = canonicalStreamUrl(trimmed);
    if (canonical == null) continue;
    if (isSensitiveUrl(trimmed)) {
      // No address text in the message: an issue list is allowed to reach a log, and the whole point of the
      // refusal is that the credential does not travel.
      issues.add(const CatalogIssue(
        code: LiveComposerIssueCode.secretRefusal,
        message: 'Credential-bearing address withheld from the composed row list',
      ));
      continue;
    }
    if (!known.add(canonical.toLowerCase())) continue;
    urls.add(trimmed);
  }
  return urls;
}

/// Host-comparator order among the new rows: `toLowerCase().compareTo`, which is what `live_catalog.dart`'s own
/// built-in merge uses on this port (invariant I3 forbids unifying collation across ports).
///
/// Index-decorated because Dart's `List.sort` is not documented stable, and two rows sharing a name arriving in
/// the opposite order between refreshes is a visible shuffle for no reason.
List<LiveTvChannel> _sortByHostName(List<LiveTvChannel> rows) {
  final indexes = List<int>.generate(rows.length, (int index) => index);
  indexes.sort((int left, int right) {
    final order = rows[left].name
        .toLowerCase()
        .compareTo(rows[right].name.toLowerCase());
    return order != 0 ? order : left.compareTo(right);
  });
  return [for (final index in indexes) rows[index]];
}

/// Place each new row where the host comparator puts it, leaving the built-in prefix untouched.
///
/// Ties go to the built-in row, so a minted row can never overtake a same-named row the user already sees.
List<LiveTvChannel> _insertMinted({
  required List<LiveTvChannel> minted,
  required List<LiveTvChannel> rows,
}) {
  if (minted.isEmpty) return rows;
  final out = <LiveTvChannel>[];
  var next = 0;
  for (final row in rows) {
    while (next < minted.length &&
        minted[next].name.toLowerCase().compareTo(row.name.toLowerCase()) < 0) {
      out.add(minted[next]);
      next++;
    }
    out.add(row);
  }
  out.addAll(minted.sublist(next));
  return out;
}
