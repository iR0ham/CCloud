import SwiftUI
import AppKit

// MARK: - Live TV state

@MainActor
final class LiveTVModel: ObservableObject {
    @Published var countries: [LiveTVCountry] = []
    @Published var isLoadingCountries = false
    @Published var countriesError: String?
    @Published var countryQuery = ""

    @Published var channels: [LiveTVChannel] = []
    @Published var isLoadingChannels = false
    @Published var channelsError: String?
    @Published var channelQuery = ""

    private var loadedCountries = false
    private var loadedCountryCode: String?

    /// QA hook (`--debug-live-search <text>`): a snapshot run has no keyboard, but it still has to
    /// be able to point the camera at one named row.
    static let qaChannelFilter: String? = {
        guard let index = CommandLine.arguments.firstIndex(of: "--debug-live-search"),
              index + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[index + 1]
    }()

    var filteredCountries: [LiveTVCountry] {
        let query = countryQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return countries }
        return countries.filter { country in
            country.persianName.localizedStandardContains(query)
                || country.englishName.localizedCaseInsensitiveContains(query)
                || country.code.localizedCaseInsensitiveContains(query)
        }
    }

    var filteredChannels: [LiveTVChannel] {
        let query = channelQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return channels }
        return channels.filter { channel in
            channel.name.localizedCaseInsensitiveContains(query)
                || channel.languageLabel.localizedStandardContains(query)
        }
    }

    var totalChannelCount: Int {
        countries.reduce(0) { $0 + $1.channelCount }
    }

    func loadCountriesIfNeeded() async {
        guard !loadedCountries, !isLoadingCountries else { return }
        await loadCountries()
    }

    func loadCountries(force: Bool = false) async {
        if force {
            loadedCountries = false
            LiveTVCatalog.shared.clearCache()
        }
        guard !isLoadingCountries else { return }
        isLoadingCountries = true
        countriesError = nil
        do {
            countries = try await LiveTVClient.shared.countries()
            loadedCountries = true
        } catch {
            countriesError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoadingCountries = false
    }

    func loadChannels(for country: LiveTVCountry, force: Bool = false) async {
        if force {
            loadedCountryCode = nil
            LiveTVCatalog.shared.clearCache()
        }
        if !force, loadedCountryCode == country.code, !channels.isEmpty { return }
        isLoadingChannels = true
        channelsError = nil
        channels = []
        channelQuery = ""
        do {
            channels = try await LiveTVCatalog.shared.channels(for: country)
            loadedCountryCode = country.code
            if let filter = Self.qaChannelFilter { channelQuery = filter }
        } catch {
            channelsError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoadingChannels = false
    }
}

// MARK: - Live TV screen (countries → channels → player)

struct LiveTVView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.openWindow) private var openWindow
    @StateObject private var model = LiveTVModel()

    var body: some View {
        Group {
            if let country = app.liveSelectedCountry {
                channelsScreen(country)
            } else {
                countriesScreen
            }
        }
        .task { await model.loadCountriesIfNeeded() }
        .onChange(of: app.liveSelectedCountry) { _, newValue in
            guard let country = newValue else { return }
            Task { await model.loadChannels(for: country) }
        }
        .onAppear {
            if let country = app.liveSelectedCountry, model.channels.isEmpty {
                Task { await model.loadChannels(for: country) }
            }
        }
        .onChange(of: app.refreshTick) { _, _ in
            Task {
                await model.loadCountries(force: true)
                if let country = app.liveSelectedCountry {
                    await model.loadChannels(for: country, force: true)
                }
            }
        }
    }

    // MARK: Countries step

    private var countriesScreen: some View {
        VStack(alignment: .trailing, spacing: 0) {
            HStack(alignment: .bottom, spacing: 14) {
                SectionHeader(title: "پخش زنده",
                              subtitle: countriesSubtitle)
                Spacer(minLength: 0)
                if !model.countries.isEmpty {
                    IconActionButton(systemName: "arrow.clockwise",
                                     help: "دریافت دوباره فهرست کشورها") {
                        Task { await model.loadCountries(force: true) }
                    }
                }
            }
            .padding(.bottom, 18)

            LiveSearchField(text: Binding(get: { model.countryQuery },
                                          set: { model.countryQuery = $0 }),
                            placeholder: "جستجوی کشور…",
                            icon: "magnifyingglass")
                .frame(maxWidth: 520)
                .padding(.bottom, 18)

            if model.isLoadingCountries && model.countries.isEmpty {
                LoadingView(text: "در حال دریافت فهرست کشورها…")
            } else if let error = model.countriesError, model.countries.isEmpty {
                ErrorStateView(message: error) {
                    Task { await model.loadCountries(force: true) }
                }
            } else if model.filteredCountries.isEmpty {
                EmptyStateView(icon: "flag.slash", title: "کشوری پیدا نشد",
                               message: "نام دیگری را جست‌وجو کنید.")
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: liveCountryColumns, alignment: .trailing, spacing: 14) {
                        ForEach(model.filteredCountries) { country in
                            LiveCountryCard(country: country) {
                                app.openLiveCountry(country)
                            }
                        }
                    }
                    .padding(.bottom, 26)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    private var countriesSubtitle: String {
        guard !model.countries.isEmpty else {
            return "شبکه‌های تلویزیونی زنده از سراسر جهان"
        }
        let count = browseNumber(model.countries.count)
        let channels = browseNumber(model.totalChannelCount)
        return "\(count) کشور • \(channels) شبکهٔ زنده"
    }

    private var liveCountryColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 178, maximum: 250), spacing: 14, alignment: .top)]
    }

    private var liveChannelColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 430, maximum: 640), spacing: 10, alignment: .top)]
    }

    // MARK: Channels step

    private func channelsScreen(_ country: LiveTVCountry) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Button {
                    app.closeLiveCountry()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                        Text("بازگشت")
                    }
                }
                .buttonStyle(SecondaryButtonStyle(compact: true))
                .help("بازگشت به فهرست کشورها")

                Spacer(minLength: 0)

                if !model.channels.isEmpty {
                    IconActionButton(systemName: "arrow.clockwise",
                                     help: "دریافت دوباره فهرست شبکه‌ها") {
                        Task { await model.loadChannels(for: country, force: true) }
                    }
                }
            }
            .padding(.bottom, 14)

            header(for: country)

            LiveSearchField(text: Binding(get: { model.channelQuery },
                                          set: { model.channelQuery = $0 }),
                            placeholder: "جستجوی شبکه…",
                            icon: "magnifyingglass")
                .frame(maxWidth: 520)
                .padding(.top, 16)
                .padding(.bottom, 16)

            if model.isLoadingChannels {
                LoadingView(text: "در حال دریافت شبکه‌های \(country.persianName)…")
            } else if let error = model.channelsError {
                ErrorStateView(message: error) {
                    Task { await model.loadChannels(for: country, force: true) }
                }
            } else if model.filteredChannels.isEmpty {
                EmptyStateView(icon: "tv.slash",
                               title: model.channelQuery.isEmpty ? "شبکه‌ای برای این کشور پیدا نشد" : "شبکه‌ای پیدا نشد",
                               message: model.channelQuery.isEmpty ? "کشور دیگری را امتحان کنید." : "نام دیگری را جست‌وجو کنید.")
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: liveChannelColumns, alignment: .trailing, spacing: 10) {
                        ForEach(model.filteredChannels) { channel in
                            LiveChannelRow(channel: channel, country: country) {
                                play(channel, country: country)
                            } onPlayStream: { stream in
                                play(channel, country: country, streamOverride: stream)
                            }
                        }
                    }
                    .padding(.bottom, 26)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    private func header(for country: LiveTVCountry) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(country.flag)
                .font(.system(size: 38))
                .frame(width: 52, height: 46)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1))

            VStack(alignment: .trailing, spacing: 2) {
                Text("پخش زنده • \(country.persianName)")
                    .font(.ccloud(19, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text(channelsSubtitle)
                    .font(.ccloud(11.5))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var channelsSubtitle: String {
        guard !model.channels.isEmpty else { return "در حال بارگذاری شبکه‌ها…" }
        return "\(browseNumber(model.channels.count)) شبکهٔ زنده"
    }

    private func play(_ channel: LiveTVChannel, country: LiveTVCountry, streamOverride: String? = nil) {
        guard let request = channel.playbackRequest(countryName: country.persianName,
                                                    streamOverride: streamOverride) else {
            app.showToast("برای این شبکه آدرسی ثبت نشده است")
            return
        }
        app.playback = request
        openWindow(id: "Player", value: request)
    }
}

// MARK: - Country card

struct LiveCountryCard: View {
    let country: LiveTVCountry
    let action: () -> Void

    @StateObject private var hover = HoverState()

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                Text(country.flag)
                    .font(.system(size: 30))
                    .frame(width: 44, height: 40)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(country.persianName)
                        .font(.ccloud(14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Text("\(browseNumber(country.channelCount)) شبکه")
                        .font(.ccloud(10.5))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .background(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .fill(hover.isHovering ? Theme.cardHover : Theme.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .strokeBorder(hover.isHovering ? Theme.accent.opacity(0.85) : Theme.stroke, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hover.isHovering)
    }
}

// MARK: - Channel icon
//
// The Famelack dataset has no logo URLs, so every channel gets a stable monogram tile instead:
// the same name always maps to the same colour, which makes the list scannable like logos do.

struct LiveChannelIcon: View {
    let name: String

    private static let palette: [Color] = [
        Theme.accent, Color(hex: 0xE5484D), Color(hex: 0x30A46C), Color(hex: 0xF2A93B),
        Color(hex: 0x8E4EC6), Color(hex: 0x0091FF), Color(hex: 0xD6409E), Color(hex: 0x12A594)
    ]

    private static let genericWords: Set<String> = [
        "tv", "hd", "fhd", "uhd", "sd", "channel", "live", "شبکه", "تلویزیون", "پخش"
    ]

    private var letters: String {
        // "Channel One (United States)" must read CO, not the parenthesis that follows the name.
        let base = String(name.prefix(upTo: name.firstIndex(where: { $0 == "(" || $0 == "[" }) ?? name.endIndex))
        let words = base
            .split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "|" || $0 == "·" })
            .map(String.init)
        let meaningful = words.filter { !Self.genericWords.contains($0.lowercased()) }
        let picked = meaningful.isEmpty ? words : meaningful
        let initials: String
        if picked.count >= 2 {
            initials = picked.prefix(2)
                .compactMap { word in word.first(where: { $0.isLetter || $0.isNumber }) }
                .map(String.init)
                .joined()
        } else {
            initials = String((picked.first ?? base).prefix(2))
        }
        return (initials.isEmpty ? String(base.prefix(2)) : initials).uppercased()
    }

    private var tint: Color {
        var hash: UInt64 = 5381
        for scalar in name.lowercased().unicodeScalars {
            hash = hash &* 33 &+ UInt64(scalar.value)
        }
        return Self.palette[Int(hash % UInt64(Self.palette.count))]
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.52)],
                                     startPoint: .topLeading,
                                     endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
            Text(letters)
                .font(.ccloud(13, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 3)
        }
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }
}

// MARK: - Channel row

/// The playback engine remembers links that failed it twice. Reaching for that memory here beats a
/// dead channel that looks exactly as playable as a live one.
@MainActor
enum LiveTVLinkState {
    static func isKnownDead(_ channel: LiveTVChannel) -> Bool {
        !channel.streams.isEmpty && channel.streams.allSatisfy { LinkHealth.isDeprioritized($0) }
    }
}

struct LiveChannelRow: View {
    let channel: LiveTVChannel
    let country: LiveTVCountry
    let onPlay: () -> Void
    let onPlayStream: (String) -> Void

    @StateObject private var hover = HoverState()

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            LiveChannelIcon(name: channel.name)

            VStack(alignment: .trailing, spacing: 6) {
                Text(channel.name)
                    .font(.ccloud(14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if LiveTVLinkState.isKnownDead(channel) {
                        LiveChip(text: "قطع", color: Theme.red)
                    }
                    if channel.isGeoBlocked {
                        LiveChip(text: "محدود جغرافیایی", color: Theme.gold)
                    }
                    if channel.streams.count > 1 {
                        LiveChip(text: "\(browseNumber(channel.streams.count)) منبع", color: Theme.textSecondary)
                    }
                    if !channel.languageLabel.isEmpty {
                        LiveChip(text: channel.languageLabel, color: Theme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            Button(action: onPlay) {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text("پخش")
                }
            }
            .buttonStyle(PrimaryButtonStyle(compact: true))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
            .fill(hover.isHovering ? Theme.cardHover : Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
            .strokeBorder(hover.isHovering ? Theme.accent.opacity(0.6) : Theme.stroke, lineWidth: 1))
        .contentShape(Rectangle())
        .onHover { hover.isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hover.isHovering)
        .onTapGesture(perform: onPlay)
        .contextMenu {
            Button("پخش زنده") { onPlay() }
            if channel.streams.count > 1 {
                Divider()
                ForEach(Array(channel.streams.enumerated()), id: \.offset) { index, stream in
                    Button("منبع \(browseNumber(index + 1))") { onPlayStream(stream) }
                }
            }
            Divider()
            Button("کپی لینک") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(channel.primaryStream ?? "", forType: .string)
            }
        }
    }
}

struct LiveChip: View {
    let text: String
    var color: Color = Theme.textSecondary

    var body: some View {
        Text(text)
            .font(.ccloud(9.5, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.12)))
    }
}

// MARK: - Search field

struct LiveSearchField: View {
    @Binding var text: String
    var placeholder: String
    var icon: String = "magnifyingglass"

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.ccloud(12.5))
                .foregroundStyle(Theme.text)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }
}
