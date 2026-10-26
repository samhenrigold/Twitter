import AudioToolbox
import Foundation

/// Twitter for iPad's sound effects. Played as system sounds, so they respect the ringer switch like the originals.
package enum ClassicSound: String, CaseIterable, Sendable {
    /// The timeline finished refreshing.
    case pop
    /// Pull-to-refresh caught.
    case psst1
    /// Pull-to-refresh released and loading.
    case psst2
    case tick

    /// The Sounds setting, on unless turned off.
    package static let settingKey = "playsSounds"

    package func play() {
        guard UserDefaults.standard.object(forKey: Self.settingKey) as? Bool ?? true, let id = Self.soundIDs[self]
        else { return }
        AudioServicesPlaySystemSound(id)
    }

    private static let soundIDs: [ClassicSound: SystemSoundID] = Dictionary(
        uniqueKeysWithValues: allCases.compactMap { sound in
            guard let url = Bundle.module.url(forResource: sound.rawValue, withExtension: "wav") else { return nil }
            var id: SystemSoundID = 0
            guard AudioServicesCreateSystemSoundID(url as CFURL, &id) == kAudioServicesNoError else { return nil }
            return (sound, id)
        }
    )
}
