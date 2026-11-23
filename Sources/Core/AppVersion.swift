import Foundation

// MARK: - Bundle version identity
//
// Info.plist is written by `scripts/version.py sync` from the repository-level
// version.json, so the UI must never repeat the number as a literal. These
// values come from the built bundle; a missing value degrades to an em dash
// instead of showing a stale hardcoded version.

enum AppVersion {
    /// `CFBundleShortVersionString` in Persian digits, e.g. `۲.۰.۰`.
    static var version: String {
        let raw = bundleString("CFBundleShortVersionString")
        return raw.isEmpty ? "—" : persianDigits(raw)
    }

    /// `CFBundleVersion` in Persian digits, e.g. `۲۲`.
    static var build: String {
        let raw = bundleString("CFBundleVersion")
        return raw.isEmpty ? "" : persianDigits(raw)
    }

    /// Version plus build for About surfaces, e.g. `۲.۰.۰ (۲۲)`.
    static var display: String {
        let version = self.version
        let build = self.build
        return build.isEmpty ? version : "\(version) (\(build))"
    }

    private static func bundleString(_ key: String) -> String {
        let value = Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func persianDigits(_ value: String) -> String {
        let persian: [Character] = ["۰", "۱", "۲", "۳", "۴", "۵", "۶", "۷", "۸", "۹"]
        var rendered = ""
        rendered.reserveCapacity(value.count)
        for character in value {
            if let ascii = character.asciiValue, ascii >= 48, ascii <= 57 {
                rendered.append(persian[Int(ascii - 48)])
            } else {
                rendered.append(character)
            }
        }
        return rendered
    }
}
