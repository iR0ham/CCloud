import Foundation

// MARK: - Multi-source playlist parsing (task B2-S)
//
// This is the macOS half of the parser contract that `flutter_app/lib/core/playlist_parser.dart`
// (B2-D) and `webos_app/app/js/playlist_parser.js` (B2-J) implement for the other two platforms.
// The three ports read the same bytes under `Tests/fixtures/multi-source/` and must reach the same
// verdicts, because one catalog is exchanged between platforms: a channel the Mac refuses while
// Android imports it (or the reverse) is a data-loss bug nobody can see until a refresh reorders a
// user's list.
//
// It deliberately does not change `LiveTVM3UClient`/`LiveTVM3U`, which still build the existing
// built-in Iran list. Replacing that path would change shipping behavior for every user at once, so
// the multi-source parser is additive and only the new catalog consumes it. It does reuse two
// dependency-free production helpers rather than restating them: `LiveTVM3UText.displayName` (the
// quality-token rule, relocated so the harness can compile it) and `PersianNumber.string` (the
// `منبع ۲` labels the other ports render the same way).
//
// Two rules need a local implementation rather than a Foundation shortcut, and both are about
// identity surviving a platform round-trip:
//
//  * `StableKeyHash` is four independent 32-bit FNV-1a passes, not SHA-256. `CryptoKit`/`Insecure.MD5`
//    cannot produce this recipe, and using a digest instead would mint different member IDs from the
//    ones the Dart and webOS ports compute, orphaning every persisted row.
//  * `LiveMatchKey` reproduces the Dart `liveNameKey` scalar-for-scalar. `LiveTVNameKey` stays in
//    place for the existing list, but Foundation's `folding(options:)` is a locale- and
//    ICU-version-sensitive transform that leaves Persian digits as ۱ rather than 1, so it cannot be
//    the cross-language key. The pinned inputs below are the only thing keeping the two definitions
//    from drifting apart silently.

// MARK: - Limits

/// Resource-safety ceilings from the specification, shared verbatim by the three ports.
///
/// These are not product quotas. Crossing one truncates the parse *and says so* through
/// `truncated` plus a `limitExceeded` or `oversizedInput` issue, so a partial catalog can never be
/// mistaken for a complete one.
enum LivePlaylistLimits {
    static let maxBytes = 10 * 1024 * 1024
    static let maxLines = 200_000
    static let maxMembers = 50_000
    static let maxUrlsPerMember = 100
    static let maxUrlChars = 8_192

    /// Anything else (`ftp:`, `file:`, `udp:`) is refused before it can reach a player, because the
    /// renderer evidence collected so far covers HTTP(S) only.
    static let streamSchemes: Set<String> = ["http", "https"]

    /// Keys that make a query string a credential rather than a parameter.
    static let sensitiveQueryKeys: Set<String> = [
        "token", "key", "password", "signature", "auth", "credential",
    ]
}

// MARK: - Identity hash

/// Deterministic 128-bit identifier hash used for catalog identity.
///
/// Four passes rather than one is not decoration: every call site builds an identity from a
/// separator-delimited string, so a single 32-bit fold eventually collides at a rate a user notices
/// as two channels silently merging. A detected collision must raise `identityCollision` and refuse
/// the merge, never pick a winner. This is **not** a cryptographic digest and is never used for
/// passwords, signatures or download integrity.
enum StableKeyHash {

    private static let seeds: [UInt32] = [0x811c_9dc5, 0x9e37_79b9, 0x85eb_ca6b, 0xc2b2_ae35]
    private static let prime: UInt32 = 0x0100_0193

