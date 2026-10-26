// The sheet's trick for a column's own scroll view: scrolled to the top, keep pulling down and the drag carries
// the whole column down instead (to dismiss it); push back up and it scrolls again.
//
// As in _UISheetInteraction (_scrollView:adjustedUnconstrainedOffsetForUnconstrainedOffset:…), one number decides
// everything: where the drag would put the content offset unconstrained. The part past the top moves the column,
// the rest scrolls, and nothing is re-baselined at the boundary, so neither hand-off jumps. While the column
// moves, the scroll view is pinned at the top without bouncing.
//

import UIKit

@MainActor
final class ScrollDismissHandoff: NSObject {
    /// The scroll view started being dragged (scrolling its content).
    var scrollBegan: () -> Void = {}
    /// Asked when a drag first reaches past the top; return false to leave the scroll view alone for the rest of
    /// the drag (engaging later would take everything pulled past the top at once, in a jump).
    var shouldBegin: () -> Bool = { true }
    var began: () -> Void = {}
    /// Distance pulled past the top (≥ 0).
    var changed: (CGFloat) -> Void = { _ in }
    /// Release, with the finger's vertical velocity (points per second).
    var ended: (CGFloat) -> Void = { _ in }
    var cancelled: () -> Void = {}

    private(set) weak var scrollView: UIScrollView?
    private var startY: CGFloat = 0
    private var isEngaged = false
    private var isRefused = false
    private var savedBounces = true

    init(scrollView: UIScrollView) {
        self.scrollView = scrollView
        super.init()
        // Added after the scroll view's own target, so this runs after it scrolls each frame.
        scrollView.panGestureRecognizer.addTarget(self, action: #selector(handlePan(_:)))
    }

    /// Stops listening (gesture recognizers don't retain their targets, so this must run before it's released).
    func detach() {
        scrollView?.panGestureRecognizer.removeTarget(self, action: #selector(handlePan(_:)))
    }

    isolated deinit {
        // The scroll view can outlive this (gesture recognizers don't retain their targets).
        detach()
    }

    private var topY: CGFloat { -(scrollView?.adjustedContentInset.top ?? 0) }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        guard let scrollView else { return }
        // Window coordinates: the scroll view itself moves with the column once it's carrying it.
        let translation = pan.translation(in: nil).y
        switch pan.state {
        case .began:
            // The scroll view's own baseline: where this drag would put the offset with nothing in the way.
            startY = scrollView.contentOffset.y + translation
            isRefused = false
            scrollBegan()
        case .changed:
            let pastTop = topY - (startY - translation)
            if pastTop > 0 {
                if !isEngaged {
                    guard !isRefused else { return }
                    guard shouldBegin() else {
                        isRefused = true
                        return
                    }
                    isEngaged = true
                    savedBounces = scrollView.bounces
                    scrollView.bounces = false
                    began()
                }
                scrollView.contentOffset.y = topY
                changed(pastTop)
            } else if isEngaged {
                // Back above the top: the column rests and the content scrolls from exactly the top.
                changed(0)
            }
        case .ended:
            guard isEngaged else { return }
            let velocity = pan.velocity(in: nil).y
            if velocity > 0 { scrollView.contentOffset.y = topY }
            finish()
            ended(velocity)
        case .cancelled, .failed:
            guard isEngaged else { return }
            finish()
            cancelled()
        default:
            break
        }
    }

    private func finish() {
        isEngaged = false
        // After this frame, so the release can't bounce off the top.
        DispatchQueue.main.async { [weak self] in
            guard let self, let scrollView else { return }
            scrollView.bounces = savedBounces
        }
    }
}
