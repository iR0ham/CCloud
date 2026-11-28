import Foundation

// Reading and writing the persisted schema-v1 live catalog (multi-source
// foundation, task B1-S).
//
// Swift twin of `flutter_app/lib/core/live_catalog_codec.dart`. Both ports apply
// the same rules, in the same order, and reject the same documents:
//
// * `schemaVersion` is prefighted as an integer before a single record is
//   decoded, so a future or corrupt document can never be half-read into an empty
//   state that the next save would then persist over the user's real catalog;
// * only `supportedSchemaVersion` is understood, and encoding refuses every other
//   version with the same error, so no port can write a document its own reader
//   rejects;
// * v1 is additive, so an absent (or null) `recentWatches`, `sourcePolicy` and
//   source `rendererCapability` gain their canonical defaults on read, while every
//   write includes all three. So does each field the Dart reader already defaults —
//   a playlist's `refreshStatus`, `channelCount` and `parsingVersion`, a member's
//   `languages`, and a preference's `favorite`, `hidden` and
//   `automaticFailoverEnabled` — because the tolerance belongs to the contract, not
//   to whichever port happens to type the field loosely;
// * a source keeps either an address or a secret reference, never both, and a
//   secret-backed source's address is omitted from the document entirely.
//
// One documented difference remains, and B3's agreement test must account for it: a null
// optional field is *omitted* here (synthesized `encodeIfPresent`) where the Dart writer
// emits an explicit null, and `ChannelMember.ordinal` is declared last here but earlier
// in Dart. Both documents read back as the same values, so cross-port comparison is by
// parsed value; comparing raw text would report a difference that is not one.
//
// Fail-closed on purpose: silently clearing state here would destroy playlists,
// associations, favourites and watch history on the next save.

/// The persisted document is not readable by this build.
///
/// The case name is this port's typed equivalent of the Dart codec's thrown
/// `FormatException('Unsupported live catalog schema')`; `message` carries the exact
/// same text, so a cross-port comparison has one string to look for and the claim is
/// pinned by an assertion rather than a comment.
enum LiveCatalogSchemaError: Error, Equatable {
    case unsupportedVersion

    /// Byte-for-byte the message the Dart codec and `playlist_contracts.js` throw.
    var message: String { "Unsupported live catalog schema" }
}

/// Timestamps as the contract persists them.
///
/// Writing always produces the canonical form — RFC 3339 UTC with exactly three
/// fractional digits and a `Z`, e.g. `2026-01-01T00:00:00.000Z`, which is what
/// `DateTime.toIso8601String()` emits on the Dart side. Reading also accepts the
/// seconds-precision form (`2026-01-01T00:00:00Z`) that the frozen v1 fixture and
/// early builds wrote, so an existing document still loads and is normalized on
/// the next save. The reason this is not simply `JSONEncoder`'s `.iso8601`
/// strategy: `ISO8601DateFormatter` with `[.withInternetDateTime]` has no
/// fractional seconds at all, so it cannot even parse what the Dart codec writes.
///
/// The text is composed from calendar components rather than from a formatter so
/// the `Z` suffix and the three-digit fraction are guaranteed instead of reliant
/// on `ISO8601DateFormatter`'s offset rendering.
enum LiveCatalogDate {
    private static let canonicalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static let secondPrecisionFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    static func date(from text: String) -> Date? {
        canonicalFormatter.date(from: text) ?? secondPrecisionFormatter.date(from: text)
    }

    static func text(for date: Date) -> String {
        // Rounding to the nearest millisecond (rather than truncating) absorbs the
        // representation error of `timeIntervalSince1970`, so a value parsed from
        // `.001` re-encodes as `.001` instead of drifting to `.000`.
        let totalMillis = (date.timeIntervalSince1970 * 1000).rounded()
        let epochSeconds = (totalMillis / 1000).rounded(.down)
        let millis = Int(totalMillis - epochSeconds * 1000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone(identifier: "UTC")!
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: Date(timeIntervalSince1970: epochSeconds)
        )
        // Composed by hand instead of with `String(format: "%04d…", someInt)`: `Int` is
        // 64-bit while `%d` reads 32, and that only happens to print correctly because
        // both macOS and the arm64 runner pass varargs in eight-byte slots. Padding the
        // digits costs nothing and cannot depend on an ABI detail.
        return [
            padded(components.year ?? 0, width: 4),
            "-",
            padded(components.month ?? 0, width: 2),
            "-",
            padded(components.day ?? 0, width: 2),
            "T",
            padded(components.hour ?? 0, width: 2),
            ":",
            padded(components.minute ?? 0, width: 2),
            ":",
            padded(components.second ?? 0, width: 2),
            ".",
            padded(millis, width: 3),
            "Z"
        ].joined()
    }