    /// Hashes [value] into thirty-two lowercase hex digits, over its exact UTF-8 bytes.
    ///
    /// The input is hashed as it arrives — no case folding, no trimming, no match-key normalization.
    /// Callers normalize first and then hash, so two ports disagreeing about normalization can never
    /// change an identity silently.
    static func hash(_ value: String) -> String {
        let bytes = Array(value.utf8)
        var out = ""
        out.reserveCapacity(32)
        for seed in seeds {
            var h = seed
            for byte in bytes {
                // FNV-1a order: XOR the byte in first, then multiply. Swapping the two gives FNV-1
                // and a completely different identifier space.
                h ^= UInt32(byte)
                h = h &* prime
            }
            var digits = String(h, radix: 16)
            while digits.count < 8 { digits = "0" + digits }
            out += digits
        }
        return out
    }
}

// MARK: - Match key

/// Script- and case-folded channel-name key, byte-for-byte the Dart `liveNameKey` recipe.
enum LiveMatchKey {

    static func key(_ name: String) -> String {
        var folded = String.UnicodeScalarView()
        for scalar in name.unicodeScalars {
            var value = scalar.value
            // Width fold (fullwidth ASCII and the ideographic space).
            if value >= 0xFF01 && value <= 0xFF5E {
                value -= 0xFEE0
            } else if value == 0x3000 {
                value = 0x20
            }
            // Diacritics: Latin combining marks and Arabic harakat/tajweed marks.
            if (value >= 0x0300 && value <= 0x036F)
                || (value >= 0x0610 && value <= 0x061A)
                || (value >= 0x064B && value <= 0x065F)
                || value == 0x0670
                || (value >= 0x06D6 && value <= 0x06ED) {
                continue
            }
            switch value {
            case 0x064A, 0x0626, 0x0649: value = 0x06CC   // ي ئ ى → ی
            case 0x0643: value = 0x06A9                   // ك → ک
            case 0x0629: value = 0x0647                   // ة → ه
            case 0x0622, 0x0623, 0x0625, 0x0671: value = 0x0627  // آ أ إ ٱ → ا
            case 0x0624: value = 0x0648                   // ؤ → و
            case 0x200C, 0x200D, 0x00A0: value = 0x20      // ZWNJ, ZWJ, NBSP → space
            default:
                if value >= 0x06F0 && value <= 0x06F9 {
                    value = 0x0030 + value - 0x06F0        // Persian digits → ASCII
                } else if value >= 0x0660 && value <= 0x0669 {
                    value = 0x0030 + value - 0x0660        // Arabic-Indic digits → ASCII
                }
            }
            if let foldedScalar = Unicode.Scalar(value) { folded.append(foldedScalar) }
        }

        let cleaned = String(folded).lowercased()
        var result = ""
        var pendingSpace = false
        for scalar in cleaned.unicodeScalars {
            let value = scalar.value
            let kept = (value >= 0x30 && value <= 0x39)
                || (value >= 0x61 && value <= 0x7A)
                || (value >= 0x0600 && value <= 0x06FF)
            if kept {
                if pendingSpace && !result.isEmpty { result += " " }
                result.unicodeScalars.append(scalar)
                pendingSpace = false
            } else {
                pendingSpace = true
            }
        }
        return result
    }
}

// MARK: - Parsed shapes

/// What a fetched document turned out to be.
enum LivePlaylistFormat: String {
    case m3uChannelList
    case hlsMediaManifest
    case empty
    case invalid
}

/// One channel as a single playlist stated it, before any identity work.
struct ParsedChannel: Sendable {
    var providerChannelId: String
    var displayName: String
    var streamUrls: [String]
    var line: Int
    var logoUrl: String?
    var group: String?
    var countryCode: String?
    var languages: [String]
    var tvgId: String?
}

/// The outcome of parsing one playlist document.
struct PlaylistParseResult: Sendable {
    var format: LivePlaylistFormat
    var channels: [ParsedChannel]
    var issues: [CatalogIssue]
    /// StableKeyHash over the exact decoded text, so a refresh that fetched identical content can
    /// skip re-parsing. Empty when the payload was refused before parsing.
    var contentHash: String
    var inputBytes: Int
    var truncated: Bool
}

