import SwiftUI

/// Twitter's own action glyphs: 24 × 24 template vectors, tinted by the foreground style.
package enum TwitterIcon: String, Sendable {
    case bookmark
    case bookmarkStroke = "bookmark_stroke"
    case heart
    case heartStroke = "heart_stroke"
    case home
    case homeStroke = "home_stroke"
    case notifications
    case notificationsStroke = "notifications_stroke"
    case person
    case personStroke = "person_stroke"
    case replyStroke = "reply_stroke"
    /// Reposted: the repost glyph, for tinting.
    case repost = "retweet"
    case repostStroke = "retweet_stroke"
    case search
    case searchStroke = "search_stroke"
    case shareStroke = "share_stroke"
    case views = "bar_chart"

    package var image: Image {
        // Reposted is the same glyph, tinted.
        Image(self == .repost ? Self.repostStroke.rawValue : rawValue, bundle: .module).renderingMode(.template)
    }
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
