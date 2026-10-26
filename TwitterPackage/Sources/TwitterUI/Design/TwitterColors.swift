import SwiftUI

/// Twitter's timeline palette (light, and the "lights out" dark theme), from the asset catalog.
extension Color {
    /// gray1100 / #D9D9D9.
    package static let twitterPrimary = Color(.twitterPrimary)
    /// gray700: handles, timestamps, counts.
    package static let twitterSecondary = Color(.twitterSecondary)
    /// gray200: dividers and thread lines.
    package static let twitterDivider = Color(.twitterDivider)
    /// blue500: links, brand, verified.
    package static let twitterBlue = Color(.twitterBlue)
    /// Twitter's like pink (pink500), for the heart and its count.
    package static let twitterLike = Color(.twitterLike)
    /// Twitter 4.x's retweet green, from `ic_action_rt_on`'s lower edge.
    package static let twitterRepost = Color(.twitterRepost)
    /// `borderMedia`: 5% black or white.
    package static let twitterMediaBorder = Color(.twitterMediaBorder)
    /// The pale blue behind notifications that arrived since they were last read.
    package static let twitterUnread = Color(.twitterUnread)
    /// Errors and the over-limit count.
    package static let twitterError = Color(.twitterError)
    /// Nearing the character limit.
    package static let twitterWarning = Color(.twitterWarning)
    /// Notification glyphs for stars, Spaces and live.
    package static let twitterPurple = Color(.twitterPurple)
    /// Notification glyphs for security.
    package static let twitterOrange = Color(.twitterOrange)
    /// Glyphs drawn over photos and video (play, GIF).
    package static let mediaGlyph = Color(.mediaGlyph)
    /// Behind media shown full screen.
    package static let mediaBackdrop = Color(.mediaBackdrop)
    /// Darkens media under controls.
    package static let mediaScrim = Color(.mediaScrim)
    /// The hairline around avatars.
    package static let avatarHairline = Color(.avatarHairline)
    /// Recessed backgrounds (a gap in a timeline).
    package static let twitterGroove = Color(.twitterGroove)
    /// Behind content: white, or black in dark mode.
    package static let twitterBackground = Color(.twitterBackground)
    /// A profile's banner area before (or without) a header photo.
    package static let bannerPlaceholder = Color(.bannerPlaceholder)
    /// The leading choice's bar in a finished poll.
    package static let pollLeader = Color(.pollLeader)
    /// Behind the 'Follows you' label.
    package static let followsYouBadge = Color(.followsYouBadge)
}

extension ShapeStyle where Self == Color {
    package static var twitterPrimary: Color { Color.twitterPrimary }
    package static var twitterSecondary: Color { Color.twitterSecondary }
    package static var twitterDivider: Color { Color.twitterDivider }
    package static var twitterBlue: Color { Color.twitterBlue }
    package static var twitterLike: Color { Color.twitterLike }
    package static var twitterRepost: Color { Color.twitterRepost }
    package static var twitterMediaBorder: Color { Color.twitterMediaBorder }
    package static var twitterUnread: Color { Color.twitterUnread }
    package static var twitterError: Color { Color.twitterError }
    package static var twitterWarning: Color { Color.twitterWarning }
    package static var twitterPurple: Color { Color.twitterPurple }
    package static var twitterOrange: Color { Color.twitterOrange }
    package static var mediaGlyph: Color { Color.mediaGlyph }
    package static var mediaBackdrop: Color { Color.mediaBackdrop }
    package static var mediaScrim: Color { Color.mediaScrim }
    package static var avatarHairline: Color { Color.avatarHairline }
    package static var twitterGroove: Color { Color.twitterGroove }
    package static var twitterBackground: Color { Color.twitterBackground }
    package static var bannerPlaceholder: Color { Color.bannerPlaceholder }
    package static var pollLeader: Color { Color.pollLeader }
    package static var followsYouBadge: Color { Color.followsYouBadge }
}

/// A full-bleed hairline in the divider colour, in place of the system `Divider`.
package struct TwitterDivider: View {
    @Environment(\.displayScale) private var displayScale

    package init() {}

    package var body: some View {
        Rectangle()
            .fill(.twitterDivider)
            .frame(height: 1 / displayScale)
            .accessibilityHidden(true)
    }
}