/// What one parsed playlist contributes to the catalog: proposed members, sources and issues.
///
/// Merging that with what the user already has (retaining health, enabled flags, associations and
/// preferences) is task B4, which is why this carries no revision and no logical IDs.
struct SourceRegistryResult: Sendable {
    var members: [ChannelMember]
    var sources: [ChannelSourceRecord]
    var issues: [CatalogIssue]
}

private struct DraftRow {
    var key: String
    var providerChannelId: String
    var displayName: String
    /// Physical line of this row's `#EXTINF`. A repeated provider id keeps the first row's number,
    /// because re-listing a station must not move it.
    var number: Int
    var logoUrl: String?
    var group: String?
    var countryCode: String?
    var languages: [String]
    var tvgId: String?
    var urls: [String] = []

    /// True once any non-comment line followed this row, whether or not it was usable. It is what
    /// separates "the playlist never gave this row an address" (`missingStream`) from "the address it
    /// gave was refused" (`invalidUrl`), so one bad row cannot report both.
    var sawAddressLine = false
}

// MARK: - Parser

enum LivePlaylistParser {

    /// Parses one M3U playlist [text] into provider rows.
    ///
    /// [playlistID] only labels issues; identity is built by `LiveSourceRegistry.register`. Relative
    /// addresses resolve against [baseURL] **only** when that base is HTTP(S): a `file:` base must
    /// not smuggle a relative path into something a player will fetch.
    static func parse(playlistID: String, text: String, baseURL: URL?) -> PlaylistParseResult {
        var issues: [CatalogIssue] = []
        let inputBytes = text.utf8.count

        // The size ceiling is checked before any splitting or hashing: refusing a ten-megabyte
        // payload cheaply is the whole point of a ceiling, and hashing refused bytes is wasted work.
        if inputBytes > LivePlaylistLimits.maxBytes {
            return PlaylistParseResult(
                format: firstLine(text).hasPrefix("#EXTM3U") ? .m3uChannelList : .invalid,
                channels: [],
                issues: [CatalogIssue(
                    code: "oversizedInput",
                    message: "playlist for \(playlistID) is \(inputBytes) bytes, above the "
                        + "\(LivePlaylistLimits.maxBytes)-byte ceiling, so nothing was parsed",
                    line: 1
                )],
                contentHash: "",
                inputBytes: inputBytes,
                truncated: true
            )
        }

        let contentHash = StableKeyHash.hash(text)
        // A leading BOM belongs to the encoding, not to the `#EXTM3U` token.
        let body = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        let allLines = body.components(separatedBy: "\n")
        var truncated = false

        var lineCount = allLines.count
        if lineCount > LivePlaylistLimits.maxLines {
            truncated = true
            issues.append(CatalogIssue(
                code: "limitExceeded",
                message: "playlist for \(playlistID) has \(allLines.count) lines; parsing stopped "
                    + "at the \(LivePlaylistLimits.maxLines)-line ceiling",
                line: LivePlaylistLimits.maxLines
            ))
            lineCount = LivePlaylistLimits.maxLines
        }

        var order: [String] = []
        var rows: [String: DraftRow] = [:]
        var fallbackOccurrences: [String: Int] = [:]
        var openKey: String?
        var sawExtInf = false
        var sawStreamInf = false

        func closeOpen() {
            guard let key = openKey else { return }
            openKey = nil
            guard let row = rows[key] else { return }
            if row.urls.isEmpty && !row.sawAddressLine {
                issues.append(CatalogIssue(
                    code: "missingStream",
                    message: "\"\(row.displayName)\" has no stream address on line \(row.number)",
                    line: row.number
                ))
            }
        }

        for index in 0..<lineCount {
            let line = index + 1
            let raw = allLines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            if raw.isEmpty { continue }

            if raw.hasPrefix("#EXTINF") {
                sawExtInf = true
                closeOpen()
                if rows.count >= LivePlaylistLimits.maxMembers {
                    // The permitted prefix is kept rather than discarded, so the user sees 50,000
                    // real rows plus one honest issue instead of an empty list.
                    truncated = true
                    issues.append(CatalogIssue(
                        code: "limitExceeded",
                        message: "playlist for \(playlistID) exceeded the "
                            + "\(LivePlaylistLimits.maxMembers)-member ceiling on line \(line)",
                        line: line
                    ))
                    break
                }
                guard let row = draftRow(
                    from: raw,
                    number: line,
                    issues: &issues,
                    fallbackOccurrences: &fallbackOccurrences
                ) else { continue }
                if rows[row.key] != nil {
                    // Repeated non-empty provider ids merge in first-seen order: the first row keeps
                    // its line, name and metadata so a re-listed station does not jump position.
                    rows[row.key]!.sawAddressLine = false
                    openKey = row.key
                    continue
                }
                order.append(row.key)
                rows[row.key] = row
                openKey = row.key
                continue
            }

            if raw.hasPrefix("#") {
                if raw.hasPrefix("#EXT-X-STREAM-INF") { sawStreamInf = true }
                continue
            }

            guard let key = openKey, var row = rows[key] else {
                continue // An address with no row before it is not a channel.
            }
            row.sawAddressLine = true
            if row.urls.count >= LivePlaylistLimits.maxUrlsPerMember {
                truncated = true
                issues.append(CatalogIssue(
                    code: "limitExceeded",
                    message: "\"\(row.displayName)\" exceeded "
                        + "\(LivePlaylistLimits.maxUrlsPerMember) stream addresses on line \(line)",
                    line: line
                ))
                rows[key] = row
                openKey = nil
                continue
            }
            // The character ceiling is charged here rather than inside the canonicalizer because
            // crossing it drops a stream the user could otherwise see, so the parse is partial and
            // must say so. A URL is never truncated to fit either: half an address would still look
            // playable.
            if raw.utf16.count > LivePlaylistLimits.maxUrlChars {
                truncated = true
                issues.append(CatalogIssue(
                    code: "limitExceeded",
                    message: "stream address on line \(line) is \(raw.utf16.count) characters, "
                        + "above the \(LivePlaylistLimits.maxUrlChars)-character ceiling",
                    line: line
                ))
                rows[key] = row
                continue
            }
            if let canonical = canonicalAddress(raw, line: line, baseURL: baseURL, issues: &issues),
               !row.urls.contains(canonical) {
                row.urls.append(canonical)
            }
            rows[key] = row
        }
        closeOpen()

        if !sawExtInf && sawStreamInf {
            return PlaylistParseResult(
                format: .hlsMediaManifest,
                channels: [],
                issues: [CatalogIssue(
                    code: "unsupportedMediaManifest",
                    message: "playlist for \(playlistID) is an HLS media manifest, not an M3U "
                        + "channel list, so no channels were imported",
                    line: 1
                )],
                contentHash: contentHash,
                inputBytes: inputBytes,
                truncated: truncated
            )
        }

        if !firstLine(body).hasPrefix("#EXTM3U") {
            issues.append(CatalogIssue(
                code: "malformedEntry",
                message: "playlist for \(playlistID) has no #EXTM3U header, so it is not treated "
                    + "as a channel list",
                line: 1
            ))
            return PlaylistParseResult(
                format: .invalid,
                channels: [],
                issues: issues,
                contentHash: contentHash,
                inputBytes: inputBytes,
                truncated: truncated
            )
        }

        var channels: [ParsedChannel] = []
        for key in order {
            guard let row = rows[key], !row.urls.isEmpty else { continue }
            channels.append(ParsedChannel(
                providerChannelId: row.providerChannelId,
                displayName: row.displayName,
                streamUrls: row.urls,
                line: row.number,
                logoUrl: row.logoUrl,
                group: row.group,
                countryCode: row.countryCode,
                languages: row.languages,
                tvgId: row.tvgId
            ))
        }

        return PlaylistParseResult(
            format: order.isEmpty ? .empty : .m3uChannelList,
            channels: channels,
            issues: issues,
            contentHash: contentHash,
            inputBytes: inputBytes,
            truncated: truncated
        )
    }

