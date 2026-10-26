import ComposableArchitecture
import Models
import SwiftUI
import TweetEngagement
import TwitterClient
import TwitterUI

/// "34 Reposts  2 Quotes  560 Likes" under the focused post, as 4.x's details counted retweets and favorites. Each
/// opens who reposted, the quotes, or (on your own posts, the only ones whose likes are visible) who liked it.
struct FocusedStatsLine: View {
    let tweet: Tweet
    let engagement: Engagement
    let store: StoreOf<FeedFeature>
    @Environment(\.tweetMetrics) private var metrics
    @SharedReader(.viewer) private var viewer

    var body: some View {
        let reposts = engagement.repost.count
        let likes = engagement.like.count
        if reposts > 0 || tweet.quoteCount > 0 || likes > 0 {
            HStack(spacing: 16) {
                if reposts > 0 {
                    FocusedStat(count: reposts, label: reposts == 1 ? "Retweet" : "Retweets") {
                        store.send(.repostsButtonTapped(tweet))
                    }
                }

                if tweet.quoteCount > 0 {
                    FocusedStat(count: tweet.quoteCount, label: tweet.quoteCount == 1 ? "Quote Tweet" : "Quote Tweets")
                    {
                        store.send(.quotesButtonTapped(tweet))
                    }
                }

                if likes > 0 {
                    // Someone else's likes are private: the count is still shown, just not as a button.
                    FocusedStat(
                        count: likes,
                        label: likes == 1 ? "Like" : "Likes",
                        action: tweet.author.id == viewer?.id ? { store.send(.likesButtonTapped(tweet)) } : nil
                    )
                }
            }
            .font(metrics.font(.subtext1))
            .lineLimit(1)
        }
    }
}

/// A count and what it counts. Without an action it's plain text rather than a disabled button, which would dim it
/// beside its neighbours.
private struct FocusedStat: View {
    let count: Int
    let label: LocalizedStringKey
    let action: (() -> Void)?

    init(count: Int, label: LocalizedStringKey, action: (() -> Void)? = nil) {
        self.count = count
        self.label = label
        self.action = action
    }

    var body: some View {
        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
        } else {
            content
                .accessibilityElement(children: .combine)
        }
    }

    private var content: some View {
        HStack(spacing: 4) {
            Text(count.compact)
                .bold()
                .foregroundStyle(.twitterPrimary)

            Text(label)
                .foregroundStyle(.twitterSecondary)
        }
    }
}

/// "3:41 PM · Oct 21, 2026 · 1.2M Views" under the focused post.
struct FocusedTimestampLine: View {
    let date: Date
    let views: Int?
    @Environment(\.tweetMetrics) private var metrics

    var body: some View {
        HStack(spacing: 4) {
            Text(date, format: .dateTime.hour().minute())

            Text(verbatim: "·")

            Text(date, format: .dateTime.month(.abbreviated).day().year())

            if let views {
                Text(verbatim: "·")

                Text(
                    "\(Text(views.compact).font(metrics.font(.subtext1, weight: .bold)).foregroundStyle(.twitterPrimary)) Views"
                )
            }
        }
        .font(metrics.font(.subtext1))
        .foregroundStyle(.twitterSecondary)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}
