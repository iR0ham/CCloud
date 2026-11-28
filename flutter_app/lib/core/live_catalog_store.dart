import 'package:shared_preferences/shared_preferences.dart';

import 'channel_identity.dart';
import 'live_contracts.dart';

/// What one [LiveCatalogStore] call concluded.
///
/// The five verdicts are the same five words the webOS seam exports
/// (`webos_app/app/js/live_catalog_store.js`) and the Swift mirror declares
/// (`Sources/Core/LiveCatalogStore.swift`), because a support log or a translation should not have to learn
/// three vocabularies for one behaviour. `absent` and `ok` both carry a usable state; `corrupt` and `refused`
/// deliberately carry none, so a screen cannot render a cleared catalog by forgetting to check.
enum LiveCatalogStoreStatus { ok, absent, corrupt, saved, refused }

/// Outcome of a single read or write: a status, the state when there is a trustworthy one, and a message that
/// is safe to show or log. The message never embeds stored document content, because a catalog holds the
/// user's playlist URLs and a diagnostic that echoed a fragment would put those into logs and artefacts.
class LiveCatalogStoreOutcome {
  const LiveCatalogStoreOutcome(this.status, {this.state, this.message});

  final LiveCatalogStoreStatus status;
  final LiveCatalogState? state;
  final String? message;

  bool get isUsable => state != null;
}

/// File-backed persistence for the schema-v1 live catalog on Android, iOS, Windows, macOS-in-Flutter and
/// Linux — the Dart half of task B4-2.
///
/// `LiveCatalogMigration` (`live_contracts.dart:412`) has owned the document rules since task B1-D with no
/// production caller and no storage key, so nothing on this port could persist a catalog. This class is that
/// key and those three rules, mirrored from `webos_app/app/js/live_catalog_store.js` and
/// `Sources/Core/LiveCatalogStore.swift`:
///
///  1. **A load never writes.** Reading happens on every start, so a read that also saved would let a seeding
///     bug or a downgraded build rewrite the user's document. The logical-id seed is applied in memory only.
///  2. **An unreadable document is reported, never cleared.** A corrupt or future-version document yields
///     `corrupt` with the stored text left exactly where it is. The tempting shortcut — decode failures return
///     an empty state — is what `LinkHealthStore._load` does at `link_health.dart:105` for a cache it can
///     afford to lose; a live catalog is not that, because an empty state followed by the next save destroys
///     playlists, associations and preferences that were fine all along.
///  3. **A write is proven, not assumed.** `SharedPreferences.setString` resolves to a bool and can throw on a
///     platform whose storage is full or blocked, and a caller that ignores that shows the user a catalog that
///     vanishes on relaunch. So the value is re-read and compared, and a mismatch is `refused`.
///
/// Each port uses the most honest primitive its storage layer offers for rule 2: Swift asks the filesystem
/// whether a file exists, webOS asks `CC.store` whether the raw prefixed slot is occupied (`util.js:56-62`),
/// and Dart asks `containsKey` — because `getString` would *throw* rather than answer `null` for a key holding
/// an int (`shared_preferences_legacy.dart:127` casts with `as String?`), so presence and type have to be two
/// separate questions here.
///
/// Reads are synchronous and writes are not, which is a platform fact rather than a style choice:
/// `SharedPreferences.getInstance()` is awaited once at startup (`startup_bootstrap.dart:42`), after which
/// reads are in-memory, while every mutation goes back through the plugin. This class holds no mutable state,
/// so it needs no lock, and it decides no policy about *when* to read or write — that is task B4-3's caller.
class LiveCatalogStore {
  LiveCatalogStore(this._prefs);

  /// The document slot, named the way every other persisted value on this port is named
  /// (`ccloud.linkHealth` at `link_health.dart:59`, `ccloud.recentSearchQueries` at `recent_searches.dart:5`).
  /// The plugin adds its own `flutter.` namespace in front of it, so this literal is the app-visible key and
  /// matches the webOS seam's suffix exactly.
  static const String storageKey = 'ccloud.liveCatalog';

  final SharedPreferences _prefs;

  /// True when *something* is stored under the key, without decoding it. Lets a screen tell "this device has
  /// no catalog" apart from "this device has a catalog this build cannot read", which is the distinction
  /// rule 2 exists to preserve.
  bool get hasStoredDocument => _prefs.containsKey(storageKey);

