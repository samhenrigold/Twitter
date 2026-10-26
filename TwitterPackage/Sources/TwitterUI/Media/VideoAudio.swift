import AVFoundation

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
