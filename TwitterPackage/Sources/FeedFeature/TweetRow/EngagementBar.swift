import ComposableArchitecture
import Models
import SwiftUI
import TweetEngagement
import TwitterClient
import TwitterUI

/// Reply, repost, like and views left-aligned at the body inset with up to 35 pt between them; bookmark and share
/// sit together at the trailing edge, 10 pt apart.
package struct EngagementBar: View {
    let tweet: Tweet
    let engagement: Engagement
    let store: StoreOf<FeedFeature>

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// Where a column is too narrow for every count, the view count goes first, and in a compact window it never
    /// shows, leaving the room to the actions; the focused post still shows it.
    package var body: some View {
        ViewThatFits(in: .horizontal) {
            if horizontalSizeClass == .regular, verticalSizeClass == .regular {
                EngagementBarRow(tweet: tweet, engagement: engagement, store: store, showsViews: true)
            }

            EngagementBarRow(tweet: tweet, engagement: engagement, store: store, showsViews: false)
        }
    }
}

private struct EngagementBarRow: View {
    let tweet: Tweet
    let engagement: Engagement
    let store: StoreOf<FeedFeature>
    let showsViews: Bool

    var body: some View {
        HStack(spacing: 0) {
            EngagementButton(
                action: { store.send(.replyButtonTapped(tweet)) },
                count: tweet.replyCount,
                icon: .replyStroke,
                label: "Reply"
            )
            .disabled(!tweet.viewerCanReply)
            .opacity(tweet.viewerCanReply ? 1 : 0.4)

            BarSpacer()

            RepostMenu(tweet: tweet, engagement: engagement, store: store)

            BarSpacer()

            HeldLikeButton(tweet: tweet, engagement: engagement, store: store)

            if showsViews, let views = tweet.viewCount {
                BarSpacer()

                EngagementLabel(icon: .views, count: views)
                    .foregroundStyle(.twitterSecondary)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(views) views")
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                EngagementButton(
                    action: { store.send(.bookmarkButtonTapped(tweet)) },
                    activeIcon: .bookmark,
                    icon: .bookmarkStroke,
                    isActive: engagement.bookmark.isOn,
                    label: engagement.bookmark.isOn ? "Remove Bookmark" : "Bookmark"
                )

                ShareButton(tweet: tweet)
            }
        }
    }
}

/// The focused post's actions on 4.x's details shelf: reply, repost, like, bookmark and share, spread evenly at full
/// size. Its views are counted in the line above.
struct DetailEngagementBar: View {
    let tweet: Tweet
    let engagement: Engagement
    let store: StoreOf<FeedFeature>

    var body: some View {
        DetailActionBar {
            EngagementButton(
                action: { store.send(.replyButtonTapped(tweet)) },
                count: tweet.replyCount,
                icon: .replyStroke,
                label: "Reply"
            )
            .disabled(!tweet.viewerCanReply)
            .opacity(tweet.viewerCanReply ? 1 : 0.4)

            RepostMenu(tweet: tweet, engagement: engagement, store: store)

            HeldLikeButton(tweet: tweet, engagement: engagement, store: store)

            EngagementButton(
                action: { store.send(.bookmarkButtonTapped(tweet)) },
                activeIcon: .bookmark,
                icon: .bookmarkStroke,
                isActive: engagement.bookmark.isOn,
                label: engagement.bookmark.isOn ? "Remove Bookmark" : "Bookmark"
            )

            ShareButton(tweet: tweet)
        }
    }
}

/// Retweet or quote, asked as Twitter's retweet sheet asks; held, who retweeted it. A button rather than a menu, so
/// the hold can be its own: a menu takes the press for itself.
private struct RepostMenu: View {
    let tweet: Tweet
    let engagement: Engagement
    let store: StoreOf<FeedFeature>
    @State private var isAsking = false

    var body: some View {
        Button {
            isAsking = true
        } label: {
            EngagementLabel(icon: engagement.repost.isOn ? .repost : .repostStroke, count: engagement.repost.count)
                .foregroundStyle(engagement.repost.isOn ? .twitterRepost : .twitterSecondary)
        }
        .buttonStyle(.plain)
        .confirmationDialog("Retweet", isPresented: $isAsking, titleVisibility: .hidden) {
            Button(engagement.repost.isOn ? "Undo Retweet" : "Retweet") {
                store.send(.repostButtonTapped(tweet))
            }

            Button("Quote Tweet") {
                store.send(.quoteButtonTapped(tweet))
            }
        }
        .onHold("View Retweets") { store.send(.repostsButtonTapped(tweet)) }
        .accessibilityLabel(engagement.repost.isOn ? "Undo Retweet" : "Retweet")
        .accessibilityValue(engagement.repost.count.formatted())
    }
}

/// Likes or unlikes the post; held, who liked it. Likes have been private since 2024, so that's only for the viewer's
/// own posts, as on Twitter.
private struct HeldLikeButton: View {
    let tweet: Tweet
    let engagement: Engagement
    let store: StoreOf<FeedFeature>
    @SharedReader(.viewer) private var viewer

    var body: some View {
        LikeButton(isLiked: engagement.like.isOn, count: engagement.like.count) {
            store.send(.likeButtonTapped(tweet))
        }
        .onHold("View Likes", perform: tweet.author.id == viewer?.id ? { store.send(.likesButtonTapped(tweet)) } : nil)
    }
}

/// Shares the post; held, opens it in the official Twitter app instead, when that's installed.
private struct ShareButton: View {
    let tweet: Tweet

    var body: some View {
        ShareLink(item: tweet.url) {
            EngagementLabel(icon: .share, count: nil, minWidth: EngagementLabel.iconOnlyWidth)
                .foregroundStyle(.twitterSecondary)
        }
        .buttonStyle(.plain)
        // The post's own link, opened only as a universal link: the Twitter app takes it, and without the app nothing
        // opens rather than the web page.
        .onHold("Open in Twitter") { UIApplication.shared.open(tweet.url, options: [.universalLinksOnly: true]) }
        .accessibilityLabel("Share")
    }
}

/// Flexible space between the primary action buttons, capped at 35 pt.
private struct BarSpacer: View {
    var body: some View {
        Spacer(minLength: 0).frame(maxWidth: 35)
    }
}
