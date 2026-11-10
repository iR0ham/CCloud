import SwiftUI
import AppKit

// MARK: - Settings page (owner: ui-detail) — appearance, font, quality, autoplay, favorites,
// server info and reset. All changes persist through SettingsStore / FavoritesStore.

@MainActor
final class SettingsLocalModel: ObservableObject {
    @Published var confirmClearFavorites = false
    @Published var confirmReset = false
}

private struct SettingsCard<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    private let content: Content

    init(icon: String, title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accentBright)
                    .frame(width: 27, height: 27)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.accent.opacity(0.14)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.ccloud(14, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Text(subtitle)
                        .font(.ccloud(10.5))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cardBackground(radius: Theme.corner, fill: Theme.card)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var downloads: DownloadsStore

    @StateObject private var model = SettingsLocalModel()

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 430, maximum: .infinity), spacing: 16)]
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeader(
                    title: "تنظیمات",
                    subtitle: "ترجیحات نمایش، پخش و اطلاعات سرور"
                )

                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    appearanceCard
                    fontCard
                    qualityCard
                    autoplayCard
                    regionalCard
                    favoritesCard
                    downloadsCard
                    serverCard
                    resetCard
                }

                Color.clear.frame(height: 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Appearance

    private var appearanceCard: some View {
        SettingsCard(icon: "circle.lefthalf.filled", title: "ظاهر برنامه",
                     subtitle: "حالت تیره، روشن یا هماهنگ با سیستم") {
            HStack(spacing: 8) {
                ForEach(AppAppearance.allCases) { option in
                    appearanceOption(option)
                }
            }
        }
    }

    private func appearanceOption(_ option: AppAppearance) -> some View {
        let selected = settings.appearance == option
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { settings.appearance = option }
        } label: {
            VStack(spacing: 7) {
                Image(systemName: appearanceIcon(option))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(selected ? Color.white : Theme.textSecondary)
                Text(option.title)
                    .font(.ccloud(10.5, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.white : Theme.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? Theme.accent : Theme.bgElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(selected ? Color.clear : Theme.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(option.title)
    }

    private func appearanceIcon(_ option: AppAppearance) -> String {
        switch option {
        case .system: return "circle.lefthalf.filled"
        case .dark: return "moon.fill"
        case .light: return "sun.max.fill"
        }
    }

    // MARK: Font scale

    private var fontCard: some View {
        SettingsCard(icon: "textformat.size", title: "اندازه فونت",
                     subtitle: "اندازه متن‌های برنامه را تنظیم کنید") {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 10) {
                    Text("کوچک").font(.ccloud(9.5)).foregroundStyle(Theme.textTertiary)
                    Slider(
                        value: Binding(
                            get: { settings.fontScale },
                            set: { settings.fontScale = min(max($0, 0.85), 1.3) }
                        ),
                        in: 0.85...1.3,
                        step: 0.05
                    )
                    .tint(Theme.accent)
                    Text("بزرگ").font(.ccloud(11, weight: .semibold)).foregroundStyle(Theme.textTertiary)
                }

                HStack(spacing: 6) {
                    Text(percentText(settings.fontScale))
                        .font(.ccloud(10, weight: .bold))
                        .foregroundStyle(Theme.accentBright)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Theme.accent.opacity(0.14)))
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("پیش‌نمایش متن")
                        .font(.ccloud(13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("این یک متن نمونه برای بررسی خوانایی اندازه فونت انتخاب‌شده است.")
                        .font(.ccloud(11.5))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.bgElevated)
                )
            }
        }
    }

    private func percentText(_ scale: Double) -> String {
        "\(Int((scale * 100).rounded()))٪"
    }

    // MARK: Preferred quality

    private var qualityCard: some View {
        SettingsCard(icon: "4k.tv", title: "کیفیت پیش‌فرض پخش",
                     subtitle: "سورس پیشنهادی هنگام زدن دکمه پخش") {
            HStack(spacing: 8) {
                ForEach(Array(settings.qualityOptions.enumerated()), id: \.offset) { pair in
                    FilterChip(
                        title: pair.element.title,
                        isSelected: settings.preferredQuality == pair.element.value,
                        action: { settings.preferredQuality = pair.element.value }
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Autoplay

    private var autoplayCard: some View {
        SettingsCard(icon: "play.circle", title: "پخش خودکار",
                     subtitle: "انتخاب کیفیت و پخش قسمت بعد") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text(settings.autoPlayBest
                         ? "در صورت وجود چند سورس، بهترین کیفیت به‌صورت خودکار پخش می‌شود."
                         : "کیفیت پیش‌فرض انتخاب‌شده در بخش قبل استفاده می‌شود.")
                        .font(.ccloud(11))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Toggle("", isOn: Binding(
                        get: { settings.autoPlayBest },
                        set: { settings.autoPlayBest = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(Theme.accent)
                }

                Divider().overlay(Theme.stroke)

                contentToggle(
                    title: "پخش قسمت بعد",
                    isOn: Binding(
                        get: { settings.autoPlayNextEpisode },
                        set: { settings.autoPlayNextEpisode = $0 }
                    ),
                    onText: "پس از پایان هر قسمت، قسمت بعد با شمارش معکوس ۱۰ ثانیه‌ای پخش می‌شود.",
                    offText: "پس از پایان قسمت، پخش متوقف می‌شود.",
                    help: "پخش خودکار قسمت بعد سریال"
                )
            }
        }
    }

    // MARK: Regional content

    private var regionalCard: some View {
        SettingsCard(icon: "globe.asia.australia", title: "پنهان‌سازی محتوا",
                     subtitle: "در همهٔ بخش‌ها به‌جز پخش زنده اعمال می‌شود") {
            VStack(alignment: .leading, spacing: 12) {
                contentToggle(
                    title: "چین، کره، ترکیه، هند، تایلند، ژاپن، پاکستان، افغانستان و کشورهای عربی",
                    isOn: Binding(
                        get: { settings.hideRegionalOrigins },
                        set: { settings.hideRegionalOrigins = $0 }
                    ),
                    onText: "این عناوین در صفحهٔ اصلی، جست‌وجو، دسته‌ها، کشورها، علاقه‌مندی‌ها و تاریخچه پنهان می‌شوند.",
                    offText: "محتوای این کشورها نمایش داده می‌شود.",
                    help: "پنهان کردن فیلم‌ها و سریال‌های چین، کره، ترکیه، هند، تایلند، ژاپن، پاکستان، افغانستان و کشورهای عربی"
                )
                Divider().overlay(Theme.stroke)
                contentToggle(
                    title: "انیمه",
                    isOn: Binding(
                        get: { settings.hideAnime },
                        set: { settings.hideAnime = $0 }
                    ),
                    onText: "انیمه‌های ژاپنی پنهان می‌شوند.",
                    offText: "انیمه‌های ژاپنی نمایش داده می‌شوند.",
                    help: "پنهان کردن انیمه‌های ژاپنی"
                )
            }
        }
    }

    private func contentToggle(title: String,
                               isOn: Binding<Bool>,
                               onText: String,
                               offText: String,
                               help: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.ccloud(11.5, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(isOn.wrappedValue ? onText : offText)
                    .font(.ccloud(10.5))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Theme.accent)
                .help(help)
        }
    }

    // MARK: Favorites

    private var favoritesCard: some View {
        SettingsCard(icon: "heart", title: "علاقه‌مندی‌ها",
                     subtitle: "عناوین ذخیره‌شده روی این مک") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Text("\(favorites.entries.count)")
                        .font(.ccloud(12, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Text("عنوان ذخیره شده است")
                        .font(.ccloud(11))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 0)
                }
                Button {
                    model.confirmClearFavorites = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash").font(.system(size: 10.5))
                        Text("پاک کردن همه علاقه‌مندی‌ها")
                    }
                    .foregroundStyle(Theme.red)
                }
                .buttonStyle(SecondaryButtonStyle(compact: true))
                .disabled(favorites.entries.isEmpty)
                .opacity(favorites.entries.isEmpty ? 0.5 : 1)
                .alert("پاک کردن علاقه‌مندی‌ها", isPresented: Binding(
                    get: { model.confirmClearFavorites },
                    set: { model.confirmClearFavorites = $0 }
                )) {
                    Button("پاک کردن", role: .destructive) {
                        favorites.clear()
                        app.showToast("علاقه‌مندی‌ها پاک شد")
                    }
                    Button("انصراف", role: .cancel) { }
                } message: {
                    Text("همه عناوین ذخیره‌شده حذف می‌شوند. این عمل قابل بازگشت نیست.")
                }
            }
        }
    }

    // MARK: Downloads

    private var downloadsCard: some View {
        SettingsCard(icon: "arrow.down.circle", title: "دانلودها",
                     subtitle: "ذخیرهٔ مستقیم در پوشهٔ Downloads/CCloud") {
            VStack(alignment: .leading, spacing: 10) {
                if downloads.items.isEmpty {
                    Text("هنوز دانلودی شروع نشده است. از صفحهٔ جزئیات فیلم یا قسمت سریال، دکمهٔ دانلود را بزنید.")
                        .font(.ccloud(11))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 8) {
                        ForEach(downloads.items) { item in
                            DownloadRow(
                                item: item,
                                onCancel: { downloads.cancel(item.id) },
                                onRetry: { downloads.retry(item.id) },
                                onReveal: { downloads.reveal(item.id) },
                                onRemove: { downloads.remove(item.id) }
                            )
                        }
                    }
                }

                HStack(spacing: 8) {
                    Button(action: { downloads.revealFolder() }) {
                        HStack(spacing: 5) {
                            Image(systemName: "folder").font(.system(size: 10))
                            Text("نمایش پوشهٔ دانلود")
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle(compact: true))

                    if downloads.items.contains(where: { $0.state != .downloading }) {
                        Button(action: { downloads.clearFinished() }) {
                            HStack(spacing: 5) {
                                Image(systemName: "xmark.circle").font(.system(size: 10))
                                Text("پاک کردن فهرست")
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle(compact: true))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: Server info

    private var serverCard: some View {
        SettingsCard(icon: "server.rack", title: "اطلاعات سرور",
                     subtitle: "وضعیت اتصال به بک‌اند CCloud") {
            VStack(alignment: .leading, spacing: 9) {
                serverRow(label: "هاست فعال", value: app.backendHost, tint: Theme.text)

                HStack(spacing: 6) {
                    Text("وضعیت اتصال")
                        .font(.ccloud(11))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 0)
                    Circle()
                        .fill(app.isOffline ? Theme.gold : (app.genresError == nil ? Theme.green : Theme.red))
                        .frame(width: 7, height: 7)
                    Text(app.isOffline ? "آفلاین (نسخهٔ ذخیره‌شده)" : (app.genresError == nil ? "متصل" : "قطع"))
                        .font(.ccloud(11, weight: .semibold))
                        .foregroundStyle(app.isOffline ? Theme.gold : (app.genresError == nil ? Theme.green : Theme.red))
                }

                serverRow(label: "ژانرهای دریافتی", value: "\(app.genres.count)", tint: Theme.text)

                if let error = app.genresError {
                    Text(error)
                        .font(.ccloud(10.5))
                        .foregroundStyle(Theme.red)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 8) {
                    Button {
                        Task { await app.loadGenres() }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise").font(.system(size: 10))
                            Text("بررسی دوباره")
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle(compact: true))
                    .disabled(app.genresLoading)
                    if app.genresLoading {
                        ProgressView().controlSize(.small)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func serverRow(label: String, value: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.ccloud(11))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
            Text(value)
                .font(.ccloud(11, weight: .medium))
                .foregroundStyle(tint)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    // MARK: Reset

    private var resetCard: some View {
        SettingsCard(icon: "arrow.counterclockwise", title: "بازنشانی تنظیمات",
                     subtitle: "بازگشت به مقادیر پیش‌فرض برنامه") {
            VStack(alignment: .leading, spacing: 12) {
                Text("ظاهر، اندازه فونت، کیفیت، پخش خودکار و پنهان‌سازی محتوا به حالت اولیه برمی‌گردند.")
                    .font(.ccloud(11))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    model.confirmReset = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise").font(.system(size: 10.5))
                        Text("بازنشانی تنظیمات")
                    }
                }
                .buttonStyle(SecondaryButtonStyle(compact: true))
                .alert("بازنشانی تنظیمات", isPresented: Binding(
                    get: { model.confirmReset },
                    set: { model.confirmReset = $0 }
                )) {
                    Button("بازنشانی", role: .destructive) {
                        settings.reset()
                        app.showToast("تنظیمات بازنشانی شد")
                    }
                    Button("انصراف", role: .cancel) { }
                } message: {
                    Text("همه تنظیمات به مقادیر پیش‌فرض بازمی‌گردند.")
                }
            }
        }
    }
}

// MARK: - Download row

private struct DownloadRow: View {
    let item: DownloadsStore.Item
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onReveal: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            CachedAsyncImage(url: item.posterURL.flatMap { URL(string: $0) }, placeholderIcon: "arrow.down")
                .frame(width: 34, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Theme.stroke, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.ccloud(11.5, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)

                statusLine

                if item.state == .downloading {
                    progressBar
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            actions
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.bgElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var statusLine: some View {
        switch item.state {
        case .downloading:
            Text("در حال دانلود • ٪\(browseNumber(Int((item.progress * 100).rounded()))) • \(sizeText)")
                .font(.ccloud(10))
                .foregroundStyle(Theme.accentBright)
        case .completed:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 9, weight: .bold))
                Text("دانلود شد • \(sizeText)")
                    .font(.ccloud(10))
            }
            .foregroundStyle(Theme.green)
        case .failed:
            Text(item.errorMessage ?? "دانلود ناموفق بود")
                .font(.ccloud(10))
                .foregroundStyle(Theme.red)
                .lineLimit(2)
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.stroke)
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: geo.size.width * max(item.progress, 0.02))
            }
        }
        .frame(height: 3)
        .environment(\.layoutDirection, .leftToRight)
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 4) {
            switch item.state {
            case .downloading:
                IconActionButton(systemName: "xmark", help: "لغو دانلود",
                                 tint: Theme.textSecondary, action: onCancel)
            case .completed:
                IconActionButton(systemName: "folder", help: "نمایش در Finder",
                                 tint: Theme.textSecondary, action: onReveal)
                IconActionButton(systemName: "trash", help: "حذف از فهرست",
                                 tint: Theme.textSecondary, action: onRemove)
            case .failed:
                IconActionButton(systemName: "arrow.clockwise", help: "تلاش دوباره",
                                 tint: Theme.accentBright, action: onRetry)
                IconActionButton(systemName: "trash", help: "حذف از فهرست",
                                 tint: Theme.textSecondary, action: onRemove)
            }
        }
    }

    private var sizeText: String {
        let received = megabytes(item.receivedBytes)
        if item.totalBytes > 0 {
            return "\(received) از \(megabytes(item.totalBytes)) مگابایت"
        }
        return "\(received) مگابایت"
    }

    private func megabytes(_ bytes: Int64) -> String {
        browseNumber(Int((Double(bytes) / 1_048_576).rounded()))
    }
}
