import AVFoundation
import Observation

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
