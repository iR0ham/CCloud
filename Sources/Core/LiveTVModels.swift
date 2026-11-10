import Foundation

// MARK: - Live TV models (Famelack / TV Garden live channel dataset)

struct LiveTVStreams: Codable, Hashable, Sendable {
    let streams: [String]

    enum CodingKeys: String, CodingKey { case streams }

    init(streams: [String]) {
        self.streams = streams
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        streams = (try? c.decodeIfPresent([String].self, forKey: .streams)) ?? []
    }
}

struct LiveTVChannel: Codable, Hashable, Identifiable, Sendable {
    let nanoid: String
    let name: String
    let sources: LiveTVStreams
    let languages: [String]
    let country: String
    let isGeoBlocked: Bool

    var id: String { nanoid }
    var countryCode: String { country.uppercased() }

    var streams: [String] {
        sources.streams
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Prefer an HLS (m3u8) stream; fall back to the first source.
    var primaryStream: String? {
        streams.first { $0.lowercased().contains(".m3u8") } ?? streams.first
    }

    var languageLabel: String {
        languages.map { LiveTVLanguage.persian($0) }.filter { !$0.isEmpty }.joined(separator: "، ")
    }

    /// Copy with a different stream list (used when a second source adds backup streams).
    func replacingStreams(_ streams: [String]) -> LiveTVChannel {
        LiveTVChannel(nanoid: nanoid,
                      name: name,
                      sources: LiveTVStreams(streams: streams),
                      languages: languages,
                      country: country,
                      isGeoBlocked: isGeoBlocked)
    }

    enum CodingKeys: String, CodingKey {
        case nanoid, name, sources, languages, country, isGeoBlocked
    }

    init(nanoid: String, name: String, sources: LiveTVStreams, languages: [String],
         country: String, isGeoBlocked: Bool) {
        self.nanoid = nanoid
        self.name = name
        self.sources = sources
        self.languages = languages
        self.country = country
        self.isGeoBlocked = isGeoBlocked
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nanoid = (try? c.decodeIfPresent(String.self, forKey: .nanoid)) ?? UUID().uuidString
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        sources = (try? c.decodeIfPresent(LiveTVStreams.self, forKey: .sources)) ?? LiveTVStreams(streams: [])
        languages = (try? c.decodeIfPresent([String].self, forKey: .languages)) ?? []
        country = (try? c.decodeIfPresent(String.self, forKey: .country)) ?? ""
        isGeoBlocked = (try? c.decodeIfPresent(Bool.self, forKey: .isGeoBlocked)) ?? false
    }
}

extension LiveTVChannel {
    /// Build a PlaybackRequest for the in-app player (HLS live streams play directly in AVPlayer).
    func playbackRequest(countryName: String, streamOverride: String? = nil) -> PlaybackRequest? {
        let urls = streamOverride.map { [$0] } ?? streams
        guard !urls.isEmpty else { return nil }
        let sources = urls.enumerated().map { index, url -> MediaSource in
            let lower = url.lowercased()
            let type: String
            if lower.contains(".m3u8") { type = "m3u8" }
            else if lower.contains(".mp4") { type = "mp4" }
            else if lower.contains(".mpd") { type = "mpd" }
            else { type = "hls" }
            let label: String
            if urls.count > 1 {
                label = index == 0 ? "منبع اصلی" : "منبع " + Self.persianDigits(index + 1)
            } else {
                label = "کیفیت اصلی"
            }
            return MediaSource(id: index + 1, quality: label, type: type, url: url)
        }
        return PlaybackRequest(title: name,
                               subtitle: "پخش زنده • " + countryName,
                               sources: sources,
                               preferredSourceID: sources.first?.id)
    }

