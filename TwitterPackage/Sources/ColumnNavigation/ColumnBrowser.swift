// Geometry for browsing the whole history at once (opened by a root pull): the strip zoomed out, every column
// side by side on one filmstrip. `position` is the point along the filmstrip shown at the middle of the screen
// (a scroll view drives it). The navigation controller carries columns from their strip frames to these poses as
// it opens.
//

import UIKit

struct ColumnBrowsePose {
    var center: CGPoint
    var scale: CGFloat
    var alpha: CGFloat = 1
}

struct ColumnBrowseLayout {
    static let scale: CGFloat = 0.45
    private static let gap: CGFloat = 14

    var bounds: CGRect
    /// Width of the trailing vertical bar, kept clear.
    var trailingInset: CGFloat
    /// Each column's (unscaled) width, root first.
    var widths: [CGFloat]
    /// The filmstrip point at the middle of the screen (see `mid(at:)`).
    var position: CGFloat

    private var area: CGRect {
        CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width - trailingInset, height: bounds.height)
    }

    /// Where column `index`'s middle sits along the filmstrip.
    func mid(at index: Int) -> CGFloat {
        let before = widths.prefix(index).map { $0 * Self.scale + Self.gap }.reduce(0, +)
        return before + widths[index] * Self.scale / 2
    }

    /// The filmstrip's scrollable range of positions: from the first column's middle to the last one's.
    var positions: ClosedRange<CGFloat> {
        widths.isEmpty ? 0...0 : mid(at: 0)...mid(at: widths.count - 1)
    }

    func pose(at index: Int) -> ColumnBrowsePose {
        let x = area.midX + mid(at: index) - position
        // Columns far off screen aren't drawn.
        let offscreen = abs(x - area.midX) > area.width * 1.5
        return ColumnBrowsePose(center: CGPoint(x: x, y: area.midY), scale: Self.scale, alpha: offscreen ? 0 : 1)
    }
}
