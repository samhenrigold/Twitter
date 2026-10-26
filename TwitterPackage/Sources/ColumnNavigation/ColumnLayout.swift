// Pure geometry for Tweetie-style stacked columns.
//
// Columns sit on a horizontal strip in stack order and `offset` scrolls the strip toward
// leading. A column that would pass the stack position instead piles up there, under the
// newer columns (Tweetie: ABSwipeColumnViewController -_updateLayout:). Every covered column
// lands on the same x; only the newest of them is drawn, as a dimmed strip.
//
// When the display is partially folded (`fold` set) and there are at least two columns,
// the fold wins: columns split at the middle of the hinge and scroll stops land on whole pages,
// so the two visible columns meet at the hinge. With a pinned root, the root's peek stays on
// the leading edge and the left page's column narrows to fit between it and the hinge.
//

import CoreGraphics

struct ColumnLayout {
    /// Preferred width of each column, root first.
    var widths: [CGFloat]
    /// Width available for content (excludes the trailing vertical bar).
    var availableWidth: CGFloat
    /// Extra width given to the top column so it reaches under the vertical bar.
    var trailingInset: CGFloat
    var height: CGFloat
    /// Where covered columns pile up. Tweetie keeps 72pt of its root (sidebar) showing; 0 piles them at the edge.
    var stackInset: CGFloat
    /// The active hinge division region's horizontal extent, if partially folded.
    var fold: ClosedRange<CGFloat>?
    /// Cards: the strip starts at `cardLeading` (in view coordinates) and cards start `cardTop` down, running off
    /// the bottom. Each column gives up `cardGap` of its width so neighbors keep that gap; the caller makes
    /// `availableWidth` `cardGap` wider than the space between the margins, so the outermost edges land on them.
    /// All zero: Tweetie's edge-to-edge panels.
    var cardLeading: CGFloat = 0
    var cardTop: CGFloat = 0
    var cardGap: CGFloat = 0

    /// Half-page geometry while folded: distance between page origins, and each column's width.
    private var foldPages: (pitch: CGFloat, width: CGFloat)? {
        guard let fold, widths.count > 1 else { return nil }
        let fullWidth = availableWidth + trailingInset
        let hinge = (fold.lowerBound + fold.upperBound) / 2
        return (hinge, max(hinge, fullWidth - hinge))
    }

    var isFolded: Bool { foldPages != nil }

    /// Effective widths: none wider than fits beside the stack position (or it could never be shown in full); if
    /// everything fits, the top column flexes to fill the remainder.
    var resolvedWidths: [CGFloat] {
        if let pages = foldPages {
            return Array(repeating: pages.width, count: widths.count)
        }
        var resolved = widths.indices.map { min(widths[$0], max(availableWidth - minimumX(at: $0), 1)) }
        let total = resolved.reduce(0, +)
        if let last = resolved.indices.last, total < availableWidth {
            resolved[last] += availableWidth - total
        }
        return resolved
    }

    /// Strip position of each column's leading edge with no scrolling.
    var stripOrigins: [CGFloat] {
        if let pages = foldPages {
            return widths.indices.map { CGFloat($0) * pages.pitch }
        }
        var x: CGFloat = 0
        return resolvedWidths.map { width in
            defer { x += width }
            return x
        }
    }

    /// Scrolling past this shows the newest column flush against the trailing edge.
    var maxOffset: CGFloat {
        if let pages = foldPages {
            return CGFloat(widths.count - 2) * pages.pitch
        }
        return max(0, resolvedWidths.reduce(0, +) - availableWidth)
    }

    /// The stack position: leftmost x a column may occupy before it piles under its successor.
    /// The root never moves left of the edge.
    func minimumX(at index: Int) -> CGFloat {
        index == 0 ? 0 : stackInset
    }

    /// Where a column's card sits when it's at the stack position.
    func pileX(at index: Int) -> CGFloat {
        minimumX(at: index) + cardLeading
    }

    /// A column's card: inset from the sides and top; it runs off the bottom edge.
    private func card(_ frame: CGRect) -> CGRect {
        CGRect(
            x: frame.minX + cardLeading, y: frame.minY + cardTop, width: frame.width - cardGap,
            height: frame.height - cardTop)
    }

