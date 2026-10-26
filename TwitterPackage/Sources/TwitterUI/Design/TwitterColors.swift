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