    /// Turns one `#EXTINF` [header] row into a draft, recording the issue that made it unusable.
    private static func draftRow(
        from header: String,
        number: Int,
        issues: inout [CatalogIssue],
        fallbackOccurrences: inout [String: Int]
    ) -> DraftRow? {
        // iptv-org puts the display name after the last comma, so the split is on the *last* comma:
        // attributes and names may each contain one, and the name is whatever follows the final one.
        guard let comma = header.lastIndex(of: ",") else {
            issues.append(CatalogIssue(
                code: "malformedEntry",
                message: "line \(number) is an #EXTINF row with no display-name field",
                line: number
            ))
            return nil
        }
        let name = LiveTVM3UText.displayName(String(header[header.index(after: comma)...]))
        if name.isEmpty {
            issues.append(CatalogIssue(
                code: "missingName",
                message: "line \(number) is an #EXTINF row whose display name is empty",
                line: number
            ))
            return nil
        }

        let attributes = header[header.startIndex..<comma]
        let rawId = attribute("tvg-id", in: attributes)
        let logo = attribute("tvg-logo", in: attributes)
        let group = attribute("group-title", in: attributes)

        // Exactly the existing parser's rule: a trailing `@quality` marker is not identity, and the
        // last dotted suffix is the country rather than part of the station name.
        var base = rawId
        if let at = base.firstIndex(of: "@") { base = String(base[base.startIndex..<at]) }
        var countryCode: String?
        if let dot = base.lastIndex(of: ".") {
            countryCode = String(base[base.index(after: dot)...]).uppercased()
            base = String(base[base.startIndex..<dot])
        }

        let providerChannelId: String
        if !base.isEmpty {
            providerChannelId = base
        } else {
            // Identity rule 2. The occurrence index is what keeps two unnamed rows apart; without it
            // they collapse into one channel and one of the user's streams silently vanishes.
            let tuple = "\(LiveMatchKey.key(name))|\(countryCode ?? "")|\(group ?? "")|\(logo ?? "")"
            let occurrence = fallbackOccurrences[tuple] ?? 0
            fallbackOccurrences[tuple] = occurrence + 1
            providerChannelId = "fallback:\(tuple)|\(occurrence)"
        }

        let languages = attribute("tvg-language", in: attributes)
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return DraftRow(
            key: providerChannelId,
            providerChannelId: providerChannelId,
            displayName: name,
            number: number,
            logoUrl: logo.isEmpty ? nil : logo,
            group: group.isEmpty ? nil : group,
            countryCode: countryCode,
            languages: languages,
            // The unstripped attribute survives so a later identity review can see `@SD` and `.ir`.
            tvgId: rawId.isEmpty ? nil : rawId
        )
    }

