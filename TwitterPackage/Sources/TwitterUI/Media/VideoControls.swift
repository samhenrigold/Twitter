import SwiftUI

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
