import AVFoundation
import SwiftUI
import UIKit

/// Draws a ``VideoPlayback`` with nothing over it, and tells it once it has a frame to show.
package struct VideoSurface: UIViewRepresentable {
    let playback: VideoPlayback
    var gravity: AVLayerVideoGravity = .resizeAspect

    package init(_ playback: VideoPlayback, gravity: AVLayerVideoGravity = .resizeAspect) {
        self.playback = playback
        self.gravity = gravity
    }

    package func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.isUserInteractionEnabled = false
        update(view, dynamicRange: context.environment.allowedDynamicRange)
        return view
    }

    package func updateUIView(_ view: PlayerLayerView, context: Context) {
        update(view, dynamicRange: context.environment.allowedDynamicRange)
    }

    private func update(_ view: PlayerLayerView, dynamicRange: Image.DynamicRange?) {
        view.playerLayer.videoGravity = gravity
        // HDR video follows the same headroom as images: limited in timelines, full in the viewer.
        let layerRange = Self.layerDynamicRange(dynamicRange)
        if view.playerLayer.preferredDynamicRange != layerRange { view.playerLayer.preferredDynamicRange = layerRange }
        guard view.playerLayer.player !== playback.player else { return }
        view.playerLayer.player = playback.player
        view.readyObservation = view.playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) {
            [weak playback] layer, _ in
            let isReady = layer.isReadyForDisplay
            Task { @MainActor in
                guard let playback, playback.isReadyForDisplay != isReady else { return }
                withAnimation(.easeOut(duration: 0.2)) { playback.isReadyForDisplay = isReady }
            }
        }
    }

    private static func layerDynamicRange(_ range: Image.DynamicRange?) -> CALayer.DynamicRange {
        switch range {
        case .standard?: .standard
        case .constrainedHigh?: .constrainedHigh
        case .high?: .high
        default: .automatic
        }
    }

    package static func dismantleUIView(_ view: PlayerLayerView, coordinator: ()) {
        view.readyObservation = nil
        view.playerLayer.player = nil
    }

    package final class PlayerLayerView: UIView {
        var readyObservation: NSKeyValueObservation?
        override package static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
