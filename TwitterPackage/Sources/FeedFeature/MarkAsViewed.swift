import Foundation

/// When a row counts as seen, by the rule Twitter's own app marks notifications read with (`TFNMarkAsViewedHelper`):
/// once the timeline has sat still on it, with each of its edges either on screen (give or take a little) or at
/// least half of it showing on that edge's side.
enum MarkAsViewed {
    /// How long the timeline sits still on its rows before they count as seen. Coming to rest after a scroll counts at
    /// once.
    static let settleDelay: Duration = .milliseconds(500)
    /// An edge cut off by less than this still counts as on screen.
    static let edgeTolerance: CGFloat = 25

    /// Whether a row from `top` to `bottom` counts as seen in a timeline showing from `visibleTop` to
    /// `visibleBottom`, all in the same vertical space, the bars already taken out of what's showing.
    static func isViewed(top: CGFloat, bottom: CGFloat, visibleTop: CGFloat, visibleBottom: CGFloat) -> Bool {
        guard bottom > visibleTop, top < visibleBottom else { return false }
        let middle = (top + bottom) / 2
        let topIsSeen = visibleTop - top < edgeTolerance || middle >= visibleTop
        let bottomIsSeen = bottom - visibleBottom < edgeTolerance || middle <= visibleBottom
        return topIsSeen && bottomIsSeen
    }
}
