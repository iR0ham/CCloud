import Foundation

// MARK: - M3U display-name text rule
//
// This is `LiveTVM3U.displayName` and its `isNoise` helper, moved verbatim out of
// `LiveTVM3UClient.swift`. Nothing about the rule changed; only its file did, and the reason is
// testability plus cross-platform identity:
//
//  * `LiveTVM3UClient.swift` declares a `@MainActor` URLSession client, so the headless contract
//    harness (`Tests/live-foundation/run.sh`, which compiles a handful of production files into a
//    standalone binary) could not include it without dragging in `Models.swift`, `LiveTVModels.swift`
//    and the network layer. The text rule has no dependencies at all, so it can.
//  * The new multi-source parser (`LivePlaylistParser.swift`, task B2-S) must strip exactly the
//    same quality tokens the shipping parser strips, because the stripped name feeds
//    `providerChannelId` fallbacks and `normalizedName` — which are persisted identities. Two
//    spellings of one rule on one platform is how a refresh ends up minting a second member for the
//    same station, and the Dart (`m3uDisplayName`) and webOS ports already treat this single recipe
//    as the contract.
//
// Keeping the implementation in one file that both callers reach means the harness assertions here
// cover the built-in Iran list and the new catalog path together, rather than only a copy.

enum LiveTVM3UText {

    /// iptv-org appends the stream quality to the channel name; the row shows the name only.
    static func displayName(_ raw: String) -> String {
        var result = ""
        var index = raw.startIndex
        while index < raw.endIndex {
            let character = raw[index]
            if character == "(" || character == "[" {
                let closer: Character = character == "(" ? ")" : "]"
                if let end = raw[index...].firstIndex(of: closer),
                   isNoise(String(raw[raw.index(after: index)..<end])) {
                    index = raw.index(after: end)
                    continue
                }
            }
            result.append(character)
            index = raw.index(after: index)
        }
        return result.split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
            .joined(separator: " ")
    }

    /// Bracketed text that is metadata rather than part of the station's name.
    private static func isNoise(_ inner: String) -> Bool {
        let token = inner.lowercased().replacingOccurrences(of: " ", with: "")
        guard !token.isEmpty else { return true }
        if ["4k", "8k", "sd", "hd", "fhd", "uhd", "hevc", "multiaudio", "backup"].contains(token) {
            return true
        }
        if token.hasPrefix("not") { return true }
        return token.range(of: #"^\d{1,4}[kpi]\d*$"#, options: .regularExpression) != nil
    }
}
