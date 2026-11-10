import SwiftUI
import AppKit

// MARK: - Player Window View (opens in separate window for true fullscreen)

@MainActor
struct PlayerWindowView: View {
    let request: PlaybackRequest?
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var history: WatchHistoryStore
    @StateObject private var ui = PlayerUIModel()

    var body: some View {
        Group {
            if let request = request ?? app.playback {
                PlayerScreen(request: request)
                    .environmentObject(app)
                    .environmentObject(settings)
                    .environmentObject(favorites)
                    .environmentObject(history)
                    .environmentObject(ui)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            } else {
                Text("هیچ پخش فعالی نیست")
                    .font(.title2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            }
        }
        .onAppear {
            // Configure window for fullscreen video
            if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "player" }) {
                window.title = "پخش‌کننده"
                window.minSize = NSSize(width: 800, height: 450)
                window.backgroundColor = NSColor.black
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.isMovableByWindowBackground = true
                window.collectionBehavior = [.fullScreenPrimary, .fullScreenAuxiliary]
            }
        }
        .onDisappear {
            app.playback = nil
        }
    }
}