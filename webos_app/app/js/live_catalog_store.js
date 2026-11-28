/* Live catalog persistence seam (webOS, task B4-2).
 *
 * `playlist_contracts.js` encodes and decodes a catalog document but deliberately touches no storage
 * (`playlist_contracts.js:21` records that split), and `channel_identity.js` seeds a logical-id map but
 * deliberately decides no load-time policy (`channel_identity.js:392`). This module is where those two
 * halves meet: it owns the storage key, turns text into a mergeable state, and refuses to destroy a
 * document it cannot read.
 *
 * Three rules carry the whole design, and each one exists because breaking it loses user data:
 *
 * 1. **A load never writes.** Reading is what the app does on every start, so if it also saved, a bug in
 *    seeding or a downgraded build would rewrite the user's document on launch. Seeding is applied to the
 *    returned state only; the stored text stays exactly as it was until a user action causes a save.
 * 2. **An unreadable document is reported, not cleared.** `decodeState` throws for malformed text, a wrong
 *    root type, or a `schemaVersion` this build does not understand (`playlist_contracts.js:600-624`).
 *    Returning an empty state in that case would look like "the user has no playlists", and the next save
 *    would persist that emptiness over the real catalog. So `load` answers `status: 'corrupt'` with
 *    `state: null`, and the caller keeps its existing list.
 * 3. **A save proves the write took.** `CC.store.set` swallows a `localStorage` failure, including quota
 *    (`util.js:50-52`), so a caller cannot tell success from a silently dropped write. This module reads the
 *    value back and reports what it saw, which is the only evidence available without a device.
 *
 * Plain ES2017 (`var`, function expressions, explicit index loops) because the runtime is webOS 4 /
 * Chromium 68, and `Tests/webos/live_catalog_store.test.js` enforces that ceiling by scanning this file's
 * text; `node --check` alone would accept newer syntax. This module also goes through `CC.store` rather than
 * touching `localStorage` itself, so the storage binding stays in one file that a suite can exercise with a
 * fake, exactly as the other four B3 modules keep host APIs out of the library layer.
 */
window.CC = window.CC || {};

(function () {
  var CC = window.CC;

  // The key within the app's own namespace: `CC.store` prefixes it with `ccloud.` (`util.js:41`), so the
  // document lands at `ccloud.liveCatalog`, beside `ccloud.settings`, `ccloud.favorites` and
  // `ccloud.history`. A new key rather than a reuse is what keeps a catalog document from ever being read as
  // a favorites list on a build that predates it.
  var KEY = 'liveCatalog';

  // The four verdicts a caller branches on. They are strings rather than an enum because a screen renders
  // text from them and the suite compares them literally on all three ports.
  var STATUS_OK = 'ok';
  var STATUS_ABSENT = 'absent';
  var STATUS_CORRUPT = 'corrupt';
  var STATUS_SAVED = 'saved';
  var STATUS_REFUSED = 'refused';

  function verdict(status, state, message) {
    return { status: status, state: state, message: message === undefined ? null : message };
  }

  // Sibling modules are read at call time, not captured at load time: `index.html` decides the real load
  // order on a TV, and a stale local binding here would make that order a second thing to get right.
  function contracts() {
    return CC.playlistContracts;
  }

  function identity() {
    return CC.channelIdentity;
  }

  // Seeding turns a freshly registered catalog into a mergeable one, because `associate` names a preferred
  // channel by a key of `logicalIdByMemberId` and registration does not populate that map. A state that
  // already carries a mapping is returned untouched by the same call, so this is safe on every load.
  function seedMergeable(state) {
    return identity().seedSingletonChannels(state);
  }

  // The error text is what a diagnostic log needs; `decodeState` throws `Error('...')` with the message the
  // Dart and Swift codecs use, so the string is compared rather than the object type.
  function messageOf(error) {
    return error && error.message ? String(error.message) : 'unreadable live catalog document';
  }

  /**
   * Reads the persisted catalog without writing anything.
   *
   * `absent` and `ok` both return a state a screen may use; only `corrupt` returns `state: null`, and the
   * stored bytes are left in place in that case so a later build that understands the document can still
   * recover the user's playlists and associations.
   */
  function load() {
    var raw = CC.store.get(KEY, null);
    if (raw === null || raw === undefined) {
      return verdict(STATUS_ABSENT, seedMergeable(contracts().emptyState()), null);
    }
    // A JSON object stored under this key is a different shape than the codec contract, and decoding it
    // would either throw or invent data; reporting it is the honest answer.
    if (typeof raw !== 'string') {
      return verdict(STATUS_CORRUPT, null, 'live catalog document is not JSON text');
    }
    var state;
    try {
      // `migrate` rather than `decodeState` because it is the port's own stored-document entry point: it
      // maps an empty string to the canonical v1 state and forwards everything else to the decoder, so a
      // build that later learns a v1-to-v2 upgrade changes one function instead of every caller.
      state = contracts().migrate(raw);
    } catch (error) {
      return verdict(STATUS_CORRUPT, null, messageOf(error));
    }
    return verdict(STATUS_OK, seedMergeable(state), null);
  }

  /**
   * Persists one catalog state and reports whether the document in storage is now exactly that state.
   *
   * Encoding is validated before the write, so a state this build cannot describe never replaces a readable
   * document. A write that `localStorage` refused (quota, private mode) is detected by the read-back and
   * reported as `refused`, which is the caller's signal to keep the previous in-memory state rather than
   * assume the user's decision was recorded.
   */
  function save(state) {
    var text;
    try {
      text = contracts().encodeState(state);
    } catch (error) {
      return verdict(STATUS_REFUSED, null, messageOf(error));
    }
    CC.store.set(KEY, text);
    if (CC.store.get(KEY, null) !== text) {
      return verdict(STATUS_REFUSED, null, 'live catalog write did not reach storage');
    }
    return verdict(STATUS_SAVED, state, null);
  }

  /**
   * Removes the persisted document, which is what an explicit "forget this catalog" action means.
   *
   * Unlike an implicit clear-on-read-corruption, this is a user decision: it returns whether storage now
   * really holds nothing under the key, so a caller cannot report success on a TV that rejected the write.
   */
  function clear() {
    CC.store.remove(KEY);
    return CC.store.get(KEY, null) === null;
  }

  /** True when a document exists, without decoding it. Lets a screen distinguish "empty" from "unreadable". */
  function hasStored() {
    return CC.store.get(KEY, null) !== null;
  }

  CC.liveCatalogStore = {
    key: KEY,
    statusOk: STATUS_OK,
    statusAbsent: STATUS_ABSENT,
    statusCorrupt: STATUS_CORRUPT,
    statusSaved: STATUS_SAVED,
    statusRefused: STATUS_REFUSED,
    load: load,
    save: save,
    clear: clear,
    hasStored: hasStored
  };
})();
