import ComposableArchitecture
import Models
import SwiftUI

/// Tells a feed that marks what's seen (Notifications) whether a row shows enough of itself to count as seen (see
/// ``MarkAsViewed``). Measured against the timeline's scroll view, which keeps to the safe area its bars inset, so a
/// row behind a bar isn't seen.
struct ViewedReporting: ViewModifier {
    let id: FeedItem.ID
    let store: StoreOf<FeedFeature>

    func body(content: Content) -> some View {
        if store.marksViewed {
            content
                .onGeometryChange(for: Bool.self) { proxy in
                    guard let timeline = proxy.bounds(of: .scrollView) else { return false }
                    return MarkAsViewed.isViewed(
                        top: 0,
                        bottom: proxy.size.height,
                        visibleTop: timeline.minY,
                        visibleBottom: timeline.maxY
                    )
                } action: { isViewed in
                    store.send(.rowViewedChanged(id, isViewed: isViewed))
                }
                .onDisappear { store.send(.rowViewedChanged(id, isViewed: false)) }
        } else {
            content
        }
    }
}

extension View {
    func reportsViewed(_ id: FeedItem.ID, store: StoreOf<FeedFeature>) -> some View {
        modifier(ViewedReporting(id: id, store: store))
    }
}
