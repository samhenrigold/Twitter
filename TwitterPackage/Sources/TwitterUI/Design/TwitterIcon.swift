import SwiftUI
import UIKit

/// Twitter's own action glyphs: 24 × 24 template vectors, tinted by the foreground style.
package enum TwitterIcon: String, Sendable {
    /// Twitter's notification for an important alert.
    case alerts
    case arrowUp = "arrow_up"
    case at
    case barChartHorizontal = "bar_chart_horizontal"
    /// Block, and a blocked account; ``unblock`` is its undo.
    case block = "no"
    case bookmark
    case bookmarkStroke = "bookmark_stroke"
    case calendar
    case checkmarkCircle = "checkmark_circle"
    case chevronLeft = "chevron_left"
    case chevronRight = "chevron_right"
    case close
    case cloudOff = "cloud_off"
    case communities
    case communitiesStroke = "communities_stroke"
    /// New Tweet: the feather and plus.
    case compose
    case copyStroke = "copy_stroke"
    case download
    case drafts
    case externalLinkStroke = "external_link_stroke"
    /// Trending.
    case fire
    /// Following.
    case followingStroke = "following_stroke"
    case gif = "gif_pill"
    /// Open in the browser.
    case globe
    /// Anyone can reply.
    case globeStroke = "globe_stroke"
    /// Hashtags.
    case hashStroke = "hash_stroke"
    case heart
    case heartPlus = "heart_plus"
    case heartStroke = "heart_stroke"
    case highlights
    case home
    case homeStroke = "home_stroke"
    case lightning
    case link
    case lists
    case listsStroke = "lists_stroke"
    case location
    case locationStroke = "location_stroke"
    case lock
    case mediaStroke = "media_stroke"
    case more
    case mute
    case newWindow = "new_window"
    case news
    case notifications
    case notificationsHighlight = "notifications_highlight"
    case notificationsMilestone = "notifications_milestone"
    case notificationsRecommendation = "notifications_recommendation"
    case notificationsSafety = "notifications_safety"
    case notificationsSecurityAlert = "notifications_security_alert"
    case notificationsSecurityUnknown = "notifications_security_unknown"
    case notificationsSpaces = "notifications_spaces"
    case notificationsStroke = "notifications_stroke"
    /// Community Notes (Birdwatch).
    case peopleCrowd = "people_crowd"
    case person
    /// Replies limited to people followed.
    case personCheckmarkStroke = "person_checkmark_stroke"
    case personStroke = "person_stroke"
    case pause
    case pin
    case play
    case plus
    /// The Quote Tweets list.
    case quote
    /// Quote Tweet, the action.
    case quoteTweet = "pencil_stroke"
    case refresh
    case reply
    case replyStroke = "reply_stroke"
    /// Retweeted: the filled glyph, for tinting.
    case repost = "retweet"
    case repostStroke = "retweet_stroke"
    case search
    case searchStroke = "search_stroke"
    case safetyMode = "safety_mode"
    case settings
    /// Share: Twitter's outgoing arrow.
    case share = "outgoing"
    case signOut = "sign_out"
    /// A video's sound, on and off; ``mute`` and ``unmute`` are for accounts.
    case sound
    case soundOff = "sound_off"
    case spaces
    /// What Twitter suggests, as a social context.
    case sparkle
    case superFollow = "superfollow"
    case topics
    case trash
    /// The bird.
    case twitter
    case unblock = "no_off"
    case unmute
    /// The verified badge, for tinting in the account's color.
    case verified
    /// The business badge, in its own gold: draw it without tinting.
    case verifiedGold = "verified_gold"
    case verifiedStroke = "verified_stroke"
    case videoOff = "video_off"
    case views = "bar_chart"
    case warningStroke = "warning_stroke"

    package var image: Image {
        Image(decorative: rawValue, bundle: .module).renderingMode(isTemplate ? .template : .original)
    }

    /// For UIKit's bars.
    package var uiImage: UIImage? {
        UIImage(named: rawValue, in: .module, with: nil)?.withRenderingMode(
            isTemplate ? .alwaysTemplate : .alwaysOriginal)
    }

    /// Whether the glyph takes the foreground style; the gold badge keeps its own colors.
    private var isTemplate: Bool { self != .verifiedGold }
}

/// A glyph drawn at the action bar's size.
package struct TwitterIconView: View {
    let icon: TwitterIcon
    var size: CGFloat?
    @Environment(\.engagementIconSize) private var engagementIconSize

    package init(_ icon: TwitterIcon, size: CGFloat? = nil) {
        self.icon = icon
        self.size = size
    }

    package var body: some View {
        icon.image
            .resizable()
            .scaledToFit()
            .frame(width: size ?? engagementIconSize, height: size ?? engagementIconSize)
            .accessibilityHidden(true)
    }
}

extension EnvironmentValues {
    /// How tall action bar glyphs draw: 18 pt in a timeline, larger in a post's details.
    @Entry package var engagementIconSize: CGFloat = 18
}

/// A glyph by name: Twitter's, where `name` is one of ``TwitterIcon``'s, otherwise the system symbol of that name.
/// Twitter's draw `size` points square; symbols follow the font.
package struct Glyph: View {
    let name: String
    let size: CGFloat

    package init(_ name: String, size: CGFloat) {
        self.name = name
        self.size = size
    }

    package var body: some View {
        if let icon = TwitterIcon(rawValue: name) {
            icon.image
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: name)
        }
    }
}

extension Label where Title == Text, Icon == Image {
    /// A label with one of Twitter's glyphs, as `Label(_:systemImage:)` takes a symbol.
    package init(_ titleKey: LocalizedStringKey, twitterIcon icon: TwitterIcon) {
        self.init {
            Text(titleKey)
        } icon: {
            icon.image
        }
    }

    @_disfavoredOverload
    package init(_ title: some StringProtocol, twitterIcon icon: TwitterIcon) {
        self.init {
            Text(title)
        } icon: {
            icon.image
        }
    }
}

extension Button where Label == SwiftUI.Label<Text, Image> {
    /// A button with one of Twitter's glyphs, as `Button(_:systemImage:role:action:)` takes a symbol.
    package init(
        _ titleKey: LocalizedStringKey, twitterIcon icon: TwitterIcon, role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.init(role: role, action: action) { SwiftUI.Label(titleKey, twitterIcon: icon) }
    }

    @_disfavoredOverload
    package init(
        _ title: some StringProtocol, twitterIcon icon: TwitterIcon, role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.init(role: role, action: action) { SwiftUI.Label(title, twitterIcon: icon) }
    }
}

extension ContentUnavailableView where Label == SwiftUI.Label<Text, Image>, Description == Text?, Actions == EmptyView {
    /// An empty or error state with one of Twitter's glyphs, as `ContentUnavailableView(_:systemImage:description:)`.
    package init(_ titleKey: LocalizedStringKey, twitterIcon icon: TwitterIcon, description: Text? = nil) {
        self.init {
            SwiftUI.Label(titleKey, twitterIcon: icon)
        } description: {
            description
        }
    }

    @_disfavoredOverload
    package init(_ title: some StringProtocol, twitterIcon icon: TwitterIcon, description: Text? = nil) {
        self.init {
            SwiftUI.Label(title, twitterIcon: icon)
        } description: {
            description
        }
    }
}