    static func persianDigits(_ value: Int) -> String {
        PersianNumber.string(value)
    }
}

enum LiveTVLanguage {
    static func persian(_ code: String) -> String {
        switch code.lowercased() {
        case "fas", "fa", "per": return "فارسی"
        case "kur", "ckb": return "کردی"
        case "ara", "ar": return "عربی"
        case "eng", "en": return "انگلیسی"
        case "tur", "tr": return "ترکی"
        case "aze", "az": return "آذری"
        case "pus", "ps": return "پشتو"
        case "urd", "ur": return "اردو"
        case "rus", "ru": return "روسی"
        case "deu", "ger", "de": return "آلمانی"
        case "fra", "fre", "fr": return "فرانسوی"
        case "spa", "es": return "اسپانیایی"
        case "ita", "it": return "ایتالیایی"
        case "por", "pt": return "پرتغالی"
        case "hin", "hi": return "هندی"
        case "zho", "chi", "zh": return "چینی"
        case "jpn", "ja": return "ژاپنی"
        case "kor", "ko": return "کره‌ای"
        case "ben", "bn": return "بنگالی"
        case "heb", "he": return "عبری"
        case "ell", "gre", "el": return "یونانی"
        case "ukr", "uk": return "اوکراینی"
        case "ron", "rum", "ro": return "رومانیایی"
        case "pol", "pl": return "لهستانی"
        case "nld", "dut", "nl": return "هلندی"
        case "tgl", "tl": return "تاگالوگ"
        case "amh", "am": return "امهری"
        case "tir", "ti": return "تیگرینیا"
        default: return code
        }
    }
}

struct LiveTVCountryMeta: Codable, Sendable {
    let country: String
    let capital: String?
    let timeZone: String?
    let hasChannels: Bool
    let channelCount: Int

    enum CodingKeys: String, CodingKey {
        case country, capital, timeZone, hasChannels, channelCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        country = (try? c.decodeIfPresent(String.self, forKey: .country)) ?? ""
        capital = (try? c.decodeIfPresent(String.self, forKey: .capital)) ?? nil
        timeZone = (try? c.decodeIfPresent(String.self, forKey: .timeZone)) ?? nil
        hasChannels = (try? c.decodeIfPresent(Bool.self, forKey: .hasChannels)) ?? false
        channelCount = (try? c.decodeIfPresent(Int.self, forKey: .channelCount)) ?? 0
    }
}

struct LiveTVCountry: Identifiable, Hashable, Codable, Sendable {
    let code: String          // ISO-3166 alpha-2, uppercase
    let englishName: String
    let channelCount: Int

    var id: String { code }
    var persianName: String { LiveTVCountryNames.persian[code] ?? englishName }
    var flag: String { Self.emojiFlag(code) }

