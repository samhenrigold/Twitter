import ComposableArchitecture
import Models
import SwiftUI
import TweetEngagement
import TwitterUI

/// One view per element (the divider lives inside the row) so the lazy stack's identity stays one-to-one with items.
struct FeedRows: View {
    let store: StoreOf<FeedFeature>
    /// Which of the feed's items: a thread lays out the conversation above its focused post apart from the rest.
    var range: Range<Int>?

    var body: some View {
        ForEach(range.map { store.items.elements[$0] } ?? store.items.elements[...]) { item in
            FeedItemRow(
                item: item,
                engagement: item.tweets.first.map { store.engagements.engagement(for: $0) },
                quotedEngagement: item.tweets.dropFirst().first.map { store.engagements.engagement(for: $0) },
                isFocused: item.id == store.focusedItemID,
                store: store
            )
            .onAppear { store.send(.rowAppeared(item.id)) }
        }
    }
}

private struct FeedItemRow: View {
    let item: FeedItem
    let engagement: Engagement?
    /// The quoted post's, for its own menu.
    let quotedEngagement: Engagement?
    let isFocused: Bool
    let store: StoreOf<FeedFeature>
    @Environment(\.tweetMetrics) private var metrics
    @SharedReader(.postRowStyle) private var style

    var body: some View {
        VStack(spacing: 0) {
            switch item {
            case .notification(let notification):
                NotificationRow(notification: notification, engagement: engagement, store: store)
            case .tweet(let feedTweet):
                TweetRow(
                    item: feedTweet,
                    engagement: engagement ?? Engagement(tweet: feedTweet.tweet),
                    quotedEngagement: quotedEngagement,
                    store: store,
                    isFocused: isFocused
                )
            case .tombstone(let tombstone):
                TombstoneView(tombstone: tombstone)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            case .showMore(let cursor):
                ShowMoreRow(
                    cursor: cursor,
                    isLoading: store.loadingShowMoreIDs.contains(item.id)
                ) {
                    store.send(.showMoreButtonTapped(cursor))
                }
            }

            if !runsThreadLineThrough {
                TwitterDivider()
            }
        }
    }
}

extension FeedItemRow {
    /// Whether the line under this post's avatar runs on into the next post of its thread, which it joins without a
    /// separator. Stacked rows have no avatar column for the line, so they keep theirs.
    fileprivate var runsThreadLineThrough: Bool {
        guard case .tweet(let feedTweet) = item, feedTweet.connectsBelow, !isFocused else { return false }
        return style.resolved(in: metrics) != .stacked
    }
}

/// A tappable "Show more replies" row that loads the rest of a conversation in its place.
private struct ShowMoreRow: View {
    let cursor: ShowMoreCursor
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                }

                Text(cursor.label)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background { GapGroove() }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}
