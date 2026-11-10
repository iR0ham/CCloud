import SwiftUI
import AVKit
import AppKit

/// Hosts the `AVPlayerLayer` video output inside SwiftUI.
/// `PlaybackController` owns the `AVPlayer`; the surface only attaches/detaches it.
struct PlayerSurface: NSViewRepresentable {
    let controller: PlaybackController

    func makeNSView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.player = controller.player
        return view
    }

    func updateNSView(_ nsView: PlayerLayerView, context: Context) {
        if nsView.playerLayer.player !== controller.player {
            nsView.playerLayer.player = controller.player
        }
    }

    static func dismantleNSView(_ nsView: PlayerLayerView, coordinator: ()) {
        nsView.playerLayer.player = nil
    }
}

/// Plain `NSView` whose backing layer is an `AVPlayerLayer` (never uses `@State`/SwiftUI macros).
final class PlayerLayerView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var isFlipped: Bool { true }

    override func makeBackingLayer() -> CALayer {
        playerLayer
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}
