import ComposableArchitecture
import Models
import SwiftUI
import TwitterUI

/// A conversation that keeps its focused post pinned to the top of the viewport.
///
/// The thread opens on the focused post alone, and the conversation above it loads in after it's on screen. The
/// scroll position is bound to the focused post's identity, so rows arriving or resizing above it move the content
/// offset rather than the post, until the person scrolls on their own. The conversation above is laid out eagerly,
/// so its height is measured rather than estimated, and the focused post and its replies are at least a viewport
/// tall, so the post can reach the top however few replies it has.
package struct ThreadView: View {
    let store: StoreOf<FeedFeature>
    @Environment(\.columnBarPlacement) private var columnBarPlacement

    package init(store: StoreOf<FeedFeature>) {
        self.store = store
    }

    @State private var hasUserScrolled = false
    @State private var position = ScrollPosition(idType: FeedItem.ID.self)
    @State private var viewportHeight: CGFloat = 0

    package var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Rarely more than a few posts, and laid out in full: a lazy stack would estimate the heights of
                // the ones it hasn't made yet, and correct them, moving the focused post, as they're scrolled to.
                VStack(spacing: 0) {
                    FeedRows(store: store, range: 0..<store.focusedIndex)
                }
                .scrollTargetLayout()

                LazyVStack(spacing: 0) {
                    FeedRows(store: store, range: store.focusedIndex..<store.items.count)

                    FeedFooter(store: store)
                }
                .scrollTargetLayout()
                // Sized in layout, the moment the replies or the viewport change, never a frame behind them.
                .frame(minHeight: viewportHeight, alignment: .top)
            }
            .readableContentWidth()
        }
        .scrollPosition($position, anchor: .top)
        // The container is what's visible between the bars: the insets the scroll view runs under them by are
        // outside it, already.
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.containerSize.height
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
        .feedInteractions(store: store)
        .safeAreaBar(edge: .bottom) {
            if let tweet = store.focusedTweet, tweet.viewerCanReply {
                ReplyBar(tweet: tweet) { store.send(.replyButtonTapped(tweet)) }
            }
        }
        .toolbar {
            if store.focusedTweet != nil {
                ColumnMenuToolbarItem("More", placement: columnBarPlacement) {
                    ThreadMenuItems(store: store)
                }
            }
        }
    }
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
