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
        TwitterIconView(style.icon, size: 26)
            .foregroundStyle(style.color)
    }
}

/// The glyph and color for a notification's `xxx_icon`, as Twitter's own table pairs them.
private struct NotificationIconStyle {
    let icon: TwitterIcon
    let color: Color

    init(icon: String) {
        let charm = icon.hasSuffix("_icon") ? String(icon.dropLast("_icon".count)) : icon
        (self.icon, color) = Self.style(charm: charm) ?? Self.fallbackStyle(charm: charm)
    }

    private static func style(charm: String) -> (TwitterIcon, Color)? {
        switch charm {
        case "heart": (.heart, .twitterLike)
        case "heart_plus": (.heartPlus, .twitterLike)
        case "person": (.person, .twitterBlue)
        case "list": (.lists, .twitterSecondary)
        case "retweet": (.repost, .twitterRepost)
        case "bird": (.twitter, .twitterBlue)
        case "lightning_bolt": (.lightning, .twitterBlue)
        case "histogram": (.barChartHorizontal, .twitterBlue)
        case "bell": (.notifications, .twitterBlue)
        case "alert_bell": (.alerts, .twitterError)
        case "reply", "conversation_bubble": (.reply, .twitterBlue)
        case "location_pin": (.location, .twitterBlue)
        case "stacked_cards": (.highlights, .twitterBlue)
        case "trending": (.fire, .twitterOrange)
        case "lock": (.lock, .twitterBlue)
        case "news": (.news, .twitterBlue)
        case "play": (.play, .twitterBlue)
        case "highlights": (.notificationsHighlight, .twitterBlue)
        case "milestone": (.notificationsMilestone, .twitterBlue)
        case "recommendation": (.notificationsRecommendation, .twitterBlue)
        case "safety": (.notificationsSafety, .twitterBlue)
        case "security_alert": (.notificationsSecurityAlert, .twitterBlue)
        case "security_unknown": (.notificationsSecurityUnknown, .twitterBlue)
        case "topic": (.topics, .twitterBlue)
        case "verified_general": (.verifiedStroke, .twitterBlue)
        case "verified_notable": (.verified, .twitterBlue)
        case "super_follow": (.superFollow, .twitterBlue)
        case "birdwatch": (.peopleCrowd, .twitterBlue)
        case "spaces": (.notificationsSpaces, .twitterPurple)
        case "safety_mode": (.safetyMode, .twitterOrange)
        case "communities": (.communities, .twitterBlue)
        default: nil
        }
    }

    /// For names Twitter adds later: the nearest family, else the bird.
    private static func fallbackStyle(charm: String) -> (TwitterIcon, Color) {
        switch charm {
        case let charm where charm.contains("heart"): (.heart, .twitterLike)
        case let charm where charm.contains("retweet"): (.repost, .twitterRepost)
        case let charm where charm.contains("person") || charm.contains("follow"): (.person, .twitterBlue)
        case let charm where charm.contains("bell"): (.notifications, .twitterBlue)
        case let charm where charm.contains("security"): (.notificationsSecurityAlert, .twitterBlue)
        case let charm where charm.contains("safety"): (.notificationsSafety, .twitterBlue)
        case let charm where charm.contains("space") || charm.contains("live"): (.notificationsSpaces, .twitterPurple)
        case let charm where charm.contains("milestone"): (.notificationsMilestone, .twitterBlue)
        case let charm where charm.contains("trending"): (.fire, .twitterOrange)
        default: (.twitter, .twitterBlue)
        }
    }
}
