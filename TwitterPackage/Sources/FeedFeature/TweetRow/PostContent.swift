import ComposableArchitecture
import Models
import PostText
import SwiftUI
import TweetEngagement
import TwitterUI

/// Text, attachments and the action bar: the same in either layout, only placed differently.
struct PostContent: View {
    let item: FeedTweet
    let engagement: Engagement
    let quotedEngagement: Engagement?
    let isFocused: Bool
    let store: StoreOf<FeedFeature>
    @Environment(\.tweetMetrics) private var metrics

    private var tweet: Tweet { item.tweet }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.mediaTextMargin) {
            if !tweet.text.isEmpty {
                ExpandableTweetText(tweet: tweet, isFocused: isFocused)
            }

            if let poll = tweet.poll {
                PollView(poll: poll) { store.send(.pollChoiceTapped(tweetID: tweet.id, choice: $0)) }
            }

            if !tweet.media.isEmpty {
                MediaGrid(media: tweet.media, tweet: tweet)
            }

            if let card = tweet.card, tweet.media.isEmpty {
                LinkCardView(card: card)
            }

            if let quoted = tweet.quoted.first {
                QuoteCard(tweet: quoted) { store.send(.tweetTapped(quoted)) }
                    // Its own menu, so pressing the quoted post lifts that post rather than the one quoting it.
                    .contextMenu {
                        TweetMenu(
                            tweet: quoted, engagement: quotedEngagement ?? Engagement(tweet: quoted), store: store)
                    } preview: {
                        ThreadPreview(tweet: quoted, store: store)
                    }
            } else if let quotedTombstone = tweet.quotedTombstone {
                TombstoneView(tombstone: quotedTombstone)
            }

            if let note = tweet.communityNote {
                CommunityNoteCard(note: note)
            }

            if isFocused, let restriction = tweet.replyRestriction {
                ReplyRestrictionBanner(restriction: restriction)
            }

            if isFocused, let date = tweet.createdAt {
                FocusedTimestampLine(date: date, views: tweet.viewCount)
            }

            if isFocused {
                FocusedStatsLine(tweet: tweet, engagement: engagement, store: store)
            }

            if isFocused {
                DetailEngagementBar(tweet: tweet, engagement: engagement, store: store)
                    // Across the row's full width.
                    .padding(.horizontal, -metrics.sideInset)
            } else {
                EngagementBar(tweet: tweet, engagement: engagement, store: store)
                    .padding(.top, metrics.actionTopMargin - metrics.mediaTextMargin)
                    // Room under the bar that stays inside the row, so the thread line runs on unbroken.
                    .padding(.bottom, item.connectsBelow ? 4 * metrics.unit : 0)
            }
        }
    }
}

/// A post's text; timeline rows cut long posts short behind "Show more", the focused post in a thread shows it all.
private struct ExpandableTweetText: View {
    let tweet: Tweet
    let isFocused: Bool
    @State private var isExpanded = false
    @Environment(\.tweetMetrics) private var metrics

    var body: some View {
        let isTruncated =
            !isFocused && !isExpanded
            && PostTextInput.needsTruncation(tweet.text, limit: TweetText.timelineCharacterLimit)
        VStack(alignment: .leading, spacing: 4 * metrics.unit) {
            TweetText(
                tweet: tweet,
                style: isFocused ? .headline2 : .body,
                characterLimit: isTruncated ? TweetText.timelineCharacterLimit : nil
            )

            if isTruncated {
                Button("Show more") {
                    withAnimation(.snappy) { isExpanded = true }
                }
                .font(metrics.font(.body, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(.twitterBlue)
            }
        }
    }
}

/// "People @x mentioned can reply" on the focused post of a thread.
private struct ReplyRestrictionBanner: View {
    let restriction: ReplyRestriction

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(restriction.message)

                if !restriction.viewerCanReply {
                    Text("You can't reply to this Tweet.")
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            TwitterIconView(icon, size: 16)
                .foregroundStyle(.tint)
        }
        .font(.footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.fill.quaternary, in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    /// Twitter's conversation-control glyph for who may reply.
    private var icon: TwitterIcon {
        switch restriction.policy {
        case .mentioned: .at
        case .verified: .verifiedStroke
        case .subscribers: .superFollow
        case .following, .other: .personCheckmarkStroke
        }
    }
}