    /// Column frames for a scroll offset. `detach` slides the columns from `detachFrom` onward toward trailing
    /// (just the top column for a back swipe; everything after the root to pop to root).
    func frames(offset: CGFloat, detach: CGFloat = 0, detachFrom: Int? = nil) -> [CGRect] {
        let overscroll = offset - maxOffset
        guard overscroll > 0, widths.count > 1 else {
            return framesInRange(offset: offset, detach: detach, detachFrom: detachFrom)
        }
        // Past the end, the newest column keeps sliding with the finger over the columns before it, with rubber-band
        // resistance past the stack position instead of stopping dead there.
        var frames = framesInRange(offset: maxOffset, detach: detach, detachFrom: detachFrom)
        let last = frames.count - 1
        let floor = pileX(at: last)
        var x = frames[last].minX - overscroll
        if x < floor { x = floor - Self.rubberBand(floor - x, dimension: frames[last].width) }
        frames[last].origin.x = x
        return frames
    }

    /// UIKit's rubber band (coefficient 0.55): `overshoot` past a limit approaches `dimension` but never reaches it.
    private static func rubberBand(_ overshoot: CGFloat, dimension: CGFloat) -> CGFloat {
        guard dimension > 0 else { return 0 }
        return dimension * (1 - 1 / (overshoot * 0.55 / dimension + 1))
    }

    private func framesInRange(offset: CGFloat, detach: CGFloat, detachFrom: Int?) -> [CGRect] {
        if let pages = foldPages {
            return foldedFrames(offset: offset, pages: pages, detach: detach, detachFrom: detachFrom).map(card)
        }
        let widths = resolvedWidths
        let folded = isFolded
        let firstDetached = detachFrom ?? widths.count - 1
        return zip(stripOrigins, widths).enumerated().map { index, column in
            let (origin, width) = column
            // The root is the anchor: it never moves, even when the strip is pulled past it (offset < 0).
            var x = index == 0 ? 0 : max(origin - offset, minimumX(at: index))
            let isTop = index == widths.count - 1
            if index >= firstDetached { x += detach }
            // Folded pages already span to the display edge; otherwise the top column reaches under the vertical bar.
            let extra = isTop && !folded ? trailingInset : 0
            return card(CGRect(x: x, y: 0, width: width + extra, height: height))
        }
    }

    /// Book pages: column i spans [i·pitch, (i+1)·pitch] on the strip. A column reaching the stack position stops
    /// there and narrows (its trailing edge keeps moving with the strip), so the left page's column always ends at
    /// the hinge, where the next one starts; it never narrows past one page beside the root's peek. The top column
    /// reaches the display's trailing edge.
    private func foldedFrames(
        offset: CGFloat, pages: (pitch: CGFloat, width: CGFloat), detach: CGFloat, detachFrom: Int?
    ) -> [CGRect] {
        let fullWidth = availableWidth + trailingInset
        let count = widths.count
        let firstDetached = detachFrom ?? count - 1
        return (0..<count).map { index in
            let start = CGFloat(index) * pages.pitch - offset
            var x = index == 0 ? 0 : max(start, minimumX(at: index))
            var width: CGFloat
            if index == count - 1 {
                width = max(fullWidth - x, pages.pitch - minimumX(at: index))
            } else {
                // On the right page, no wider than the display leaves (that page can be narrower than the left).
                width = min(max(start + pages.pitch - x, pages.pitch - minimumX(at: index)), fullWidth - x)
            }
            if index == 0 { width = pages.pitch }
            if index >= firstDetached { x += detach }
            return CGRect(x: x, y: 0, width: width, height: height)
        }
    }

    /// The column at the leading spot (just after the pinned root, or the left page when folded): what a change of
    /// layout (folding, unfolding) should keep in place. The root, if the strip is at its start.
    func leadingColumn(offset: CGFloat) -> Int {
        if let pages = foldPages {
            return min(max(Int((offset / pages.pitch).rounded()), 0), widths.count - 1)
        }
        guard offset > 0.5 else { return 0 }
        let frames = frames(offset: offset)
        return frames.indices.dropFirst().first { index in
            let visibleEnd = index + 1 < frames.count ? frames[index + 1].minX : frames[index].maxX
            return visibleEnd - frames[index].minX >= frames[index].width * 0.5
        } ?? frames.count - 1
    }

