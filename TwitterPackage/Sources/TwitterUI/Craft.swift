import SwiftUI

// Small details carried over from Twitter for iPad (2012), drawn flat: a folded corner for your mark on a post, a
// band where the timeline has a gap, a fleuron at its end.

/// Your mark on a post, like folding down the corner of a page: orange for a like, green for a repost, split
/// diagonally for both. Drawn in the row's top-trailing corner.
package struct DogEar: View {
    let isLiked: Bool
    let isReposted: Bool

    package init(isLiked: Bool, isReposted: Bool) {
        self.isLiked = isLiked
        self.isReposted = isReposted
    }

    package var body: some View {
        Canvas { context, size in
            let side = size.width
            var corner = Path()
            corner.move(to: .zero)
            corner.addLine(to: CGPoint(x: side, y: 0))
            corner.addLine(to: CGPoint(x: side, y: side))
            corner.closeSubpath()
            let start = CGPoint(x: side, y: 0)
            let end = CGPoint(x: side / 2, y: side / 2)
            if isLiked, isReposted {
                // The like takes the upper half of the fold, the repost the lower.
                var upper = Path()
                upper.move(to: .zero)
                upper.addLine(to: CGPoint(x: side, y: 0))
                upper.addLine(to: CGPoint(x: side / 2, y: side / 2))
                upper.closeSubpath()
                context.fill(corner, with: .linearGradient(.dogEarRepost, startPoint: start, endPoint: end))
                context.fill(upper, with: .linearGradient(.dogEarLike, startPoint: start, endPoint: end))
            } else {
                context.fill(
                    corner,
                    with: .linearGradient(isLiked ? .dogEarLike : .dogEarRepost, startPoint: start, endPoint: end)
                )
            }
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }
}

extension Gradient {
    fileprivate static let dogEarLike = Gradient(colors: [
        Color(.dogEarLikeStart), Color(.dogEarLikeEnd)
    ])
    fileprivate static let dogEarRepost = Gradient(colors: [
        Color(.dogEarRepostStart), Color(.dogEarRepostEnd)
    ])
}

/// A tear in the timeline: something is missing here. A band of grouped background between hairlines.
package struct GapGroove: View {
    package init() {}

    package var body: some View {
        Rectangle()
            .fill(Color(.secondarySystemBackground))
            .overlay(alignment: .top) { Divider() }
            .overlay(alignment: .bottom) { Divider() }
    }
}

/// The end of a timeline or thread, said calmly: a faint fleuron.
package struct EndOfTimeline: View {
    package init() {}

    package var body: some View {
        Image(systemName: "fleuron.fill")
            .font(.system(size: 34))
            .foregroundStyle(.quaternary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .accessibilityLabel("End of timeline")
    }
}
