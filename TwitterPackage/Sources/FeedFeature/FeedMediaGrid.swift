import ComposableArchitecture
import Models
import SwiftUI
import TwitterUI

/// A profile's media as a grid that respects iPhone Duo's fold.
///
/// The column count is always even, so the grid divides cleanly when the device folds. While a vertical fold is active
/// across the grid, each half gets the same number of fixed columns sized to the narrower side, and the gutter between
/// the halves widens to step over the fold, so no thumbnail is ever bent.
struct FeedMediaGrid: View {
    let store: StoreOf<FeedFeature>
    @ScaledMetric private var minimumCellWidth: CGFloat = 104
    @State private var geometry = GridGeometry()
    @State private var cells = MediaCellsMemo()

    private static let spacing: CGFloat = 2

    var body: some View {
        let layout = GridLayout(geometry: geometry, minimumCellWidth: minimumCellWidth, spacing: Self.spacing)
        LazyVGrid(columns: layout.columns, spacing: Self.spacing) {
            ForEach(cells.cells(for: store.items)) { cell in
                MediaCell(cell: cell) {
                    // Looked up on tap so the post opens as it is now, not as it was when the cells were built.
                    if case .tweet(let feedTweet) = store.items[id: cell.itemID] {
                        store.send(.tweetTapped(feedTweet.tweet))
                    }
                }
                .onAppear { store.send(.rowAppeared(cell.itemID)) }
            }
        }
        .padding(.leading, layout.leadingInset)
        .padding(.trailing, layout.trailingInset)
        // Measure the width offered, so the grid's own sizing can never feed back into it.
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: GridGeometry.self) { proxy in
            GridGeometry(proxy: proxy)
        } action: { newValue in
            geometry = newValue
        }
    }
}

private struct GridGeometry: Equatable {
    /// The fold's horizontal extent in the grid's own coordinates, when it runs vertically through the grid.
    var fold: ClosedRange<CGFloat>?
    var isFoldActive = false
    var width: CGFloat = 0

    init() {}

    init(proxy: GeometryProxy) {
        width = proxy.size.width
        let division = proxy.reservedRegions(kind: .division, options: .includeInactive)
            .first { $0.frame.height > $0.frame.width }
        if let division, division.frame.minX > 0, division.frame.maxX < width {
            fold = division.frame.minX...division.frame.maxX
            isFoldActive = division.isActive
        }
    }
}

private struct GridLayout {
    var columns: [GridItem]
    var leadingInset: CGFloat = 0
    var trailingInset: CGFloat = 0

    init(geometry: GridGeometry, minimumCellWidth: CGFloat, spacing: CGFloat) {
        let fitting = Int((geometry.width + spacing) / (minimumCellWidth + spacing))
        let count = max(fitting / 2 * 2, 2)

        guard geometry.isFoldActive, let fold = geometry.fold else {
            columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: count)
            return
        }

        // Size both halves from the narrower side of the fold, then pad each half against its outer edge so the
        // widened gutter lands exactly on the fold.
        let perSide = count / 2
        let leadingSide = fold.lowerBound
        let trailingSide = geometry.width - fold.upperBound
        let cellWidth = max(
            (min(leadingSide, trailingSide) - CGFloat(perSide - 1) * spacing) / CGFloat(perSide), 1
        )
        let halfWidth = CGFloat(perSide) * cellWidth + CGFloat(perSide - 1) * spacing
        columns = (0..<count).map { index in
            GridItem(.fixed(cellWidth), spacing: index == perSide - 1 ? fold.upperBound - fold.lowerBound : spacing)
        }
        leadingInset = leadingSide - halfWidth
        trailingInset = trailingSide - halfWidth
    }
}

struct MediaGridCell: Identifiable, Equatable {
    let itemID: FeedItem.ID
    let media: Media
    /// The media's address within its post, for its menu.
    let link: URL?

    var id: String { "\(itemID)-\(media.id)" }
}

/// The grid's cells, rebuilt only when the feed's items change rather than on every body evaluation. An item's media
/// never changes under the same ID, so the IDs are enough to tell.
private final class MediaCellsMemo {
    private var ids: [FeedItem.ID] = []
    private var cells: [MediaGridCell] = []

    func cells(for items: IdentifiedArrayOf<FeedItem>) -> [MediaGridCell] {
        guard !items.ids.elementsEqual(ids) else { return cells }
        ids = Array(items.ids)
        cells = items.flatMap { item -> [MediaGridCell] in
            guard case .tweet(let feedTweet) = item else { return [] }
            let tweet = feedTweet.tweet
            return tweet.media.map { MediaGridCell(itemID: item.id, media: $0, link: tweet.mediaURL(of: $0)) }
        }
        return cells
    }
}

private struct MediaCell: View {
    let cell: MediaGridCell
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    RemoteImage(url: cell.media.previewURL(variant: "small"), pointSize: 200)
                }
                .overlay(alignment: .bottomTrailing) {
                    if cell.media.kind != .photo {
                        Glyph(cell.media.kind == .gif ? TwitterIcon.gif.rawValue : TwitterIcon.play.rawValue, size: 12)
                            .font(.caption)
                            .foregroundStyle(.mediaGlyph)
                            .padding(6)
                            .glassEffect(.regular, in: .circle)
                            .padding(6)
                    }
                }
                .clipped()
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // A long press previews the whole photo, uncropped; the menu's first action opens the post, as a tap does.
        .mediaPreview(cell.media, link: cell.link, openTitle: "View Tweet", open: action)
        .accessibilityLabel(cell.media.altText ?? (cell.media.kind == .photo ? "Image" : "Video"))
        .accessibilityHint("Opens the Tweet")
    }
}
