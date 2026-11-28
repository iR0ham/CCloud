import Foundation

// Live catalog persistence seam (multi-source foundation, task B4-2S).
//
// This is the Swift half of `webos_app/app/js/live_catalog_store.js`. The B1–B3 libraries can build, decode
// and merge a `LiveCatalogState`, and `LiveCatalogMigration` (Sources/Core/LiveTVCatalogCodec.swift:349)
// already owns the document rules, but nothing on any port had a *path*: `LiveCatalogMigration` has no
// production caller and touches no file. This type is that path, and it stays thin on purpose — it decides
// only where the document lives and what a read or write is allowed to do to it. All schema, timestamp and
// secret-refusal rules belong to the codec, so a future v1-to-v2 migration changes one function there instead
// of every caller here.
//
// Three rules, each of which the webOS suite pins and the checks in `Tests/live-foundation/main.swift` mirror:
//
//  1. **A load never writes.** Reading a stored document may seed the logical-id map in memory
//     (`seedSingletonChannels`, Sources/Core/LiveTVChannelIdentity.swift:300) so the catalog a user just
//     restored is mergeable, but it must not create, touch or rewrite the file. A read that persists turns a
//     viewer into a mutation, and a launch after a partially-failed write would then overwrite good data.
//  2. **An unreadable document is reported, never cleared.** A corrupt or future-version document yields
//     `.corrupt` with the bytes left intact, because the only cheaper-looking alternative — decoding to an
//     empty state — is indistinguishable from a user who genuinely has no playlists, and the next save would
//     then destroy a catalog that was fine all along.
//  3. **A save proves the write took.** `Data.write` can fail on a read-only volume, a full disk or a denied
//     directory, and a caller that ignores the outcome shows the user a catalog that vanishes on next launch.
//     So the bytes are re-read and compared, and a mismatch is `.refused`.
//
// Deliberately actor-neutral and synchronous: it holds no mutable state of its own, only a `URL`, so it can be
// constructed inside a background task and it never needs a lock. B4-3's consumer decides *where* to call it;
// a 50k-member document is not something to decode on the main actor, and that call belongs to the screen
// wiring rather than to this type.

/// What a store operation concluded. `ok` and `absent` both hand back a usable state; `corrupt` deliberately
/// does not, so no caller can render a cleared catalog by forgetting to check.
enum LiveCatalogStoreStatus: String, Equatable, Sendable {
    case ok
    case absent
    case corrupt
    case saved
    case refused
}

/// Outcome of one store call: a status, the state when there is a trustworthy one, and a message that is safe
/// to show or log. The message never embeds stored file contents, because a catalog document holds user URLs
/// and a diagnostic that prints a fragment of it would put those into logs and artefacts.
struct LiveCatalogStoreOutcome: Equatable, Sendable {
    let status: LiveCatalogStoreStatus
    let state: LiveCatalogState?
    let message: String?

    var isUsable: Bool { state != nil }
}

/// File-backed `LiveCatalogState` storage, following the directory the media stores already use
/// (`Sources/Core/Stores.swift:44-53`: Application Support/`CCloudMac`), so a second data home for the same
/// app never appears.
struct LiveCatalogStore: Sendable {
    static let fileName = "live_catalog.json"

    let fileURL: URL
    private var directory: URL { fileURL.deletingLastPathComponent() }

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// The production location: Application Support/`CCloudMac/live_catalog.json`, the directory the favorites
    /// and history documents already live in (`Stores.swift:44-53`). The directory is created lazily by `save`,
    /// never by `load`, so asking where the document lives cannot leave a directory behind on a machine that
    /// never had one.
    static func standard() -> LiveCatalogStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return LiveCatalogStore(fileURL: base
            .appendingPathComponent("CCloudMac", isDirectory: true)
            .appendingPathComponent(fileName))
    }

    // MARK: - Read

    var hasStoredDocument: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// Reads and migrates the stored document, then seeds the logical-id map so the result is mergeable.
    /// Never writes, never deletes, and never returns a cleared state for a document it could not read.
    func load() -> LiveCatalogStoreOutcome {
        guard hasStoredDocument else {
            return LiveCatalogStoreOutcome(
                status: .absent,
                state: LiveCatalogStore.seeded(LiveCatalogState.empty),
                message: nil
            )
        }
        guard let data = try? Data(contentsOf: fileURL) else {
            return LiveCatalogStoreOutcome(
                status: .corrupt,
                state: nil,
                message: "live catalog document could not be read"
            )
        }
        do {
            return LiveCatalogStoreOutcome(
                status: .ok,
                state: LiveCatalogStore.seeded(try LiveCatalogMigration.migrate(data)),
                message: nil
            )
        } catch {
            return LiveCatalogStoreOutcome(status: .corrupt, state: nil, message: LiveCatalogStore.message(for: error))
        }
    }

    // MARK: - Write

    /// Encodes, writes atomically, then re-reads and compares. Returns `.refused` — with the caller's state
    /// intact and nothing pretending it persisted — if encoding refuses the state or the bytes do not land.
    func save(_ state: LiveCatalogState) -> LiveCatalogStoreOutcome {
        do {
            let data = try LiveCatalogMigration.encode(state)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try data.write(to: fileURL, options: .atomic)
            } catch {
                return LiveCatalogStoreOutcome(
                    status: .refused,
                    state: nil,
                    message: "live catalog write did not reach storage"
                )
            }
            guard let written = try? Data(contentsOf: fileURL), written == data else {
                return LiveCatalogStoreOutcome(
                    status: .refused,
                    state: nil,
                    message: "live catalog write did not reach storage"
                )
            }
            return LiveCatalogStoreOutcome(status: .saved, state: state, message: nil)
        } catch {
            // Only the encoder can reach here: the write branch answers for itself above.
            return LiveCatalogStoreOutcome(status: .refused, state: nil, message: LiveCatalogStore.message(for: error))
        }
    }

    /// Removes the document. An already-absent file counts as success, because the caller's goal — no stored
    /// catalog — holds either way; a removal that fails for another reason reports false so a screen cannot
    /// claim a wipe it did not perform.
    func clear() -> Bool {
        guard hasStoredDocument else { return true }
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            return false
        }
        return !hasStoredDocument
    }

    // MARK: - Shared helpers

    /// The seed happens on read rather than on registration so that every existing document, including one
    /// written by an earlier build, becomes mergeable without a migration step or a write.
    static func seeded(_ state: LiveCatalogState) -> LiveCatalogState {
        seedSingletonChannels(state)
    }

    /// One shared message for a schema refusal — the text the Dart codec throws and the webOS contracts throw
    /// (`LiveCatalogSchemaError.message`, Sources/Core/LiveTVCatalogCodec.swift:44) — and a fixed message for
    /// everything else, so no decoded value leaks out of an error string.
    static func message(for error: Error) -> String {
        if let schema = error as? LiveCatalogSchemaError { return schema.message }
        return "live catalog document could not be decoded"
    }
}
