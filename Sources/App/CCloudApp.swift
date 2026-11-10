import SwiftUI
import AppKit

@main
struct CCloudApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var app = AppState()
    @StateObject private var settings = SettingsStore()
    @StateObject private var favorites = FavoritesStore()
    @StateObject private var history = WatchHistoryStore()
    @StateObject private var downloads = DownloadsStore()

    init() {
        AppFont.register()
    }

    var body: some Scene {
        WindowGroup("CCloud") {
            RootView()
                .onAppear {
                    app.favoritesRef = favorites
                    app.historyRef = history
                    downloads.onCompleted = { item in
                        app.showToast("دانلود «\(item.title)» کامل شد")
                    }
                }
                .environmentObject(app)
                .environmentObject(settings)
                .environmentObject(favorites)
                .environmentObject(history)
                .environmentObject(downloads)
                .frame(minWidth: 1120, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1320, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .help) { }
            CommandGroup(after: .newItem) {
                Button("تازه‌سازی") {
                    app.refresh()
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("جستجو") {
                    app.focusSearch()
                }
                .keyboardShortcut("f", modifiers: .command)
            }
            CommandMenu("پخش") {
                Button("توقف/ادامه") {
                    NotificationCenter.default.post(name: .ccloudTogglePlayback, object: nil)
                }
                .keyboardShortcut(.space, modifiers: [])
                Button("بستن پخش‌کننده") {
                    app.playback = nil
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
        }

        WindowGroup("Player", id: "Player", for: PlaybackRequest.self) { request in
            PlayerWindowView(request: request.wrappedValue)
                .environmentObject(app)
                .environmentObject(settings)
                .environmentObject(favorites)
                .environmentObject(history)
                .environmentObject(downloads)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1280, height: 720)
        .windowToolbarStyle(.unified(showsTitle: false))
    }
}

extension Notification.Name {
    static let ccloudTogglePlayback = Notification.Name("ccloud.togglePlayback")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppFont.register()

        NSApp.setActivationPolicy(.regular)
        if let window = NSApp.windows.first {
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.minSize = NSSize(width: 1120, height: 720)
            window.backgroundColor = NSColor(hex: 0x0A0B10)
        }
        NSApp.activate(ignoringOtherApps: true)

        // Single-instance behaviour: a second direct launch (QA/terminal) of the same bundle must not
        // leave zombie instances that block future launches. macOS' normal double-click activation
        // already reuses the running instance; this only kills duplicate processes.
        let myPID = ProcessInfo.processInfo.processIdentifier
        for other in NSRunningApplication.runningApplications(withBundleIdentifier: "ir.ccloud.mac") {
            if other.processIdentifier != myPID {
                other.forceTerminate()
            }
        }

        // QA hook: `CCloud --snapshot /tmp/shot.png [--snapshot-delay 5] [--tab movies]`
        //      [--snapshot-window Player|CCloud] — which of the app's windows to render
        // LaunchServices (`open`) does not forward argv on modern macOS, so the same hooks can be
        // driven through UserDefaults for unsandboxed end-to-end QA:
        //   defaults write ir.ccloud.macapp QASnapshot -string /tmp/shot.png
        //   defaults write ir.ccloud.macapp QADelay -int 12
        //   defaults write ir.ccloud.macapp QADemo -string favorites
        let args = CommandLine.arguments
        var snapshotPath: String?
        var snapshotDelay = 5.0
        var snapshotWindow: String?
        if let idx = args.firstIndex(of: "--snapshot"), idx + 1 < args.count {
            snapshotPath = args[idx + 1]
            if let dIdx = args.firstIndex(of: "--snapshot-delay"), dIdx + 1 < args.count,
               let d = Double(args[dIdx + 1]) { snapshotDelay = d }
            if let wIdx = args.firstIndex(of: "--snapshot-window"), wIdx + 1 < args.count {
                snapshotWindow = args[wIdx + 1]
            }
        } else if let qaPath = UserDefaults.standard.string(forKey: "QASnapshot") {
            snapshotPath = qaPath
            let qaDelay = UserDefaults.standard.double(forKey: "QADelay")
            if qaDelay > 0 { snapshotDelay = qaDelay }
            UserDefaults.standard.removeObject(forKey: "QASnapshot")
            UserDefaults.standard.removeObject(forKey: "QADelay")
            UserDefaults.standard.synchronize()
        }
        if let snapshotPath {
            DispatchQueue.main.asyncAfter(deadline: .now() + snapshotDelay) {
                Self.writeSnapshot(to: snapshotPath, titled: snapshotWindow)
                fflush(stderr)
                exit(0)
            }
        }
    }

    /// Renders the front window's layer tree to PNG (works without screen-recording permission).
    static func writeSnapshot(to path: String, titled wanted: String? = nil) {
        let candidates = NSApp.windows.filter { $0.isVisible && $0.contentView != nil }
        let diag = "windows=\(NSApp.windows.count) visible=\(candidates.count) key=\(NSApp.keyWindow?.title ?? "-") sheets=\(NSApp.windows.filter { $0.isSheet }.count)"
        FileHandle.standardError.write("snapshot: \(diag)\n".data(using: .utf8)!)
        // The player lives in its own window, so a QA run that leaves one behind would otherwise
        // be photographed instead of the screen it asked for. Windows are matched by their
        // SwiftUI title ("CCloud", "Player") or the identifier SwiftUI derives from the scene id.
        let named = wanted.flatMap { title in
            candidates.first { window in
                window.title.compare(title, options: .caseInsensitive) == .orderedSame
                    || window.identifier?.rawValue.range(of: title, options: .caseInsensitive) != nil
            }
        }
        let window = named
            ?? NSApp.windows.first(where: { $0.isSheet && $0.isVisible && $0.contentView != nil })
            ?? NSApp.keyWindow.flatMap { key in candidates.contains(where: { $0 === key }) ? key : nil }
            ?? candidates.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
        guard let window = window,
              let view = window.contentView,
              let layer = view.layer ?? window.contentView?.layer else {
            FileHandle.standardError.write("snapshot: no window\n".data(using: .utf8)!)
            return
        }
        view.layoutSubtreeIfNeeded()
        let scale = window.backingScaleFactor
        let size = view.bounds.size
        guard size.width > 10, size.height > 10,
              let ctx = CGContext(data: nil,
                                  width: Int(size.width * scale),
                                  height: Int(size.height * scale),
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return }
        ctx.scaleBy(x: scale, y: scale)
        // CALayer geometry is bottom-left origin; flip so the PNG is upright.
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)
        layer.render(in: ctx)
        guard let cgImage = ctx.makeImage() else { return }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            FileHandle.standardError.write("snapshot written: \(path) \(cgImage.width)x\(cgImage.height)\n".data(using: .utf8)!)
        } catch {
            FileHandle.standardError.write("snapshot failed: \(error)\n".data(using: .utf8)!)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // Disable AppKit state restoration: a corrupted/stale saved window state (or a sandboxed
    // environment that cannot write it) must never prevent the main window from being created.
    func application(_ app: NSApplication, shouldSaveApplicationState coder: NSCoder) -> Bool {
        false
    }

    func application(_ app: NSApplication, shouldRestoreApplicationState coder: NSCoder) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
