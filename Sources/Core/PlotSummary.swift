import Foundation

/// The backend packs the whole info sheet into `description`: labelled metadata first, then the
/// plot after a «خلاصه داستان/سریال» heading, then release notes. Detail pages and the Home hero
/// only want the story, so this strips everything else and flattens it into one paragraph.
enum PlotSummary {
    private static let plotHeadings = [
        "خلاصه داستان", "خلاصه سریال", "خلاصه فیلم", "خلاصه برنامه",
        "داستان فیلم", "داستان سریال", "داستان برنامه"
    ]

    private static let footerHeadings = [
        "زیرنویس", "وضعیت", "برای تماشای", "لینک دانلود", "منبع",
        "درباره انیمیشن", "درباره فیلم", "درباره سریال", "نقد و بررسی"
    ]

    private static let metadataLabels = [
        "نام اصلی", "نام پارسی", "سایر عناوین", "امتیاز", "ژانر",
        "تاریخ انتشار", "سال ساخت", "سال تولید", "محصول", "کشور",
        "زبان", "شبکه", "پخش از شبکه", "روز پخش", "روز های پخش",
        "شبکه پخش", "رده سنی", "کارگردان", "نویسنده", "ستارگان",
        "بازیگران", "با حضور", "فرمت", "کیفیت", "حجم", "مدت زمان",
        "تعداد قسمت", "قسمت ها", "وضعیت"
    ]

    static func plot(from description: String) -> String? {
        let normalized = description
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let body: String
        if let heading = plotHeadings
            .compactMap({ normalized.range(of: $0) })
            .min(by: { $0.lowerBound < $1.lowerBound }) {
            body = String(normalized[heading.upperBound...])
        } else {
            // Some entries have no plot at all, just a run of labelled fields. Those must not be
            // printed as if they were a story.
            let storyLines = normalized
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { line in
                    let trimmed = String(line).trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return true }
                    return !(metadataLabels + footerHeadings).contains(where: trimmed.hasPrefix)
                }
            let remaining = storyLines.joined(separator: "\n")
            guard !remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            guard metadataLabels.filter({ remaining.contains($0) }).count < 2 else { return nil }
            body = remaining
        }

        var story = cutAtFooter(body)
        story = String(story.drop(while: { $0.isWhitespace || $0 == ":" || $0 == "：" }))
        story = story
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        story = story.trimmingCharacters(in: CharacterSet(charactersIn: ":،,"))
        return story.isEmpty ? nil : story
    }

    private static func cutAtFooter(_ text: String) -> String {
        let kept = text.split(separator: "\n", omittingEmptySubsequences: false)
            .prefix { line in
                let trimmed = String(line).trimmingCharacters(in: .whitespaces)
                return !footerHeadings.contains(where: trimmed.hasPrefix)
            }
        return kept.joined(separator: "\n")
    }
}
