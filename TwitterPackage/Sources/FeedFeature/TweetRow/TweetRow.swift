import ComposableArchitecture
import Models
import SwiftUI
import TweetEngagement
import TwitterUI

package struct TweetRow: View {
    /// The corner dog-ear on liked and Retweeted posts: off for now.
    private static let showsDogEar = false

    let item: FeedTweet
    let engagement: Engagement
    /// The quoted post's, for its own menu.
    var quotedEngagement: Engagement?
    let store: StoreOf<FeedFeature>
    var isFocused = false
    @Environment(\.tweetMetrics) private var metrics
    @SharedReader(.postRowStyle) private var style

    private var tweet: Tweet { item.tweet }

    /// The style in effect for this column; never ``PostRowStyle/automatic``.
    private var columnStyle: PostRowStyle { style.resolved(in: metrics) }

    /// The focused post of a thread is always stacked, as in Twitter.
    private var layout: PostRowStyle { isFocused ? .stacked : columnStyle }

    package var body: some View {
        VStack(alignment: .leading, spacing: 4 * metrics.unit) {
            if let reposter = item.repostedBy {
                ContextLabel(symbol: TwitterIcon.repostStroke.rawValue, text: Text("\(reposter.name) retweeted"))
            } else if let context = item.socialContext {
                ContextLabel(symbol: item.socialSymbol ?? "sparkles", text: Text(verbatim: context))
            }

            if layout == .stacked {
                StackedTweetLayout(
                    item: item,
                    engagement: engagement,
                    quotedEngagement: quotedEngagement,
                    isFocused: isFocused,
                    store: store
                )
            } else {
                ClassicTweetLayout(
                    item: item,
                    engagement: engagement,
                    quotedEngagement: quotedEngagement,
                    store: store
                )
            }
        }
        .padding(.horizontal, metrics.sideInset)
        .padding(.top, item.connectsAbove ? 4 : metrics.topInset)
        // The focused post's action bar is its bottom edge.
        .padding(.bottom, item.connectsBelow || isFocused ? 0 : metrics.actionBarBottomInset)
        .foregroundStyle(.twitterPrimary)
        .overlay(alignment: .topTrailing) {
            ZStack(alignment: .topTrailing) {
                if Self.showsDogEar, engagement.like.isOn || engagement.repost.isOn {
                    DogEar(isLiked: engagement.like.isOn, isReposted: engagement.repost.isOn)
                        .transition(.scale(scale: 0, anchor: .topTrailing))
                }
            }
            .animation(.spring(duration: 0.3, bounce: 0.35), value: engagement.like.isOn)
            .animation(.spring(duration: 0.3, bounce: 0.35), value: engagement.repost.isOn)
        }
        // Opaque, so the post lifted for its context menu isn't see-through. Twitter's pale blue while unread.
        .background(item.isUnread ? AnyShapeStyle(.twitterUnread) : AnyShapeStyle(.background))
        .contentShape(.rect)
        .onTapGesture { store.send(.tweetTapped(tweet)) }
        .contextMenu {
            TweetMenu(tweet: tweet, engagement: engagement, store: store)
        } preview: {
            ThreadPreview(tweet: tweet, store: store)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Open Tweet") { store.send(.tweetTapped(tweet)) }
    }
}

private struct ContextLabel: View {
    let symbol: String
    /// Localized when it's ours ("… retweeted"), verbatim when Twitter wrote it.
    let text: Text
    @Environment(\.tweetMetrics) private var metrics

    var body: some View {
        HStack(spacing: metrics.gutter) {
            Glyph(symbol, size: 16)
                .frame(width: metrics.avatarSize, alignment: .trailing)

            text.lineLimit(1)
        }
        .font(metrics.font(.subtext2, weight: .bold))
        .foregroundStyle(.twitterSecondary)
    }
}
