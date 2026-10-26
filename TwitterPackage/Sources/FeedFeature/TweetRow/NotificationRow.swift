import ComposableArchitecture
import Models
import SwiftUI
import TweetEngagement
import TwitterUI

package struct NotificationRow: View {
    let notification: TwitterNotification
    /// The notification's post's, for its menu.
    let engagement: Engagement?
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
        // Opaque, so the row lifted for its context menu isn't see-through. Twitter's pale blue while unread.
        .background(notification.isUnread ? AnyShapeStyle(.twitterUnread) : AnyShapeStyle(.background))
        .contentShape(.rect)
        .onTapGesture(perform: open)
        .modifier(NotificationMenu(notification: notification, engagement: engagement, store: store))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Open", open)
    }

    /// The post it's about, or else the first of the people.
    private func open() {
        if let tweet = notification.tweet {
            store.send(.tweetTapped(tweet))
        } else if let user = notification.users.first {
            store.send(.authorTapped(user))
        }
    }
}

/// A long press does what a tap would, ahead of time, as Twitter's `NotificationsStatusView` does: a notification
/// about a post gets the post's menu, one about people (a follow) previews the first of them. Each avatar keeps its
/// own profile preview.
private struct NotificationMenu: ViewModifier {
    let notification: TwitterNotification
    let engagement: Engagement?
    let store: StoreOf<FeedFeature>

    func body(content: Content) -> some View {
        if let tweet = notification.tweet {
            content.contextMenu {
                TweetMenu(tweet: tweet, engagement: engagement ?? Engagement(tweet: tweet), store: store)
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
    fileprivate var attributedMessage: AttributedString {
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
            (symbol, color) = ("star.fill", .twitterPurple)
        case let icon where icon.contains("security") || icon.contains("safety"):
            (symbol, color) = (TwitterIcon.lock.rawValue, .twitterOrange)
        case let icon where icon.contains("live") || icon.contains("space"):
            (symbol, color) = ("waveform", .twitterPurple)
        case let icon where icon.contains("milestone") || icon.contains("trending"):
            (symbol, color) = ("chart.line.uptrend.xyaxis", .accentColor)
        default:
            (symbol, color) = ("sparkles", .accentColor)
        }
    }
}
