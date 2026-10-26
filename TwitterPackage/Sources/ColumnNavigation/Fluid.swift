// The system's recipe for fluid, interruptible gestures (from the iOS 27 decomp and WWDC18 "Designing Fluid
// Interfaces"), used by every drag except the strip scroll, which keeps Tweetie's own integrator:
//
// - While the finger is down, the dragged value follows it exactly.
// - On release, a spring (FluidSpring) takes the value from there at the finger's velocity. Springs are stepped
//   by one display link (FluidDriver), which then lays everything out once per frame, so every view derived from
//   the values (shadows, dimmers, masks) moves in lockstep. A touch stops a spring where it is: it catches.
// - Decisions use where the release would carry the finger (projection), not where it lifted.
// - Resistance past a limit uses UIKit's rubber band.
//

import SwiftUI
import UIKit

@MainActor
enum Fluid {
    /// SBFFluidBehaviorSettings' default settle spring (dampingRatio 0.845, response 0.531).
    nonisolated static let settle = Animation.spring(response: 0.531, dampingFraction: 0.845)
    /// SBFFluidBehaviorSettings' critically damped spring, for things that mustn't overshoot.
    nonisolated static let criticallyDamped = Animation.spring(response: 0.336, dampingFraction: 1)

    static func animate(_ animation: Animation = settle, _ changes: () -> Void, completion: (() -> Void)? = nil) {
        UIView.animate(animation, changes: changes, completion: completion)
    }

    /// Where a release at `velocity` (points per second) would carry things (_UIHyperInteractor's projection:
    /// deceleration 0.99, speeds under 250 pt/s count as none).
    static func project(_ velocity: CGFloat, decelerationRate rate: CGFloat = 0.99, minimumSpeed: CGFloat = 250)
        -> CGFloat
    {
        abs(velocity) < minimumSpeed ? 0 : velocity * (rate / (1 - rate)) / 1000
    }

    /// The finger travel that `rubberBand` turns into `displacement` (so a caught, rubber-banded value can be dragged
    /// on without a jump).
    static func invertRubberBand(_ displacement: CGFloat, dimension: CGFloat, coefficient: CGFloat = 0.55) -> CGFloat {
        guard dimension > 0 else { return 0 }
        let fraction = min(abs(displacement) / dimension, 0.999)
        let travel = dimension * (1 / (1 - fraction) - 1) / coefficient
        return displacement < 0 ? -travel : travel
    }

    /// UIKit's rubber band (_UIHyperInteractor, coefficient 0.55 for touch): `overshoot` past a limit becomes a
    /// displacement that approaches `dimension` but never reaches it.
    static func rubberBand(_ overshoot: CGFloat, dimension: CGFloat, coefficient: CGFloat = 0.55) -> CGFloat {
        guard dimension > 0 else { return 0 }
        let magnitude = dimension * (1 - 1 / (abs(overshoot) * coefficient / dimension + 1))
        return overshoot < 0 ? -magnitude : magnitude
    }
}

/// A value carried toward a target by a damped spring (response and damping ratio, as SpringBoard specifies them).
/// It moves only while a FluidDriver steps it; stopping it leaves it exactly where it is, which is how a touch
/// catches something in flight.
@MainActor
final class FluidSpring {
    fileprivate(set) var value: CGFloat
    /// Units per second.
    fileprivate(set) var velocity: CGFloat = 0
    fileprivate(set) var target: CGFloat
    fileprivate(set) var isAnimating = false
    /// Distance and speed under which the spring is considered at rest.
    var restThreshold: CGFloat
    /// Called with the new value on every step (and when set directly).
    var onChange: ((CGFloat) -> Void)?
    fileprivate var response: CGFloat = 0.531
    fileprivate var dampingRatio: CGFloat = 0.845
    fileprivate var completion: (() -> Void)?

    init(_ value: CGFloat = 0, restThreshold: CGFloat = 0.05) {
        self.value = value
        self.target = value
        self.restThreshold = restThreshold
    }

    /// Moves the value directly (a finger dragging it), stopping any animation.
    func set(_ newValue: CGFloat) {
        isAnimating = false
        completion = nil
        value = newValue
        target = newValue
        velocity = 0
        onChange?(newValue)
    }

    /// Stops in place, keeping the current value. Returns it.
    @discardableResult
    func stop() -> CGFloat {
        isAnimating = false
        completion = nil
        velocity = 0
        target = value
        return value
    }

    /// One semi-implicit Euler step of x'' = −k(x − target) − c·x'. Returns true once at rest.
    fileprivate func step(_ dt: CGFloat) -> Bool {
        let stiffness = pow(2 * .pi / response, 2)
        let damping = 4 * .pi * dampingRatio / response
        velocity += (-stiffness * (value - target) - damping * velocity) * dt
        value += velocity * dt
        if abs(value - target) < restThreshold, abs(velocity) < restThreshold * 10 {
            value = target
            velocity = 0
            return true
        }
        return false
    }
}

/// Steps FluidSprings off one display link at a fixed internal rate, then calls `onFrame` once, so everything
/// laid out from their values moves in lockstep (nothing animates on its own in Core Animation).
@MainActor
final class FluidDriver: NSObject {
    private var springs: [FluidSpring] = []
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private let onFrame: () -> Void

    init(onFrame: @escaping () -> Void) {
        self.onFrame = onFrame
    }

    var isAnimating: Bool { !springs.isEmpty }

    /// Springs `spring` to `target`, starting at `velocity` (units per second; nil keeps its current velocity, so
    /// retargeting a moving spring stays continuous).
    func animate(
        _ spring: FluidSpring, to target: CGFloat, velocity: CGFloat? = nil, response: CGFloat = 0.531,
        dampingRatio: CGFloat = 0.845, completion: (() -> Void)? = nil
    ) {
        spring.target = target
        if let velocity { spring.velocity = velocity }
        spring.response = response
        spring.dampingRatio = dampingRatio
        spring.completion = completion
        spring.isAnimating = true
        if !springs.contains(where: { $0 === spring }) { springs.append(spring) }
        if link == nil {
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
            link.add(to: .main, forMode: .common)
            self.link = link
            lastTimestamp = nil
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        // Step to the frame about to be shown, not the one just drawn.
        let now = link.targetTimestamp
        let elapsed = min(max(now - (lastTimestamp ?? link.timestamp), 0), 1.0 / 30)
        lastTimestamp = now
        let substep: CGFloat = 1.0 / 480
        var finished: [FluidSpring] = []
        springs.removeAll { !$0.isAnimating }
        for spring in springs {
            var remaining = CGFloat(elapsed)
            var atRest = false
            while remaining > 0, !atRest {
                let dt = min(substep, remaining)
                atRest = spring.step(dt)
                remaining -= dt
            }
            spring.onChange?(spring.value)
            if atRest { finished.append(spring) }
        }
        for spring in finished {
            spring.isAnimating = false
        }
        springs.removeAll { !$0.isAnimating }
        onFrame()
        for spring in finished {
            let completion = spring.completion
            spring.completion = nil
            completion?()
        }
        if springs.isEmpty {
            self.link?.invalidate()
            self.link = nil
        }
    }
}