    private static func attribute(_ name: String, in line: Substring) -> String {
        guard let start = line.range(of: name + "=\"") else { return "" }
        let rest = line[start.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return "" }
        return String(rest[rest.startIndex..<end]).trimmingCharacters(in: .whitespaces)
    }

    private static func canonicalAddress(
        _ raw: String,
        line: Int,
        baseURL: URL?,
        issues: inout [CatalogIssue]
    ) -> String? {
        var candidate: URL?
        if let parsed = URL(string: raw), parsed.scheme != nil {
            candidate = parsed
        } else if let base = baseURL,
                  LivePlaylistLimits.streamSchemes.contains((base.scheme ?? "").lowercased()) {
            candidate = URL(string: raw, relativeTo: base)?.absoluteURL
        }
        guard let resolved = candidate else {
            issues.append(CatalogIssue(
                code: "invalidUrl",
                message: "stream address on line \(line) is not absolute and no HTTP(S) base was "
                    + "supplied",
                line: line
            ))
            return nil
        }
        guard let canonical = canonicalStreamURL(resolved.absoluteString) else {
            issues.append(CatalogIssue(
                code: "invalidUrl",
                message: "stream address on line \(line) is not an HTTP(S) address this build can "
                    + "play",
                line: line
            ))
            return nil
        }
        return canonical
    }

