// Port of Tweetie's ABSwipeColumnScrollView reveal animation ("disableSpring"): a 60 Hz step does
// `x += v; v *= 0.8`, starting at 0.2 × the distance — a geometric ease-out that lands exactly on the destination.
// (Throws settle on a spring instead; this only keeps Tweetie's projection for them.)
//
// Velocities are in points per 60 Hz frame, as in the original. Steps run at a fixed 60 Hz
// regardless of the display's refresh rate.
//

import UIKit

@MainActor
final class ColumnScroller {
    private(set) var value: CGFloat = 0
    /// Points per 60 Hz frame.
    private(set) var velocity: CGFloat = 0
    private(set) var destination: CGFloat = 0

    /// Per-frame velocity retention of a throw (Tweetie: 0.7), for projecting where a release would coast to.
    var throwFriction: CGFloat = 0.7
    var onUpdate: ((CGFloat) -> Void)?
    var onRest: (() -> Void)?

    private static let easeFriction: CGFloat = 0.8
    private var steps = 0
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var pendingTime: CFTimeInterval = 0
    private static let frame: CFTimeInterval = 1.0 / 60

    var isAnimating: Bool { displayLink != nil }

    /// Where a release at `velocity` (points per frame) would coast to (Tweetie's _endScroll: projection, with a
    /// throw's friction).
    func projectedLanding(from value: CGFloat, velocity: CGFloat) -> CGFloat {
        (value + velocity / (1 - throwFriction)).rounded()
    }

    /// Reveal: ease out onto `destination` exactly.
    func easeTo(_ destination: CGFloat, from value: CGFloat) {
        self.value = value
        self.destination = destination
        velocity = 0.2 * (destination - value)
        steps = 0
        pendingTime = 0
        guard displayLink == nil else { return }
        lastTimestamp = 0
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    /// Catches the animation in place (a touch down stops a moving stack), returning the current value.
    @discardableResult
    func stop() -> CGFloat {
        displayLink?.invalidate()
        displayLink = nil
        return value
    }

    @objc private func tick(_ link: CADisplayLink) {
        if lastTimestamp == 0 {
            lastTimestamp = link.timestamp
        }
        pendingTime += min(link.targetTimestamp - lastTimestamp, 0.1)
        lastTimestamp = link.targetTimestamp

        // Fixed 60 Hz steps, carrying fractional time over; between steps, show the in-between position.
        while pendingTime >= Self.frame {
            pendingTime -= Self.frame
            value += velocity
            velocity *= Self.easeFriction
            steps += 1
            if steps > 199 || (abs(velocity) < 1 && abs(destination - value) < 1) {
                value = destination
                velocity = 0
                stop()
                onUpdate?(value)
                onRest?()
                return
            }
        }
        onUpdate?(value + velocity * CGFloat(pendingTime / Self.frame))
    }
}

/// Tweetie's edge resistance: past either end, movement is halved.
func rubberBand(_ overshoot: CGFloat) -> CGFloat {
    overshoot * 0.5
}
