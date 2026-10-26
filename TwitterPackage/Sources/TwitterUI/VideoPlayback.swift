import AVFoundation
import Models
import SwiftUI
import UIKit

/// One video's or GIF's player, made once and kept by whoever shows it, so a body pass never builds a new one.
///
/// It plays what `url` points at, looping a GIF (which Twitter serves as a silent MP4), and publishes what controls
/// need: whether it's playing, how far along it is, and whether its first frame is ready to replace the poster.
@MainActor
@Observable
package final class VideoPlayback {
    package let player = AVQueuePlayer()
    package let loops: Bool
    package private(set) var isPlaying = false
    /// Whether it's waiting for data while asked to play.
    package private(set) var isBuffering = false
    package private(set) var currentTime: Double = 0
    package private(set) var duration: Double?
    /// Whether it played to its end; playing again starts over.
    package private(set) var didFinish = false
    /// Set by the surface showing it, once it has a frame to draw.
    package var isReadyForDisplay = false
    package private(set) var failed = false
    package var isMuted: Bool {
        didSet { player.isMuted = isMuted }
    }

    @ObservationIgnored private var looper: AVPlayerLooper?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: (any NSObjectProtocol)?

    package init(url: URL, loops: Bool, isMuted: Bool) {
        self.loops = loops
        self.isMuted = isMuted
        player.isMuted = isMuted
        // A muted loop is decoration: it shouldn't keep the display awake or hold up the app going to the background.
        player.preventsDisplaySleepDuringVideoPlayback = !isMuted
        let item = AVPlayerItem(url: url)
        if loops {
            looper = AVPlayerLooper(player: player, templateItem: item)
        } else {
            player.actionAtItemEnd = .pause
            player.insert(item, after: nil)
            endObserver = NotificationCenter.default.addObserver(
                forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.didFinish = true }
            }
        }
        observe()
    }

    private func observe() {
        observations.append(
            player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
                let status = player.timeControlStatus
                Task { @MainActor in
                    self?.isPlaying = status != .paused
                    self?.isBuffering = status == .waitingToPlayAtSpecifiedRate
                }
            })
        observations.append(
            player.observe(\.currentItem?.status, options: [.initial, .new]) { [weak self] player, _ in
                let status = player.currentItem?.status
                let duration = player.currentItem?.duration.seconds
                Task { @MainActor in
                    if status == .failed { self?.failed = true }
                    if let duration, duration.isFinite, duration > 0 { self?.duration = duration }
                }
            })
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 4), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.currentTime = time.seconds.isFinite ? time.seconds : 0
                if self.duration == nil, let seconds = self.player.currentItem?.duration.seconds, seconds.isFinite,
                    seconds > 0
                {
                    self.duration = seconds
                }
            }
        }
    }

    package func play() {
        if didFinish {
            didFinish = false
            player.seek(to: .zero)
        }
        player.play()
    }

    package func pause() {
        player.pause()
    }

    package func togglePlaying() {
        isPlaying ? pause() : play()
    }

    /// Jumps to `seconds` exactly, for scrubbing.
    package func seek(to seconds: Double) {
        didFinish = false
        currentTime = seconds
        player.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Stops it for good, releasing its observers; call when the view that kept it goes away.
    package func invalidate() {
        player.pause()
        observations.removeAll()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        looper?.disableLooping()
        looper = nil
    }
}

/// The app's audio session, as Twitter runs it: muted inline video and GIFs mix with whatever else is playing and
/// respect the Ring/Silent switch, and only a video playing with sound in the viewer takes over the audio.
///
/// Changes go through a queue of their own: the session's calls block on the audio server, and on the main thread
/// they hitch the zoom into and out of the viewer.
package enum VideoAudio {
    private static let queue = DispatchQueue(label: "VideoAudio", qos: .userInitiated)

    /// Before a video plays with sound: plays even with the Ring/Silent switch on silent, and interrupts other audio.
    package static func playWithSound() {
        queue.async {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .moviePlayback)
            try? session.setActive(true)
        }
    }

    /// Once nothing plays with sound: other apps' audio resumes, and muted video goes back to mixing in.
    package static func playSilently() {
        queue.async {
            let session = AVAudioSession.sharedInstance()
            guard session.category != .ambient else { return }
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            try? session.setCategory(.ambient)
        }
    }
}

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
        update(view)
        return view
    }

    package func updateUIView(_ view: PlayerLayerView, context: Context) {
        update(view)
    }

    private func update(_ view: PlayerLayerView) {
        view.playerLayer.videoGravity = gravity
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

/// Twitter's video controls: play/pause, elapsed time, a scrubber, the time left, and sound on or off.
struct VideoControls: View {
    let playback: VideoPlayback
    @State private var scrubbedTime: Double?

    var body: some View {
        HStack(spacing: 12) {
            Button {
                playback.togglePlaying()
            } label: {
                TwitterIconView(playback.isPlaying ? .pause : .play, size: 20)
                    .frame(width: 32, height: 32)
                    .contentShape(.rect)
            }
            .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")

            let duration = playback.duration ?? 0
            let time = scrubbedTime ?? playback.currentTime
            Text(Self.format(time))
                .font(.caption.monospacedDigit())
                .accessibilityHidden(true)

            Slider(
                value: Binding(
                    get: { min(time, max(duration, 0.01)) },
                    set: { scrubbedTime = $0 }
                ),
                in: 0...max(duration, 0.01)
            ) { isEditing in
                if !isEditing, let scrubbedTime {
                    playback.seek(to: scrubbedTime)
                    self.scrubbedTime = nil
                }
            }
            .disabled(duration == 0)
            .accessibilityLabel("Playback position")
            .accessibilityValue(Text("\(Self.format(time)) of \(Self.format(duration))"))

            Text("-" + Self.format(max(duration - time, 0)))
                .font(.caption.monospacedDigit())
                .accessibilityHidden(true)

            Button {
                playback.isMuted.toggle()
            } label: {
                TwitterIconView(playback.isMuted ? .soundOff : .sound, size: 20)
                    .frame(width: 32, height: 32)
                    .contentShape(.rect)
            }
            .accessibilityLabel(playback.isMuted ? "Turn Sound On" : "Turn Sound Off")
        }
        .foregroundStyle(.mediaGlyph)
        .buttonStyle(.plain)
    }

    /// `1:05`, or `1:02:05` past an hour.
    static func format(_ seconds: Double) -> String {
        let total = seconds.isFinite ? max(Int(seconds.rounded(.down)), 0) : 0
        let hours = total / 3600
        let minutes = total / 60 % 60
        let rest = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }
}