    private static func padded(_ value: Int, width: Int) -> String {
        let digits = String(value)
        guard digits.count < width else { return digits }
        return String(repeating: "0", count: width - digits.count) + digits
    }
}

enum LiveCatalogStateCodec {
    /// The only persisted schema version this build can read.
    static let supportedSchemaVersion = 1

    /// A decoder configured with the contract's timestamp rule.
    ///
    /// Exposed because `UnifiedCatalogSnapshot` and the parse results the later
    /// tasks carry are Codable too: sharing one decoder is what stops a second
    /// place in the port from quietly choosing a different date text.
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = LiveCatalogDate.date(from: text) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "live catalog date is not an RFC 3339 timestamp: \(text)"
                ))
            }
            return date
        }
        return decoder
    }

    /// An encoder that writes the canonical timestamp form and nothing else.
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            try encoder.singleValueContainer().encode(LiveCatalogDate.text(for: date))
        }
        return encoder
    }

    static func decode(_ data: Data) throws -> LiveCatalogState {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any] else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [],
                debugDescription: "live catalog state must be a JSON object"
            ))
        }
        // Preflight: a missing, non-integer or boolean `schemaVersion` is malformed
        // data; a valid integer this build does not know is a version problem. The
        // explicit boolean rejection matters because NSNumber bridges `true` to `1`,
        // which would otherwise read as a supported document.
        guard let version = integer(root["schemaVersion"]) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [],
                debugDescription: "live catalog schemaVersion must be an integer"
            ))
        }
        guard version == supportedSchemaVersion else {
            throw LiveCatalogSchemaError.unsupportedVersion
        }
        let normalizedData = try JSONSerialization.data(withJSONObject: normalize(root))
        return try makeDecoder().decode(LiveCatalogState.self, from: normalizedData)
    }

    static func encode(_ state: LiveCatalogState) throws -> Data {
        // Symmetric with the decode preflight, and with the same reason: a port
        // must never emit a document its own reader would reject.
        guard state.schemaVersion == supportedSchemaVersion else {
            throw LiveCatalogSchemaError.unsupportedVersion
        }
        return try makeEncoder().encode(state)
    }

    // MARK: - Additive v1 normalization

    /// Fills in only the keys a v1 document may omit, on a copy.
    ///
    /// A present value is never replaced, whatever it holds: an invalid
    /// `rendererCapability` label or a mistyped `sourcePolicy` must reach typed
    /// decoding and throw there, because silently defaulting one would rewrite
    /// user intent into a capability the renderer never verified.
    ///
    /// The field list is Dart's, not the compiler's convenience. `_optEnum`, `_optInt`,
    /// `_optBool` and `_optStringList` in `live_catalog_codec.dart` each name a fallback
    /// for an absent-or-null value, so a v1 document written by an older build omits
    /// them freely. This port has to spell that out here rather than rely on the
    /// declared property initial values, because synthesized `Codable` decoding calls
    /// `decode` for a non-optional field and throws `keyNotFound` before any initial
    /// value is consulted — the difference would make one port read a document the other
    /// rejects, which is the failure the whole three-port contract exists to prevent.
    private static func normalize(_ root: [String: Any]) -> [String: Any] {
        var normalized = root
        if isMissing(normalized["recentWatches"]) {
            normalized["recentWatches"] = [Any]()
        }
        if let playlists = root["playlists"] as? [[String: Any]] {
            normalized["playlists"] = playlists.map { playlist in
                var copy = playlist
                if isMissing(copy["refreshStatus"]) {
                    copy["refreshStatus"] = PlaylistRefreshStatus.idle.rawValue
                }
                if isMissing(copy["channelCount"]) { copy["channelCount"] = 0 }
                if isMissing(copy["parsingVersion"]) { copy["parsingVersion"] = 1 }
                return copy
            }
        }
        if let members = root["members"] as? [[String: Any]] {
            normalized["members"] = members.map { member in
                var copy = member
                if isMissing(copy["languages"]) { copy["languages"] = [String]() }
                return copy
            }
        }
        if let sources = root["sources"] as? [[String: Any]] {
            normalized["sources"] = sources.map { source in
                var copy = source
                if isMissing(copy["rendererCapability"]) {
                    copy["rendererCapability"] = RendererSupport.notYetVerified.rawValue
                }
                return copy
            }
        }
        if let preferences = root["preferences"] as? [[String: Any]] {
            normalized["preferences"] = preferences.map { preference in
                var copy = preference
                if isMissing(copy["favorite"]) { copy["favorite"] = false }
                if isMissing(copy["hidden"]) { copy["hidden"] = false }
                // Failover is on unless the user turned it off, so an absent key means
                // "not yet expressed" here, not "false".
                if isMissing(copy["automaticFailoverEnabled"]) {
                    copy["automaticFailoverEnabled"] = true
                }
                if isMissing(copy["sourcePolicy"]) {
                    copy["sourcePolicy"] = standardPolicyJSON
                } else if let policy = copy["sourcePolicy"] as? [String: Any] {
                    copy["sourcePolicy"] = paddedPolicy(policy)
                }
                return copy
            }
        }
        return normalized
    }

    /// Pads a policy that exists but predates some of its own fields.
    ///
    /// `backoffMs` is deliberately absent from this list: no port gives it a fallback,
    /// because a policy that schedules no backoff and a policy that never said are
    /// different documents, and inventing a schedule would change when a source is
    /// retried.
    private static func normalized(_ policy: [String: Any]) -> [String: Any] {
        var copy = policy
        let standard = SourcePolicy.standard
        if isMissing(copy["maxAutomaticAttempts"]) { copy["maxAutomaticAttempts"] = standard.maxAutomaticAttempts }
        if isMissing(copy["sameSourceRetries"]) { copy["sameSourceRetries"] = standard.sameSourceRetries }
        if isMissing(copy["connectTimeoutMs"]) { copy["connectTimeoutMs"] = standard.connectTimeoutMs }
        if isMissing(copy["failedCooldownSeconds"]) { copy["failedCooldownSeconds"] = standard.failedCooldownSeconds }
        if isMissing(copy["bufferingThresholdMs"]) { copy["bufferingThresholdMs"] = standard.bufferingThresholdMs }
        return copy
    }

    /// Absent and JSON null are the same thing to a v1 document, exactly as
    /// `json['key'] == null` is on the Dart side.
    private static func isMissing(_ value: Any?) -> Bool {
        value == nil || value is NSNull
    }

    private static var standardPolicyJSON: [String: Any] {
        let policy = SourcePolicy.standard
        return [
            "maxAutomaticAttempts": policy.maxAutomaticAttempts,
            "sameSourceRetries": policy.sameSourceRetries,
            "connectTimeoutMs": policy.connectTimeoutMs,
            "backoffMs": policy.backoffMs,
            "failedCooldownSeconds": policy.failedCooldownSeconds,
            "bufferingThresholdMs": policy.bufferingThresholdMs,
        ]
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        // JSON `true`/`false` arrives as an NSNumber whose ObjC type encoding is a
        // char, and NSNumber bridges that to 1 — which must never read as a
        // supported schema version. A non-integral number is rejected the same way.
        let encoding = String(cString: number.objCType)
        if encoding == "c" || encoding == "C" { return nil }
        let asInt = number.int64Value
        guard number.doubleValue == Double(asInt) else { return nil }
        return Int(exactly: asInt)
    }
}

/// Read and write entry points for the persisted v1 document.
///
/// `ChannelSourceRecord` carries its own `Codable` implementation in
/// `LiveTVContracts.swift`, because that is where the secret-omission rule belongs
/// next to the fields it protects; this file owns the document-level rules: the
/// schema preflight, the additive defaults, and the timestamp strategy.
enum LiveCatalogMigration {
    /// Absent or empty stored data yields the canonical empty v1 state; anything
    /// else is decoded, and a document that cannot be understood throws rather
    /// than returning a cleared catalog.
    ///
    /// This never touches the legacy media stores: it has no path, no
    /// `UserDefaults` and no file handle, so the favorites and history documents
    /// stay byte-for-byte whatever this returns.
    static func migrate(_ data: Data?) throws -> LiveCatalogState {
        guard let data, !data.isEmpty else { return .empty }
        return try LiveCatalogStateCodec.decode(data)
    }

    static func encode(_ state: LiveCatalogState) throws -> Data {
        try LiveCatalogStateCodec.encode(state)
    }
}
