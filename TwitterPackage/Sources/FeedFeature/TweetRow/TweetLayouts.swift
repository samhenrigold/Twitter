import ComposableArchitecture
import Models
import SwiftUI
import TweetEngagement
import TwitterUI

/// Twitter's timeline row: the avatar (and the thread line under it) in a column of its own, the author line and
/// the post beside it.
struct ClassicTweetLayout: View {
    let item: FeedTweet
    let engagement: Engagement
    let quotedEngagement: Engagement?
    let store: StoreOf<FeedFeature>
    @Environment(\.tweetMetrics) private var metrics

    private var tweet: Tweet { item.tweet }

    var body: some View {
        HStack(alignment: .top, spacing: metrics.gutter) {
            VStack(spacing: 0) {
                AvatarButton(author: tweet.author, store: store)

                if item.connectsBelow {
                    ThreadConnector()
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2 * metrics.unit) {
                    AuthorLine(user: tweet.author, date: tweet.createdAt)

                    if item.showsReplyingTo {
                        ReplyingToLine(screenNames: tweet.replyingTo)
                    }
                }

                PostContent(
                    item: item,
                    engagement: engagement,
                    quotedEngagement: quotedEngagement,
                    isFocused: false,
                    store: store
                )
                .padding(.top, tweet.text.isEmpty ? metrics.mediaTextMargin : metrics.authorBodyMargin)
            }
        }
    }
}

/// The avatar beside the name over the handle, and the post under both at the row's full width.
struct StackedTweetLayout: View {
    let item: FeedTweet
    let engagement: Engagement
    let quotedEngagement: Engagement?
    let isFocused: Bool
    let store: StoreOf<FeedFeature>
    @Environment(\.tweetMetrics) private var metrics

    private var tweet: Tweet { item.tweet }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: metrics.gutter) {
                AvatarButton(author: tweet.author, store: store)

                // The focused post's time is spelled out above its action bar instead.
                AuthorLine(user: tweet.author, date: isFocused ? nil : tweet.createdAt, layout: .stacked)
            }

            if item.showsReplyingTo {
                ReplyingToLine(screenNames: tweet.replyingTo)
                    .padding(.top, metrics.stackedBodyMargin)
            }

            PostContent(
                item: item,
                engagement: engagement,
                quotedEngagement: quotedEngagement,
                isFocused: isFocused,
                store: store
            )
            .padding(.top, item.showsReplyingTo ? metrics.authorBodyMargin : metrics.stackedBodyMargin)
        }
    }
}

private struct AvatarButton: View {
    let author: User
    let store: StoreOf<FeedFeature>
    @Environment(\.tweetMetrics) private var metrics

    var body: some View {
        Button {
            store.send(.authorTapped(author))
        } label: {
            Avatar(
                user: author,
                size: metrics.avatarSize,
                decodeSize: max(metrics.avatarSize, FeedImages.avatarSize)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "@\(author.screenName)"))
        .profilePreview(for: author) { store.send(.authorTapped(author)) }
    }
}

extension FeedTweet {
    /// Within a thread the line above already says who's being replied to.
    fileprivate var showsReplyingTo: Bool {
        !tweet.replyingTo.isEmpty && !connectsAbove
    }
}

/// "Replying to @a and @b" above a reply that isn't shown under the post it answers.
private struct ReplyingToLine: View {
    let screenNames: [String]
    @Environment(\.tweetMetrics) private var metrics

    var body: some View {
        Text("Replying to \(screenNames.map { "@\($0)" }.formatted(.list(type: .and)))")
            .font(metrics.font(.body))
            .foregroundStyle(.twitterSecondary)
            .lineLimit(1)
    }
}

/// The line from a post's avatar down to the next post in its thread: 2 pt in the divider colour, starting 8 pt
/// below the avatar (`connectorAvatarBottomPadding`).
private struct ThreadConnector: View {
    var body: some View {
        Capsule()
            .fill(.twitterDivider)
            .frame(width: 2)
            .frame(maxHeight: .infinity)
            .padding(.top, 8)
            .accessibilityHidden(true)
    }
}