    static func emojiFlag(_ code: String) -> String {
        // The dataset uses a few non-ISO codes; map them to real flag codes.
        let aliases: [String: String] = ["UK": "GB", "EL": "GR"]
        let normalized = aliases[code.uppercased()] ?? code.uppercased()
        guard normalized.count == 2 else { return "🌐" }   // a few dataset codes are not ISO-2
        let base: UInt32 = 0x1F1E6
        var scalars = String.UnicodeScalarView()
        for scalar in normalized.unicodeScalars {
            let value = scalar.value
            guard value >= 65, value <= 90, let flag = UnicodeScalar(base + value - 65) else { return "🏳️" }
            scalars.append(flag)
        }
        return String(scalars)
    }
}

enum LiveTVCountryNames {
    /// Persian display names; unknown codes fall back to the dataset's English name.
    static let persian: [String: String] = [
        "IR": "ایران", "AF": "افغانستان", "TJ": "تاجیکستان", "US": "امریکا",
        "GB": "انگلستان", "UK": "انگلستان", "DE": "آلمان", "TR": "ترکیه",
        "IQ": "عراق", "AE": "امارات", "SA": "عربستان", "QA": "قطر", "KW": "کویت",
        "OM": "عمان", "BH": "بحرین", "YE": "یمن", "SY": "سوریه", "LB": "لبنان",
        "JO": "اردن", "PS": "فلسطین", "EG": "مصر", "LY": "لیبی", "TN": "تونس",
        "CY": "قبرس",
        "DZ": "الجزایر", "MA": "مراکش", "SD": "سودان", "SO": "سومالی",
        "IN": "هند", "PK": "پاکستان", "BD": "بنگلادش", "LK": "سریلانکا",
        "NP": "نپال", "CN": "چین", "JP": "ژاپن", "KR": "کره جنوبی",
        "KP": "کره شمالی", "TW": "تایوان", "HK": "هنگ‌کنگ", "TH": "تایلند",
        "VN": "ویتنام", "ID": "اندونزی", "MY": "مالزی", "SG": "سنگاپور",
        "PH": "فیلیپین", "MM": "میانمار", "KH": "کامبوج", "LA": "لائوس",
        "MN": "مغولستان", "KZ": "قزاقستان", "UZ": "ازبکستان", "TM": "ترکمنستان",
        "KG": "قرقیزستان", "AZ": "آذربایجان", "AM": "ارمنستان", "GE": "گرجستان",
        "RU": "روسیه", "UA": "اوکراین", "BY": "بلاروس", "PL": "لهستان",
        "CZ": "چک", "SK": "اسلواکی", "HU": "مجارستان", "RO": "رومانی",
        "BG": "بلغارستان", "RS": "صربستان", "HR": "کرواسی", "SI": "اسلوونی",
        "BA": "بوسنی", "ME": "مونته‌نگرو", "MK": "مقدونیه", "AL": "آلبانی",
        "GR": "یونان", "IT": "ایتالیا", "ES": "اسپانیا", "PT": "پرتغال",
        "FR": "فرانسه", "BE": "بلژیک", "NL": "هلند", "LU": "لوکزامبورگ",
        "CH": "سوئیس", "AT": "اتریش", "DK": "دانمارک", "SE": "سوئد",
        "NO": "نروژ", "FI": "فنلاند", "IS": "ایسلند", "IE": "ایرلند",
        "EE": "استونی", "LV": "لتونی", "LT": "لیتوانی", "MD": "مولداوی",
        "CA": "کانادا", "MX": "مکزیک", "BR": "برزیل", "AR": "آرژانتین",
        "CL": "شیلی", "PE": "پرو", "CO": "کلمبیا", "VE": "ونزوئلا",
        "EC": "اکوادور", "BO": "بولیوی", "PY": "پاراگوئه", "UY": "اروگوئه",
        "CR": "کاستاریکا", "PA": "پاناما", "GT": "گواتمالا", "HN": "هندوراس",
        "SV": "السالوادور", "NI": "نیکاراگوئه", "CU": "کوبا", "DO": "دومینیکن",
        "HT": "هائیتی", "JM": "جامائیکا", "AU": "استرالیا", "NZ": "نیوزیلند",
        "ZA": "آفریقای جنوبی", "NG": "نیجریه", "KE": "کنیا", "ET": "اتیوپی",
        "GH": "غنا", "SN": "سنگال", "CI": "ساحل عاج", "CM": "کامرون",
        "UG": "اوگاندا", "TZ": "تانزانیا", "MZ": "موزامبیک", "ZW": "زیمبابوه",
        "AO": "آنگولا", "ZM": "زامبیا", "BW": "بوتسوانا", "MU": "موریس",
        "ML": "مالی", "BF": "بورکینافاسو", "NE": "نیجر", "TD": "چاد",
        "MR": "موریتانی", "GM": "گامبیا", "GN": "گینه", "BJ": "بنین",
        "TG": "توگو", "SL": "سیرالئون", "LR": "لیبریا", "RW": "رواندا",
        "BI": "بوروندی", "MG": "ماداگاسکار", "MW": "مالاوی", "NA": "نامیبیا",
        "LS": "لسوتو", "SZ": "اسواتینی", "CD": "کنگو", "CG": "کنگو برازاویل",
        "GA": "گابن", "GQ": "گینه استوایی", "CF": "آفریقای مرکزی", "SS": "سودان جنوبی"
    ]
}