    /// The scroll offset that puts column `index` at the leading spot (as far as the strip allows).
    func leadingOffset(for index: Int) -> CGFloat {
        guard widths.indices.contains(index) else { return maxOffset }
        let target = foldPages.map { CGFloat(index) * $0.pitch } ?? stripOrigins[index] - minimumX(at: index)
        return min(max(target, 0), maxOffset)
    }

    /// Columns piled at the stack position under a newer column, oldest first. Tweetie draws only the last
    /// of these (plus its root peek); the rest are fully covered.
    func stackedIndices(in frames: [CGRect]) -> [Int] {
        frames.indices.dropLast().filter { index in
            frames[index].minX <= pileX(at: index) + 0.5 && frames[index + 1].minX < frames[index].maxX - 0.5
        }
    }

    /// Snap points (after Tweetie's swipePointsForSwipeView:): the start, each non-top column from 1 on resting at
    /// the stack position, and the end of the strip.
    var stopOffsets: [CGFloat] {
        let limit = maxOffset
        if let pages = foldPages {
            return (0...max(0, widths.count - 2)).map { CGFloat($0) * pages.pitch }
        }
        // One detent per column (resting at the leading spot, just after the root's peek) and the end of the strip.
        // Tweetie also stopped with each column's trailing edge at the screen's, but next to a neighbor's leading
        // stop that lands on nearly the same view, so a swipe seemed to go nowhere. Stops closer than
        // minimumStopSpacing to the next one are dropped for the same reason.
        let origins = stripOrigins
        var stops: [CGFloat] = [0, limit]
        for index in origins.indices.dropFirst() where index < origins.count - 1 {
            stops.append(origins[index] - minimumX(at: index))
        }
        var kept: [CGFloat] = []
        for stop in Set(stops.map { min(max($0, 0), limit).rounded() }).sorted(by: >) {
            // From the end down, so the end of the strip always survives.
            if let last = kept.last, last - stop < Self.minimumStopSpacing, stop > 0 { continue }
            kept.append(stop)
        }
        return kept.reversed()
    }

    /// Detents closer than this show nearly the same columns; only the later one is kept.
    static let minimumStopSpacing: CGFloat = 60

    /// Tweetie's stop choice (swipeView:willSwipeToOffset:throwing:): a throw goes to the stop nearest the
    /// projected offset among those strictly past the last resting stop in the throw's direction, so a flick
    /// always advances at least one stop; otherwise the stop nearest the proposed offset.
    /// With a pinned root (Tweetie's sidebar), fewer than three columns and room for both, there's nothing to
    /// scroll. (Tweetie's columns always fit two across; when the newest doesn't, as in portrait, it scrolls.)
    func restingOffset(proposed: CGFloat, lastStop: CGFloat, throwing: Bool) -> CGFloat {
        if hasNothingToScroll { return 0 }
        let stops = stopOffsets
        guard !stops.isEmpty else { return 0 }
        func nearest(_ candidates: [CGFloat], to value: CGFloat) -> CGFloat? {
            candidates.min { abs($0 - value) < abs($1 - value) }
        }
        if throwing {
            let forward = proposed > lastStop
            let ahead = stops.filter { forward ? $0 > lastStop + 0.5 : $0 < lastStop - 0.5 }
            return nearest(ahead, to: proposed) ?? nearest(stops, to: lastStop)!
        }
        return nearest(stops, to: proposed)!
    }

    /// The strip rests at its start regardless of drags: a pinned root and one column beside it that fits.
    var hasNothingToScroll: Bool {
        stackInset > 0 && !isFolded && widths.count < 3 && maxOffset < 0.5
    }

    /// The smallest scroll that shows column `index` in full (with its stack position), like Tweetie's _reveal:.
    func revealOffset(for index: Int, from offset: CGFloat) -> CGFloat {
        if let pages = foldPages {
            // Whole pages: if the column isn't on either page, turn just far enough to bring it onto one.
            let left = Int((offset / pages.pitch).rounded())
            let page = index < left ? index : index > left + 1 ? index - 1 : left
            return min(max(CGFloat(page) * pages.pitch, 0), maxOffset)
        }
        let origins = stripOrigins
        let widths = resolvedWidths
        let minX = origins[index] - minimumX(at: index)
        let maxX = origins[index] + widths[index]
        var target = offset
        if minX < offset {
            target = minX
        } else if maxX > offset + availableWidth {
            target = maxX - availableWidth
        }
        return min(max(target, 0), maxOffset)
    }
}