    /// Reduces a stream address to the form identity is computed from, or `nil` if unusable.
    ///
    /// Only the scheme and host fold to lowercase; path and query keep their case, because CDN paths
    /// are case-sensitive and lowercasing one would silently point two different manifests at one
    /// `sourceId`. Default ports are dropped for the same reason: `:443` and no port are the same
    /// origin, and keeping both spellings would double every source list.
    ///
    /// A fragment is refused rather than stripped, because stripping would make `a.m3u8#1` and
    /// `a.m3u8#2` one source while the playlist presented two rows. Userinfo is refused for the same
    /// class of reason: it is a credential, not part of an address.
    static func canonicalStreamURL(_ raw: String) -> String? {
        guard let uri = URLComponents(string: raw) else { return nil }
        let scheme = (uri.scheme ?? "").lowercased()
        guard LivePlaylistLimits.streamSchemes.contains(scheme) else { return nil }
        guard let host = uri.host, !host.isEmpty else { return nil }
        guard (uri.user ?? "").isEmpty && (uri.password ?? "").isEmpty else { return nil }
        guard uri.fragment == nil else { return nil }
        let path = uri.path
        guard !path.isEmpty && path != "/" else { return nil }

        var out = "\(scheme)://\(host.lowercased())"
        if let port = uri.port {
            let defaultPort = scheme == "http" ? 80 : 443
            if port != defaultPort { out += ":\(port)" }
        }
        out += path
        if let query = uri.query, !query.isEmpty { out += "?\(query)" }
        return out
    }

    /// True when [raw] carries a credential that must never be persisted as plaintext.
    ///
    /// Detection is on exact query *keys*, case-insensitively, rather than on substring matches: a
    /// substring test flags `/monkey.m3u8` and drops a legitimate channel, which is worse than the
    /// leak it tries to prevent. A signed URL is not rejected here — only the registry knows whether
    /// this platform has a secret store to put it in.
    static func isSensitiveURL(_ raw: String) -> Bool {
        guard let uri = URLComponents(string: raw) else { return false }
        if !(uri.user ?? "").isEmpty || !(uri.password ?? "").isEmpty { return true }
        guard let query = uri.query else { return false }
        for pair in query.split(separator: "&", omittingEmptySubsequences: false) {
            if pair.isEmpty { continue }
            let key = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                .first ?? pair
            if LivePlaylistLimits.sensitiveQueryKeys
                .contains(key.trimmingCharacters(in: .whitespaces).lowercased()) {
                return true
            }
        }
        return false
    }

    /// Protocol hint from the canonical path extension only.
    ///
    /// The query is ignored deliberately: `c.MP4?x=M3U8` is an mp4 file whose query merely mentions a
    /// manifest. A hint never claims the renderer can play the stream — only `SourceHealth` and
    /// `rendererCapability` carry evidence, and both start unverified.
    static func protocolHint(for canonical: String) -> String {
        let path = (URLComponents(string: canonical)?.path ?? "").lowercased()
        if path.hasSuffix(".m3u8") { return "hls" }
        if path.hasSuffix(".mpd") { return "dash" }
        if path.hasSuffix(".mp4") { return "mp4" }
        return "unknown"
    }

