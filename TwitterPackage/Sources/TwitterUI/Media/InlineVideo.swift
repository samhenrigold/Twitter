import AVFoundation
import SwiftUI

/// A video or GIF playing muted on a loop over its poster while it's on screen, as a timeline or a preview shows one.
/// The player exists only while the view is mostly visible, so a long timeline never holds more than a few.
package struct InlineVideo: View {
    let url: URL
    var gravity: AVLayerVideoGravity = .resizeAspectFill
    /// Whether it plays while visible; off when the person turned video autoplay off in Accessibility.
    var autoplays = true
    /// Whether it waits until it's half scrolled into view, rather than playing as soon as it appears (outside a
    /// scroll view, as a preview is).
    var waitsForScrollVisibility = true
    @State private var playback: VideoPlayback?
    @State private var isVisible = false

    package init(
        url: URL, gravity: AVLayerVideoGravity = .resizeAspectFill, autoplays: Bool = true,
        waitsForScrollVisibility: Bool = true
    ) {
        self.url = url
        self.gravity = gravity
        self.autoplays = autoplays
        self.waitsForScrollVisibility = waitsForScrollVisibility
    }

    package var body: some View {
        // Fills its space even before there's a player, so there's something to scroll into view.
        Color.clear
            .overlay {
                if let playback {
                    VideoSurface(playback, gravity: gravity)
                        .opacity(playback.isReadyForDisplay ? 1 : 0)
                }
            }
            .allowsHitTesting(false)
            .onScrollVisibilityChange(threshold: 0.5) { isVisible = $0 }
            .onAppear { if !waitsForScrollVisibility { isVisible = true } }
            .onDisappear { isVisible = false }
            .onChange(of: isVisible) { update() }
            .onChange(of: autoplays) { update() }
            .onChange(of: url) {
                stop()
                update()
            }
    }

    private func update() {
        guard autoplays, isVisible else { return stop() }
        if playback == nil {
            VideoAudio.playSilently()
            playback = VideoPlayback(url: url, loops: true, isMuted: true)
        }
        playback?.play()
    }

    private func stop() {
        playback?.invalidate()
        playback = nil
    }
}
