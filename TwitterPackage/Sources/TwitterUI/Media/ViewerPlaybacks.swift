import Models

/// The viewer's players, one per video or GIF, made the first time a page or the caption asks.
@MainActor
final class ViewerPlaybacks {
    private var playbacks: [Media.ID: VideoPlayback] = [:]
    /// Once the viewer has closed: the pages it redraws while it animates away get no new players, and play no more.
    private var isStopped = false

    /// The full-quality variant with sound for a video; a GIF has none, and loops.
    func playback(for item: Media) -> VideoPlayback? {
        guard item.kind != .photo, let url = item.videoURL ?? item.inlineVideoURL else { return nil }
        guard !isStopped else { return playbacks[item.id] }
        if let playback = playbacks[item.id] { return playback }
        let playback = VideoPlayback(url: url, loops: item.kind == .gif, isMuted: item.kind == .gif)
        playbacks[item.id] = playback
        return playback
    }

    /// Plays `item` (with sound, if it has any) and pauses every other one.
    func play(_ item: Media?) {
        guard !isStopped else { return }
        let selected = item.flatMap(playback(for:))
        for playback in playbacks.values where playback !== selected {
            playback.pause()
        }
        guard let selected else { return }
        if !selected.isMuted { VideoAudio.playWithSound() }
        selected.play()
    }

    /// Stops everything as the viewer closes, handing the audio back.
    func stop() {
        for playback in playbacks.values {
            playback.invalidate()
        }
        // Kept, paused on their last frame, for the zoom back into the tile.
        isStopped = true
        VideoAudio.playSilently()
    }
}
