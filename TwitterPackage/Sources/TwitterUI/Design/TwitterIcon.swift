import SwiftUI
import UIKit

/// Twitter's own action glyphs: 24 × 24 template vectors, tinted by the foreground style.
package enum TwitterIcon: String, Sendable {
    case arrowUp = "arrow_up"
    case at
    case block
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
    /// New Tweet: the feather.
    case compose = "feather"
    case copyStroke = "copy_stroke"
    case download
    case externalLinkStroke = "external_link_stroke"
    /// Following, and replies limited to people followed.
    case followingStroke = "following_stroke"
    /// Open in the browser.
    case globe
    case heart
    case heartStroke = "heart_stroke"
    case home
    case homeStroke = "home_stroke"
    case link
    case lists
    case location
    case locationStroke = "location_stroke"
    case lock
    case mediaStroke = "media_stroke"
    case more
    case newWindow = "new_window"
    case notifications
    case notificationsStroke = "notifications_stroke"
    case person
    case personStroke = "person_stroke"
    case pin
    case play
    case quote
    case refresh
    case replyStroke = "reply_stroke"
    /// Reposted: the repost glyph, for tinting.
    case repost = "retweet"
    case repostStroke = "retweet_stroke"
    case search
    case searchStroke = "search_stroke"
    case shareStroke = "share_stroke"
    case signOut = "sign_out"
    /// The bird.
    case twitter
    /// The verified badge, for tinting in the account's color.
    case verified
    case videoOff = "video_off"
    case views = "bar_chart"
    case warningStroke = "warning_stroke"

    package var image: Image {
        Image(assetName, bundle: .module).renderingMode(.template)
    }

    /// For UIKit's bars.
    package var uiImage: UIImage? {
        UIImage(named: assetName, in: .module, with: nil)?.withRenderingMode(.alwaysTemplate)
    }

    private var assetName: String {
        // Reposted is the same glyph, tinted.
        self == .repost ? Self.repostStroke.rawValue : rawValue
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
