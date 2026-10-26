import ComposableArchitecture
import Models
import Routing
import SwiftUI
import TweetEngagement
import TwitterClient
import TwitterUI

package struct TweetRow: View {
    let item: FeedTweet
    let engagement: Engagement
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
                ContextLabel(symbol: TwitterIcon.repostStroke.rawValue, text: "\(reposter.name) retweeted")
            } else if let context = item.socialContext {
                ContextLabel(symbol: item.socialSymbol ?? "sparkles", text: context)
            }

            if layout == .stacked {
                stackedLayout
            } else {
                classicLayout
            }
        }
        .padding(.horizontal, metrics.sideInset)
        .padding(.top, item.connectsAbove ? 4 : metrics.topInset)
        // The focused post's action bar is its bottom edge.
        .padding(.bottom, item.connectsBelow || isFocused ? 0 : metrics.actionBarBottomInset)
        .foregroundStyle(.twitterPrimary)
        .overlay(alignment: .topTrailing) {
            if engagement.like.isOn || engagement.repost.isOn {
                DogEar(isLiked: engagement.like.isOn, isReposted: engagement.repost.isOn)
                    .transition(.scale(scale: 0, anchor: .topTrailing))
            }
        }
        .animation(.spring(duration: 0.3, bounce: 0.35), value: engagement.like.isOn)
        .animation(.spring(duration: 0.3, bounce: 0.35), value: engagement.repost.isOn)
        // Opaque, so the post lifted for its context menu isn't see-through.
        .background(.background)
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

    /// Twitter's timeline row: the avatar (and the thread line under it) in a column of its own, the author line and
    /// the post beside it.
    private var classicLayout: some View {
        HStack(alignment: .top, spacing: metrics.gutter) {
            VStack(spacing: 0) {
                avatarButton

                if item.connectsBelow {
                    ThreadConnector()
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2 * metrics.unit) {
                    AuthorLine(user: tweet.author, date: tweet.createdAt)

                    if showsReplyingTo {
                        ReplyingToLine(screenNames: tweet.replyingTo)
                    }
                }

                postContent
                    .padding(.top, tweet.text.isEmpty ? metrics.mediaTextMargin : metrics.authorBodyMargin)
            }
        }
    }

    /// The avatar beside the name over the handle, and the post under both at the row's full width.
    private var stackedLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: metrics.gutter) {
                avatarButton

                // The focused post's time is spelled out above its action bar instead.
                AuthorLine(user: tweet.author, date: isFocused ? nil : tweet.createdAt, layout: .stacked)
            }

            if showsReplyingTo {
                ReplyingToLine(screenNames: tweet.replyingTo)
                    .padding(.top, metrics.stackedBodyMargin)
            }

            postContent
                .padding(.top, showsReplyingTo ? metrics.authorBodyMargin : metrics.stackedBodyMargin)
        }
    }

    private var avatarButton: some View {
        Button {
            store.send(.authorTapped(tweet.author))
        } label: {
            Avatar(
                user: tweet.author,
                size: metrics.avatarSize,
                decodeSize: max(metrics.avatarSize, FeedImages.avatarSize)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("@\(tweet.author.screenName)")
        .profilePreview(for: tweet.author) { store.send(.authorTapped(tweet.author)) }
    }

    /// Within a thread the line above already says who's being replied to.
    private var showsReplyingTo: Bool {
        !tweet.replyingTo.isEmpty && !item.connectsAbove
    }

    /// Text, attachments and the action bar: the same in either layout, only placed differently.
    private var postContent: some View {
        VStack(alignment: .leading, spacing: metrics.mediaTextMargin) {
            if !tweet.text.isEmpty {
                ExpandableTweetText(tweet: tweet, isFocused: isFocused)
            }

            if let poll = tweet.poll {
                PollView(poll: poll)
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
                        TweetMenu(tweet: quoted, engagement: store.engagements.engagement(for: quoted), store: store)
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

/// A post's text; timeline rows cut long posts short behind "Show more", the focused post in a thread shows it all.
private struct ExpandableTweetText: View {
    let tweet: Tweet
    let isFocused: Bool
    @State private var isExpanded = false
    @Environment(\.tweetMetrics) private var metrics

    var body: some View {
        let isTruncated =
            !isFocused && !isExpanded
            && TweetText.truncated(tweet.text, limit: TweetText.timelineCharacterLimit) != nil
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
            Glyph((restriction.policy == .mentioned ? TwitterIcon.at : .followingStroke).rawValue, size: 16)
                .foregroundStyle(.tint)
        }
        .font(.footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.fill.quaternary, in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
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

/// "34 Reposts  2 Quotes  560 Likes" under the focused post, as 4.x's details counted retweets and favorites. Each
/// opens who reposted, the quotes, or (on your own posts, the only ones whose likes are visible) who liked it.
private struct FocusedStatsLine: View {
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
private struct FocusedTimestampLine: View {
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

private struct ContextLabel: View {
    let symbol: String
    let text: String
    @Environment(\.tweetMetrics) private var metrics

    var body: some View {
        HStack(spacing: metrics.gutter) {
            Glyph(symbol, size: 16)
                .frame(width: metrics.avatarSize, alignment: .trailing)

            Text(text).lineLimit(1)
        }
        .font(metrics.font(.subtext2, weight: .bold))
        .foregroundStyle(.twitterSecondary)
    }
}

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
private struct DetailEngagementBar: View {
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
                Label("Quote Tweet", twitterIcon: .quote)
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
            EngagementLabel(icon: .shareStroke, count: nil, minWidth: EngagementLabel.iconOnlyWidth)
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

package struct TweetMenu: View {
    let tweet: Tweet
    let engagement: Engagement
    let store: StoreOf<FeedFeature>
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows
    @SharedReader(.viewer) private var viewer

    package var body: some View {
        Button {
            store.send(.replyButtonTapped(tweet))
        } label: {
            Label("Reply", twitterIcon: .replyStroke)
        }
        .disabled(!tweet.viewerCanReply)

        Button {
            store.send(.repostButtonTapped(tweet))
        } label: {
            Label(engagement.repost.isOn ? "Undo Retweet" : "Retweet", twitterIcon: .repostStroke)
        }

        Button {
            store.send(.quoteButtonTapped(tweet))
        } label: {
            Label("Quote Tweet", twitterIcon: .quote)
        }

        PostActivityMenu(tweet: tweet, isOwnPost: tweet.author.id == viewer?.id, store: store)

        Button {
            store.send(.authorTapped(tweet.author))
        } label: {
            Label("View @\(tweet.author.screenName)", twitterIcon: .personStroke)
        }

        if tweet.author.id == viewer?.id {
            Button(role: .destructive) {
                store.send(.deleteButtonTapped(tweet))
            } label: {
                Label("Delete Tweet", twitterIcon: .trash)
            }
        } else {
            Button {
                store.send(.muteButtonTapped(tweet.author))
            } label: {
                Label(
                    tweet.author.isMuting
                        ? "Unmute @\(tweet.author.screenName)" : "Mute @\(tweet.author.screenName)",
                    twitterIcon: tweet.author.isMuting ? .unmute : .mute)
            }

            Button(role: tweet.author.isBlocking ? nil : .destructive) {
                store.send(.blockButtonTapped(tweet.author))
            } label: {
                Label(
                    tweet.author.isBlocking
                        ? "Unblock @\(tweet.author.screenName)" : "Block @\(tweet.author.screenName)",
                    twitterIcon: .block)
            }
        }

        if supportsMultipleWindows {
            Divider()

            Button {
                openWindow(value: Route.thread(tweet).window)
            } label: {
                Label("Open in New Window", twitterIcon: .newWindow)
            }

            Button {
                openWindow(value: Route.profile(tweet.author).window)
            } label: {
                Label("Open @\(tweet.author.screenName) in New Window", twitterIcon: .newWindow)
            }
        }

        Divider()

        ShareLink(item: tweet.url)

        Button {
            UIPasteboard.general.url = tweet.url
        } label: {
            Label("Copy Link", twitterIcon: .link)
        }

        if tweet.isInAnotherLanguage() {
            Button {
                store.send(.translateButtonTapped(tweet))
            } label: {
                Label("Translate Tweet", twitterIcon: .globe)
            }
        }

        if !tweet.text.isEmpty {
            Button {
                UIPasteboard.general.string = tweet.text
            } label: {
                Label("Copy Text", twitterIcon: .copyStroke)
            }
        }
    }
}

package struct NotificationRow: View {
    let notification: TwitterNotification
    let store: StoreOf<FeedFeature>

    package var body: some View {
        HStack(alignment: .top, spacing: 12) {
            NotificationIcon(icon: notification.icon)
                .frame(width: 44, alignment: .trailing)

            VStack(alignment: .leading, spacing: 8) {
                // Side by side, each its own square, as 4.x showed who it was.
                HStack(spacing: 4) {
                    ForEach(notification.users.prefix(8)) { user in
                        Button {
                            store.send(.authorTapped(user))
                        } label: {
                            Avatar(user: user, size: 32)
                        }
                        .buttonStyle(.plain)
                        .profilePreview(for: user) { store.send(.authorTapped(user)) }
                    }
                }

                Text(notification.attributedMessage)
                    .font(.subheadline)

                if let tweet = notification.tweet, !tweet.text.isEmpty {
                    Text(tweet.text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        // Opaque, so the row lifted for its context menu isn't see-through.
        .background(.background)
        .contentShape(.rect)
        .onTapGesture {
            if let tweet = notification.tweet {
                store.send(.tweetTapped(tweet))
            } else if let user = notification.users.first {
                store.send(.authorTapped(user))
            }
        }
        .modifier(NotificationMenu(notification: notification, store: store))
    }
}

/// A long press does what a tap would, ahead of time, as Twitter's `NotificationsStatusView` does: a notification
/// about a post gets the post's menu, one about people (a follow) previews the first of them. Each avatar keeps its
/// own profile preview.
private struct NotificationMenu: ViewModifier {
    let notification: TwitterNotification
    let store: StoreOf<FeedFeature>

    func body(content: Content) -> some View {
        if let tweet = notification.tweet {
            content.contextMenu {
                TweetMenu(tweet: tweet, engagement: store.engagements.engagement(for: tweet), store: store)
            } preview: {
                ThreadPreview(tweet: tweet, store: store)
            }
        } else if let user = notification.users.first {
            content.profilePreview(for: user) { store.send(.authorTapped(user)) }
        } else {
            content
        }
    }
}

extension TwitterNotification {
    package var attributedMessage: AttributedString {
        var result = AttributedString(message)
        let scalars = Array(message.unicodeScalars)
        for range in boldRanges where range.lowerBound >= 0 && range.upperBound <= scalars.count {
            let prefix = String(String.UnicodeScalarView(scalars[..<range.lowerBound]))
            let token = String(String.UnicodeScalarView(scalars[range]))
            guard
                let start = result.characters.index(
                    result.startIndex, offsetBy: prefix.count, limitedBy: result.endIndex
                ),
                let end = result.characters.index(start, offsetBy: token.count, limitedBy: result.endIndex)
            else { continue }
            result[start..<end].inlinePresentationIntent = .stronglyEmphasized
        }
        return result
    }
}

private struct NotificationIcon: View {
    let icon: String

    var body: some View {
        let style = NotificationIconStyle(icon: icon)
        Glyph(style.symbol, size: 26)
            .font(.title2)
            .foregroundStyle(style.color)
            .accessibilityHidden(true)
    }
}

private struct NotificationIconStyle {
    let color: Color
    let symbol: String

    init(icon: String) {
        switch icon {
        case let icon where icon.contains("heart"):
            (symbol, color) = (TwitterIcon.heart.rawValue, .twitterLike)
        case let icon where icon.contains("retweet"):
            (symbol, color) = (TwitterIcon.repostStroke.rawValue, .twitterRepost)
        case let icon where icon.contains("person") || icon.contains("follow"):
            (symbol, color) = (TwitterIcon.person.rawValue, .accentColor)
        case let icon where icon.contains("bell"):
            (symbol, color) = (TwitterIcon.notifications.rawValue, .accentColor)
        case let icon where icon.contains("star") || icon.contains("bird"):
            (symbol, color) = ("star.fill", .purple)
        case let icon where icon.contains("security") || icon.contains("safety"):
            (symbol, color) = ("lock.shield.fill", .orange)
        case let icon where icon.contains("live") || icon.contains("space"):
            (symbol, color) = ("waveform", .purple)
        case let icon where icon.contains("milestone") || icon.contains("trending"):
            (symbol, color) = ("chart.line.uptrend.xyaxis", .accentColor)
        default:
            (symbol, color) = ("sparkles", .accentColor)
        }
    }
}
