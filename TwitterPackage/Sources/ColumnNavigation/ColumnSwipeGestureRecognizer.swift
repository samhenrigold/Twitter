// Port of Tweetie's ABScrollGestureRecognizer plus the touch half of ABSwipeColumnScrollView.
//
// - Fails for multi-touch (cancels, if already dragging), and for touches that start in text views.
// - Begins once the finger has moved more than 10pt horizontally; fails if it first moves
//   more than 10pt vertically (and more vertically than horizontally).
// - Doesn't delay touches, so content still sees taps, unless `beginsOnTouchDown` says the touch is
//   catching something in motion: then it begins at once, which cancels the touch for content (a tap that
//   stops a moving strip shouldn't also select a row).
// - A touch that ends without dragging fires `onTouchEndedWithoutDrag` on reset, saying whether it was a
//   tap (Tweetie's _didReset → swipeView:shouldRevealItem:) or not (a vertical scroll, a cancel).
// - Release velocity is measured over the last few moves (not just the last one), and is zero if the
//   finger came to rest before lifting.
// - It's a UIPanGestureRecognizer by class only (none of its own tracking runs: these overrides don't call super), so
//   content yields to it the way it does to a scroll view's pan. SwiftUI lets a pan cancel a Button (or tap) the touch
//   began on, where any other recognizer is excluded by the button's, which begins on touch down; UISlider (SwiftUI's
//   Slider too) refuses a pan along its track that starts on its thumb, or once it's tracking. `location(in:)` and
//   `translation(in:)` answer from this recognizer's own tracking, for them.
//

import UIKit
import UIKit.UIGestureRecognizerSubclass

final class ColumnSwipeGestureRecognizer: UIPanGestureRecognizer {
    /// Touch down (swipeView:willBeginTouches:withEvent:): Tweetie stops a moving stack here.
    var onTouchDown: ((CGPoint) -> Void)?
    /// Asked at touch down (after `onTouchDown`): begin right away, claiming the touch from content.
    var beginsOnTouchDown: (() -> Bool)?
    /// A touch that went down ended without a horizontal drag (always reported, so whatever it caught can settle):
    /// `isTap` if it lifted in place (not a vertical scroll, a second finger, or a cancel).
    var onTouchEndedWithoutDrag: ((_ location: CGPoint, _ isTap: Bool) -> Void)?

    private(set) var firstLocation: CGPoint = .zero
    private(set) var location: CGPoint = .zero
    /// Recent (time, x) samples, for the release velocity.
    private var samples: [(time: TimeInterval, x: CGFloat)] = []
    private var liftTime: TimeInterval = 0
    /// A touch went down (and `onTouchDown` ran), so its end gets reported.
    private var hasTouch = false
    private var didDrag = false
    private var isTap = false

    /// How far back the release velocity looks.
    private static let velocityWindow: TimeInterval = 0.08
    /// A finger still this long before lifting has no release velocity.
    private static let restBeforeLift: TimeInterval = 0.05

    /// Horizontal finger travel since touch down.
    var translationX: CGFloat { location.x - firstLocation.x }

    /// Finger velocity at release, in points per 60 Hz frame (the unit Tweetie's physics use): the average over
    /// the last `velocityWindow` of movement, at the touches' real rate (120 Hz too), or 0 if it had stopped.
    var releaseVelocity: CGFloat {
        guard let last = samples.last, liftTime - last.time < Self.restBeforeLift,
            let first = samples.first(where: { last.time - $0.time <= Self.velocityWindow }),
            last.time > first.time
        else { return 0 }
        return (last.x - first.x) / CGFloat(last.time - first.time) / 60
    }

    override func location(in view: UIView?) -> CGPoint {
        self.view?.convert(location, to: view) ?? location
    }

    override func translation(in view: UIView?) -> CGPoint {
        guard let own = self.view else { return .zero }
        let start = own.convert(firstLocation, to: view)
        let end = own.convert(location, to: view)
        return CGPoint(x: end.x - start.x, y: end.y - start.y)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first, (event.allTouches?.count ?? touches.count) == 1, state == .possible else {
            // A second finger: an invalid transition from .began/.changed would leave the drag hanging.
            state = state == .possible ? .failed : .cancelled
            return
        }
        if touch.view is UITextView || touch.view is UITextField {
            state = .failed
            return
        }
        let point = touch.location(in: view)
        firstLocation = point
        location = point
        samples = [(touch.timestamp, point.x)]
        liftTime = touch.timestamp
        isTap = true
        hasTouch = true
        onTouchDown?(point)
        if beginsOnTouchDown?() == true {
            isTap = false
            begin()
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first else { return }
        if (event.allTouches?.count ?? 1) > 1 {
            state = state == .possible ? .failed : .cancelled
            return
        }
        record(touch)

        let dx = abs(location.x - firstLocation.x)
        let dy = abs(location.y - firstLocation.y)
        switch state {
        case .possible:
            if dy > 10, dy > dx {
                // A vertical scroll: let content have it.
                isTap = false
                state = .failed
            } else if dx > 10 {
                isTap = false
                begin()
            }
        case .began, .changed:
            state = .changed
        default:
            break
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first {
            record(touch)
            liftTime = touch.timestamp
        }
        switch state {
        case .began, .changed:
            state = .ended
        default:
            state = .failed
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        isTap = false
        samples = []
        switch state {
        case .began, .changed:
            state = .cancelled
        default:
            state = .failed
        }
    }

    private func begin() {
        state = .began
        // Refused by the delegate, it fails instead, and the touch ends as one that didn't drag.
        didDrag = state == .began
    }

    private func record(_ touch: UITouch) {
        let point = touch.location(in: view)
        location = point
        // Only moves count; a lift in place adds its time (via liftTime), not a sample.
        if let last = samples.last, last.x == point.x { return }
        samples.append((touch.timestamp, point.x))
        if let newest = samples.last?.time {
            samples.removeAll { newest - $0.time > Self.velocityWindow * 2 }
        }
    }

    override func reset() {
        super.reset()
        if hasTouch, !didDrag {
            onTouchEndedWithoutDrag?(firstLocation, isTap)
        }
        isTap = false
        hasTouch = false
        didDrag = false
        samples = []
    }
}
