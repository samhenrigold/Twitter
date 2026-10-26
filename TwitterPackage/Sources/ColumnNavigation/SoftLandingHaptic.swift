// A soft, round "bawoomp" for something settling into place: a short continuous haptic with low sharpness that
// swells and fades, rather than a crisp tap. Falls back to a soft impact where Core Haptics isn't available.
//

import CoreHaptics
import UIKit

@MainActor
final class SoftLandingHaptic {
    private let engine: CHHapticEngine?
    private let fallback = UIImpactFeedbackGenerator(style: .soft)

    init() {
        engine = CHHapticEngine.capabilitiesForHardware().supportsHaptics ? try? CHHapticEngine() : nil
        engine?.isAutoShutdownEnabled = true
    }

    /// Spins the engine up ahead of a landing that's about to happen.
    func prepare() {
        if let engine {
            try? engine.start()
        } else {
            fallback.prepare()
        }
    }

    func play(intensity: Float = 1) {
        guard let engine else {
            fallback.impactOccurred(intensity: CGFloat(intensity))
            return
        }
        // Short, as discrete-event haptics should be (HIG), with very low sharpness for roundness.
        let duration: TimeInterval = 0.12
        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.08)
            ], relativeTime: 0, duration: duration)
        // Lands at full strength, then rolls off: round rather than a click.
        let swell = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [
                .init(relativeTime: 0, value: 0.6),
                .init(relativeTime: 0.02, value: 1),
                .init(relativeTime: 0.06, value: 0.5),
                .init(relativeTime: duration, value: 0)
            ], relativeTime: 0)
        do {
            try engine.start()
            let pattern = try CHHapticPattern(events: [event], parameterCurves: [swell])
            try engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
        } catch {
            fallback.impactOccurred(intensity: CGFloat(intensity))
        }
    }
}
