import ComposableArchitecture
import Models
import SwiftUI
import TwitterUI

/// A conversation that keeps its focused post pinned to the top of the viewport.
///
/// Ancestors load in above the focused post after it's already on screen, so the scroll position is bound by item
/// identity and re-aimed whenever the head of the thread changes, until the person scrolls on their own. A trailing
/// spacer makes room for the focused post to reach the top even when it has few replies.
package struct ThreadView: View {
    let store: StoreOf<FeedFeature>
    @Environment(\.columnBarItemsInVerticalBar) private var columnBarItemsInVerticalBar

    package init(store: StoreOf<FeedFeature>) {
        self.store = store
    }

    @State private var hasUserScrolled = false
    /// Positions measured during layout. Not observed: recording them must never re-render the thread, or the spacer
    /// they size would move the rows that measured them, every frame (an update loop).
    @State private var measurements = ThreadMeasurements()
    @State private var position = ScrollPosition(idType: FeedItem.ID.self)
    @State private var spacerHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    package var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                LazyVStack(spacing: 0) {
                    FeedRows(store: store)

                    FeedFooter(store: store)
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.frame(in: .named(ThreadView.coordinateSpace)).maxY
                        } action: { maxY in
                            measurements.contentMaxY = maxY
                        }
                }
                .scrollTargetLayout()

                Color.clear
                    .frame(height: spacerHeight)
                    .transaction { $0.disablesAnimations = true }
            }
            .readableContentWidth()
            .coordinateSpace(.named(ThreadView.coordinateSpace))
            .environment(\.threadMeasurements, measurements)
        }
        .scrollPosition($position, anchor: .top)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.containerSize.height - geometry.contentInsets.top - geometry.contentInsets.bottom
        } action: { _, height in
            viewportHeight = height
        }
        .onScrollPhaseChange { _, phase in
            if phase == .interacting { hasUserScrolled = true }
        }
        .onChange(of: store.items.ids.first, initial: true) {
            guard !hasUserScrolled, let focusedID = store.focusedItemID else { return }
            position.scrollTo(id: focusedID, anchor: .top)
        }
        // Resized only when the thread's content or the viewport changes, after layout has settled.
        .task(
            id: SpacerInputs(
                itemCount: store.items.count,
                // Heights that change without the item count: the footer swapping its spinner for the end mark.
                isLoading: store.isLoading,
                viewportHeight: viewportHeight
            )
        ) {
            // A superseded task stops here instead of resizing with stale inputs.
            do {
                try await Task.sleep(for: .milliseconds(100))
                let height = measurements.spacerHeight(viewportHeight: viewportHeight)
                if abs(height - spacerHeight) > 1 { spacerHeight = height }
            } catch {}
        }
        .feedInteractions(store: store)
        .safeAreaBar(edge: .bottom) {
            if let tweet = store.focusedTweet, tweet.viewerCanReply {
                ReplyBar(tweet: tweet) { store.send(.replyButtonTapped(tweet)) }
            }
        }
        .toolbar {
            if store.focusedTweet != nil {
                ColumnMenuToolbarItem("More", isInVerticalBar: columnBarItemsInVerticalBar) {
                    ThreadMenuItems(store: store)
                }
            }
        }
    }
}

extension ThreadView {
    nonisolated static let coordinateSpace = "thread"
}

/// Along the bottom of a post's page, as in Twitter: your avatar and "Tweet your reply", which opens the reply.
private struct ReplyBar: View {
    let tweet: Tweet
    let reply: () -> Void
    @SharedReader(.viewer) private var viewer

    var body: some View {
        Button(action: reply) {
            HStack(spacing: 10) {
                if let viewer {
                    Avatar(user: viewer, size: 28)
                }

                Text("Tweet your reply")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .accessibilityLabel("Reply to @\(tweet.author.screenName)")
    }
}

/// A thread's "…" menu: the focused post's.
package struct ThreadMenuItems: View {
    let store: StoreOf<FeedFeature>

    package init(store: StoreOf<FeedFeature>) {
        self.store = store
    }

    package var body: some View {
        if let tweet = store.focusedTweet {
            TweetMenu(tweet: tweet, engagement: store.engagements.engagement(for: tweet), store: store)
        }
    }
}

extension FeedFeature.State {
    /// The post a thread is about.
    package var focusedTweet: Tweet? {
        focusedItemID.flatMap { items[id: $0]?.tweets.first }
    }
}

/// Written by the rows and footer as they lay out, read only when the spacer is resized.
@MainActor
final class ThreadMeasurements {
    var contentMaxY: CGFloat?
    var focusedMinY: CGFloat?

    /// Room below the content for the focused post to reach the top of the viewport.
    func spacerHeight(viewportHeight: CGFloat) -> CGFloat {
        guard let contentMaxY, let focusedMinY else { return 0 }
        return max(viewportHeight - (contentMaxY - focusedMinY), 0).rounded()
    }
}

private struct SpacerInputs: Equatable {
    var itemCount: Int
    var isLoading: Bool
    var viewportHeight: CGFloat
}

extension EnvironmentValues {
    /// Where the focused row reports its position inside a thread; `nil` everywhere else.
    @Entry var threadMeasurements: ThreadMeasurements? = nil
}