  /// Reads and migrates the stored document, then seeds the logical-id map so the result is mergeable.
  /// Never writes, never removes, and never returns a cleared state for a document it could not read.
  LiveCatalogStoreOutcome load() {
    if (!hasStoredDocument) {
      return LiveCatalogStoreOutcome(
        LiveCatalogStoreStatus.absent,
        state: _seeded(const LiveCatalogState()),
      );
    }
    // `get` returns whatever type is cached and never casts, which is what makes the next question answerable:
    // a bool, an int or a list under this key is a different shape than the codec contract. Decoding it would
    // either throw or invent data, and ignoring it silently would be rule 2 failing quietly.
    final Object? raw = _prefs.get(storageKey);
    if (raw is! String) {
      return const LiveCatalogStoreOutcome(
        LiveCatalogStoreStatus.corrupt,
        message: 'live catalog document is not JSON text',
      );
    }
    try {
      return LiveCatalogStoreOutcome(
        LiveCatalogStoreStatus.ok,
        state: _seeded(LiveCatalogMigration.migrate(raw)),
      );
    } on FormatException catch (error) {
      // The codec's own refusal, which carries the shared `Unsupported live catalog schema` text for a
      // version this build does not know and a precise reason for malformed fields.
      return LiveCatalogStoreOutcome(
        LiveCatalogStoreStatus.corrupt,
        message: error.message,
      );
    } catch (_) {
      return const LiveCatalogStoreOutcome(
        LiveCatalogStoreStatus.corrupt,
        message: 'live catalog document could not be decoded',
      );
    }
  }

  /// Encodes, writes, then asks storage what it holds now. Returns `refused` — with no state handed back, so a
  /// caller cannot assume its decision was recorded — if the codec refuses the state or the document does not
  /// land.
  ///
  /// The re-read goes through `reload()` rather than `get()`, because the plugin updates its in-memory cache
  /// *before* the platform answers (`shared_preferences_legacy.dart:202-210`): a write the storage layer
  /// rejected would still read back perfectly from the cache, and rule 3 would be testing the wrong thing. The
  /// boolean the plugin returns is the other half of the evidence, and the cache is re-synced before answering
  /// either way so a caller that inspects `load()` after a refusal learns what storage really holds.
  Future<LiveCatalogStoreOutcome> save(LiveCatalogState state) async {
    final String text;
    try {
      text = LiveCatalogMigration.encode(state);
    } on FormatException catch (error) {
      return LiveCatalogStoreOutcome(
        LiveCatalogStoreStatus.refused,
        message: error.message,
      );
    }
    bool wrote = false;
    try {
      wrote = await _prefs.setString(storageKey, text);
    } catch (_) {
      wrote = false;
    }
    final bool resynced = await _resync();
    // A platform that cannot re-read leaves the boolean as the only evidence, which is stated rather than
    // hidden: `true` from the plugin means "written, or this platform does not report success or failure".
    final bool landed = resynced ? _prefs.get(storageKey) == text : true;
    if (!wrote || !landed) {
      return _writeRefused();
    }
    return LiveCatalogStoreOutcome(LiveCatalogStoreStatus.saved, state: state);
  }

  /// Removes the document, which is what an explicit "forget this catalog" action means. Returns whether
  /// storage really holds nothing, so a caller cannot report a wipe the platform refused. An already-absent
  /// document counts as success, because the caller's goal holds either way.
  ///
  /// `remove` empties the cache before the platform answers (`shared_preferences_legacy.dart:196-200`), so both
  /// signals are required: the boolean catches a refusal, and the re-sync makes the answer about storage rather
  /// than about this process's intentions.
  Future<bool> clear() async {
    if (!hasStoredDocument) return true;
    bool removed = false;
    try {
      removed = await _prefs.remove(storageKey);
    } catch (_) {
      removed = false;
    }
    await _resync();
    return removed && !hasStoredDocument;
  }

  static LiveCatalogStoreOutcome _writeRefused() => const LiveCatalogStoreOutcome(
    LiveCatalogStoreStatus.refused,
    message: 'live catalog write did not reach storage',
  );

  /// Asks the platform for the current contents so the in-memory cache reflects storage. Returns whether that
  /// round trip worked; a false answer means this build could not verify, and the callers above degrade to the
  /// plugin's own boolean instead of inventing evidence.
  Future<bool> _resync() async {
    try {
      await _prefs.reload();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Seeding happens on read rather than on registration, so every existing document — including one written
  /// by a build that predates task B4-1 — becomes mergeable without a migration step or a write. It is the
  /// library's own rule (`seedSingletonChannels`, `channel_identity.dart:311`), not a copy made here.
  static LiveCatalogState _seeded(LiveCatalogState state) => seedSingletonChannels(state);
}
