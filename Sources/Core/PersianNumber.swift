import Foundation

// MARK: - Persian digits
//
// The app writes its own numbers everywhere — browse subtitles, live channel counts and the
// player's status messages — so the helper lives in Core, where the headless player harness can
// compile it too.

enum PersianNumber {

    private static let digits: [Character] = ["۰", "۱", "۲", "۳", "۴", "۵", "۶", "۷", "۸", "۹"]

    /// Latin → Persian digits, without grouping (counts are small enough that grouping is noise).
    static func string(_ value: Int) -> String {
        let magnitude = abs(value)
        if magnitude == 0 { return digits[0].description }
        var chars: [Character] = []
        var remainder = magnitude
        while remainder > 0 {
            chars.append(digits[remainder % 10])
            remainder /= 10
        }
        let rendered = String(chars.reversed())
        return value < 0 ? "−" + rendered : rendered
    }
}
