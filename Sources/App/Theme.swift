import SwiftUI
import AppKit
import CoreText

// MARK: - Fonts (Vazirmatn bundled in Contents/Resources/Fonts)

enum AppFont {
    /// Global font scale driven by SettingsStore (0.85 … 1.3).
    static var scale: Double = 1.0

    private static var didRegister = false

    static func register() {
        guard !didRegister else { return }
        didRegister = true
        var urls: [URL] = []
        if let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts", isDirectory: true),
           let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            urls = files.filter { $0.pathExtension.lowercased() == "ttf" || $0.pathExtension.lowercased() == "otf" }
        }
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func postScriptName(for weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight, .thin: return "Vazirmatn-Thin"
        case .light: return "Vazirmatn-Light"
        case .medium: return "Vazirmatn-Medium"
        case .semibold: return "Vazirmatn-SemiBold"
        case .bold: return "Vazirmatn-Bold"
        case .heavy, .black: return "Vazirmatn-Bold"
        default: return "Vazirmatn-Regular"
        }
    }
}

extension Font {
    /// The app font (Vazirmatn), scaled by the user's font-size setting.
    static func ccloud(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let scaled = size * CGFloat(AppFont.scale)
        return Font.custom(AppFont.postScriptName(for: weight), fixedSize: scaled)
    }
}

// MARK: - Design tokens

enum Theme {
    // Brand (from the app's logo: vivid blue + periwinkle)
    static let accent = Color(hex: 0x3D5AFE)
    static let accentBright = Color(hex: 0x5B78FF)
    static let accentSoft = Color(hex: 0xA7B4F5)
    static let accentDeep = Color(hex: 0x1B2E8F)

    // Semantic surfaces (dynamic: dark ⇄ light)
    static let bg = Color.dynamic(light: 0xF6F7FB, dark: 0x0A0B10)
    static let bgElevated = Color.dynamic(light: 0xFFFFFF, dark: 0x11131B)
    static let sidebar = Color.dynamic(light: 0xEDEFF6, dark: 0x08090E)
    static let card = Color.dynamic(light: 0xFFFFFF, dark: 0x14161F)
    static let cardHover = Color.dynamic(light: 0xE9ECF6, dark: 0x1C1F2B)
    static let stroke = Color.dynamic(light: 0xD6DAE7, dark: 0x232736)
    static let separator = Color.dynamic(light: 0xE2E5EF, dark: 0x1A1D27)

    // Text
    static let text = Color.dynamic(light: 0x12141C, dark: 0xF2F3F7)
    static let textSecondary = Color.dynamic(light: 0x5C6275, dark: 0x9BA0B4)
    static let textTertiary = Color.dynamic(light: 0x878DA1, dark: 0x6D7286)
    static let textOnAccent = Color.white

    // Semantic accents
    static let gold = Color(hex: 0xF5C04A)
    static let green = Color(hex: 0x35D07F)
    static let red = Color(hex: 0xF0555A)
    static let overlay = Color.black.opacity(0.55)
    static let heroGradientTop = Color.black.opacity(0.05)
    static let heroGradientBottom = Color.black.opacity(0.92)

    // Metrics
    static let cornerSmall: CGFloat = 8
    static let corner: CGFloat = 14
    static let cornerLarge: CGFloat = 22
    static let sidebarWidth: CGFloat = 236
    static let contentMaxWidth: CGFloat = 1180
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }

    /// A colour that adapts when NSApp.appearance changes (dark ⇄ light).
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? NSColor(hex: dark) : NSColor(hex: light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: Double = 1.0) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: CGFloat(alpha)
        )
    }
}

// MARK: - Common view modifiers

struct CardBackground: ViewModifier {
    var radius: CGFloat = Theme.corner
    var fill: Color = Theme.card

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
    }
}

extension View {
    func cardBackground(radius: CGFloat = Theme.corner, fill: Color = Theme.card) -> some View {
        modifier(CardBackground(radius: radius, fill: fill))
    }

    /// Right-to-left, Persian-friendly text defaults.
    func ccloudText() -> some View {
        self.multilineTextAlignment(.leading)
            .environment(\.layoutDirection, .rightToLeft)
    }
}
