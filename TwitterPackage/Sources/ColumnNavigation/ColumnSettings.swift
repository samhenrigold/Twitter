// Live-tunable knobs, edited from the debug panel. Defaults are Tweetie's constants.
//

import UIKit

@MainActor
package final class ColumnSettings {
    package static let shared = ColumnSettings()
    static let didChange = Notification.Name("ColumnSettingsDidChange")

    /// Keep the root's leading strip showing under the stack, like Tweetie's sidebar.
    var pinsRoot = true { didSet { notify() } }
    /// How much of the root shows when pinned (Tweetie: 72).
    var stackInset: CGFloat = 72 { didSet { notify() } }
    /// Per-frame velocity retention after a throw (Tweetie: 0.7).
    var throwFriction: CGFloat = 0.7 { didSet { notify() } }
    /// Distance a column must travel (down, or off trailing by back swipe) before release commits a pop.
    var popDistance: CGFloat = 110 { didSet { notify() } }
    /// Root pull needed to clear everything back to it (Tweetie: 120; farther here, leaving room before it to
    /// release into the overview).
    var throwawayDistance: CGFloat = 300 { didSet { notify() } }
    var showsOverlay = false { didSet { notify() } }
    /// On the Duo, the focused column's bar buttons move to the vertical bar.
    var verticalBarItems = true { didSet { notify() } }
    /// The focused column places its own buttons in the vertical bar (as SwiftUI does with a vertical-preferred toolbar
    /// item), told by `setColumnBarItemsShown(false)`; off, the navigation controller's toolbar hosts stand-ins of them.
    package var columnsPlaceVerticalBarItems = false { didSet { notify() } }
    /// Swiping a column off by its leading seam (or the screen's leading edge) pops it and everything after it,
    /// with it shrinking, fading and blurring on the way. Off for cards for now (always on edge to edge).
    var cardBackSwipeEnabled = false { didSet { notify() } }
    /// Columns are cards laid out in the layout margins on a black void (off: Tweetie's edge-to-edge panels).
    var cardStyle = true { didSet { notify() } }
    /// Space between neighboring cards (0: they touch at their sides).
    var cardGap: CGFloat = 0 { didSet { notify() } }
    /// Extra inset beyond the layout margins, at the top and sides.
    var cardInset: CGFloat = 8 { didSet { notify() } }
    /// Radius of a card's top corners (its bottom runs off the display).
    var cardCornerRadius: CGFloat = 8 { didSet { notify() } }
    /// Releasing a root pull partway (the history peeking out) opens the overview (off: it springs back; only a
    /// full pull clears).
    var overviewEnabled = true { didSet { notify() } }

    /// Where covered columns pile up.
    var effectiveStackInset: CGFloat { pinsRoot ? stackInset : 0 }

    private func notify() {
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}
