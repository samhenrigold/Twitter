import ComposableArchitecture
import Models
import SwiftUI
import TweetEngagement
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

            LikeButton(isLiked: engagement.like.isOn, count: engagement.like.count) {
                store.send(.likeButtonTapped(tweet))
            }

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

            LikeButton(isLiked: engagement.like.isOn, count: engagement.like.count) {
                store.send(.likeButtonTapped(tweet))
            }

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

/// Repost or quote, from the repost button.
private struct RepostMenu: View {
    let tweet: Tweet
    let engagement: Engagement
    let store: StoreOf<FeedFeature>

    var body: some View {
        Menu {
            Button {
                store.send(.repostButtonTapped(tweet))
            } label: {
                Label(engagement.repost.isOn ? "Undo Retweet" : "Retweet", twitterIcon: .repostStroke)
            }

            Button {
                store.send(.quoteButtonTapped(tweet))
            } label: {
                Label("Quote Tweet", twitterIcon: .quoteTweet)
            }
        } label: {
            EngagementLabel(icon: engagement.repost.isOn ? .repost : .repostStroke, count: engagement.repost.count)
                .foregroundStyle(engagement.repost.isOn ? .twitterRepost : .twitterSecondary)
        }
        .accessibilityLabel(engagement.repost.isOn ? "Undo Retweet" : "Retweet")
        .accessibilityValue(engagement.repost.count.formatted())
    }
}

/// Shares the post; held, opens it in the official Twitter app instead, when that's installed.
private struct ShareButton: View {
    let tweet: Tweet
    @State private var opensInTwitter = 0

    var body: some View {
        ShareLink(item: tweet.url) {
            EngagementLabel(icon: .share, count: nil, minWidth: EngagementLabel.iconOnlyWidth)
                .foregroundStyle(.twitterSecondary)
        }
        .buttonStyle(.plain)
        // Ahead of the share sheet: a tap still shares, a hold doesn't.
        .highPriorityGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in openInTwitter() })
        .sensoryFeedback(.impact(weight: .medium), trigger: opensInTwitter)
        .accessibilityLabel("Share")
        .accessibilityAction(named: "Open in Twitter") { openInTwitter() }
    }

    /// The post's own link, opened only as a universal link: the Twitter app takes it, and without the app nothing
    /// opens rather than the web page.
    private func openInTwitter() {
        opensInTwitter += 1
        UIApplication.shared.open(tweet.url, options: [.universalLinksOnly: true])
    }
}

/// Flexible space between the primary action buttons, capped at 35 pt.
private struct BarSpacer: View {
    var body: some View {
        Spacer(minLength: 0).frame(maxWidth: 35)
    }
}