    private static func firstLine(_ text: String) -> String {
        if let newline = text.firstIndex(of: "\n") {
            return String(text[text.startIndex..<newline])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Source registry

/// Turns a parse result into catalog members and sources.
///
/// Identity follows the specification's rules exactly, because these IDs are what survive a refresh:
///
///  * `memberId = "member:" + stableKeyHash(playlistId + "\nprovider\n" + providerNamespace + "\n"
///    + providerChannelId)` (rule 1), so the same station name in two playlists, or under two
///    namespaces, stays two members rather than merging into one the user did not choose.
///  * `sourceId = "source:" + stableKeyHash(memberId + "\nurl\n" + canonicalStreamUrl)` (rule 3), so
///    an address that merely changes spelling keeps its identity, while a real address change
///    produces a new ID and the old one's history stops applying.
///  * `channelId` is the member ID (rule 4). No association is inferred here; cross-playlist merging
///    needs explicit user action in B4.
///
/// Nothing here claims a stream works. Every source starts `unverified` with `rendererCapability` at
/// `Not Yet Verified` and no playback timestamps, because parsing a playlist is not evidence about a
/// decoder.
enum LiveSourceRegistry {

    static func register(
        parsed: PlaylistParseResult,
        playlistId: String,
        providerNamespace: String
    ) -> SourceRegistryResult {
        var members: [ChannelMember] = []
        var sources: [ChannelSourceRecord] = []
        var issues: [CatalogIssue] = []

        for channel in parsed.channels {
            let memberId = "member:" + StableKeyHash.hash(
                "\(playlistId)\nprovider\n\(providerNamespace)\n\(channel.providerChannelId)"
            )
            members.append(ChannelMember(
                memberId: memberId,
                playlistId: playlistId,
                providerNamespace: providerNamespace,
                providerChannelId: channel.providerChannelId,
                displayName: channel.displayName,
                normalizedName: LiveMatchKey.key(channel.displayName),
                logoUrl: channel.logoUrl,
                group: channel.group,
                countryCode: channel.countryCode,
                languages: channel.languages,
                tvgId: channel.tvgId,
                ordinal: members.count
            ))

            var seen = Set<String>()
            var priority = 0
            for raw in channel.streamUrls {
                let canonical = LivePlaylistParser.canonicalStreamURL(raw)
                guard let canonical else {
                    // Defensive rather than redundant: the parser already canonicalized, so reaching
                    // here means canonicalization stopped being idempotent, and that is a bug worth a
                    // visible issue rather than a silently missing source.
                    issues.append(CatalogIssue(
                        code: "invalidUrl",
                        message: "member \(memberId) offered an address that is not canonicalizable: "
                            + "line \(channel.line)",
                        line: channel.line
                    ))
                    continue
                }
                // Two spellings of one origin are one source. Deduplicating is not an error, so it
                // reports nothing: the ceilings in the parser own the `limitExceeded` cases.
                if seen.contains(canonical) { continue }
                seen.insert(canonical)

                if LivePlaylistParser.isSensitiveURL(canonical) {
                    // No platform has a verified secret store yet, and the contract forbids
                    // persisting a credential-bearing address as plaintext. Refusing with this code
                    // is the honest outcome: once a secret store is verified, the same row becomes a
                    // `streamSecretRef` instead.
                    issues.append(CatalogIssue(
                        code: "secretStorageUnavailable",
                        message: "a stream address for \(channel.displayName) carries a credential "
                            + "and was not stored, because no verified secret store exists on this "
                            + "platform",
                        line: channel.line
                    ))
                    continue
                }

                sources.append(ChannelSourceRecord(
                    sourceId: "source:" + StableKeyHash.hash("\(memberId)\nurl\n\(canonical)"),
                    channelId: memberId,
                    memberId: memberId,
                    playlistId: playlistId,
                    providerNamespace: providerNamespace,
                    label: priority == 0 ? "منبع اصلی" : "منبع \(PersianNumber.string(priority + 1))",
                    streamUrl: canonical,
                    streamSecretRef: nil,
                    protocolHint: LivePlaylistParser.protocolHint(for: canonical),
                    rendererCapability: .notYetVerified,
                    origin: .playlist,
                    priority: priority,
                    enabled: true,
                    health: .unverified,
                    lastSuccessfulPlaybackAt: nil,
                    lastFailedPlaybackAt: nil,
                    lastErrorCode: nil
                ))
                priority += 1
            }
        }

        return SourceRegistryResult(members: members, sources: sources, issues: issues)
    }
}
