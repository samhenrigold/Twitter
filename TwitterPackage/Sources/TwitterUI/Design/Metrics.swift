import SwiftUI

/// Timeline metrics derived the way Twitter for iPhone derives them: everything scales from one base text size.
///
/// The base is `14 + Dynamic Type offset + width class`, so a 393 pt column at the default text size reads at 15 pt
/// with a 19.29 pt line, a 44.33 pt avatar and an 8.33 pt gutter. Set once per column with ``SwiftUI/View/tweetMetrics()``.
package struct TweetMetrics: Equatable, Sendable {
    /// The `body` text size every other metric derives from.
    package let bodySize: CGFloat
    /// Bold Text swaps each weight one step heavier, as Twitter does.
    package let isBoldText: Bool
    /// Whether the column is too narrow, for its text size, to give up an avatar's width beside every post: fewer
    /// than ``narrowColumnEms`` body ems across. Posts lay out stacked here when the viewer leaves it automatic.
    package let isNarrowColumn: Bool

    package init(bodySize: CGFloat, isBoldText: Bool = false, isNarrowColumn: Bool = false) {
        self.bodySize = min(max(bodySize, 8), 50)
        self.isBoldText = isBoldText
        self.isNarrowColumn = isNarrowColumn
    }

    package init(width: CGFloat, dynamicTypeSize: DynamicTypeSize, isBoldText: Bool = false) {
        let bodySize = 14 + Self.offset(for: dynamicTypeSize) + CGFloat(Self.widthClass(for: width))
        self.init(
            bodySize: bodySize,
            isBoldText: isBoldText,
            isNarrowColumn: Self.isNarrow(width: width, bodySize: bodySize)
        )
    }

    /// 28 em: 420 pt at 15 pt text. iPhone Duo's closed display (~375 pt of content) and a 6.1-inch iPhone fall
    /// under it; a 476 pt column on the inner display (16 pt text, 29.75 em) and anything wider don't. Larger text
    /// narrows a column in ems, so it tips into stacked sooner.
    package static let narrowColumnEms: CGFloat = 28

    static func isNarrow(width: CGFloat, bodySize: CGFloat) -> Bool {
        width < narrowColumnEms * min(max(bodySize, 8), 50)
    }

    /// 15 pt: a 6.1-inch iPhone at the default text size.
    package static let standard = TweetMetrics(bodySize: 15)

    /// Lines are 18/14 of the text size (compact width, regular height).
    package var lineHeight: CGFloat { bodySize * 18 / 14 }
    /// Twitter's spacing unit: an 18 pt grid scaled to the line height.
    package var unit: CGFloat { lineHeight / 18 }
    /// 2.29 line heights.
    package var avatarSize: CGFloat { Self.ceil3x(2.29 * lineHeight) }
    /// Avatar to content: 0.575 em, at least 8.
    package var gutter: CGFloat { max(Self.floor3x(0.575 * bodySize), 8) }
    /// Kept at 16 rather than the production 9 pt (a server-tuned experiment).
    package var sideInset: CGFloat { 16 }
    /// 0.86 em, plus a hairline on top.
    package var contentInset: CGFloat { Self.floor3x(0.86 * bodySize) }
    package var topInset: CGFloat { contentInset + 1 / 3 }
    package var bottomInset: CGFloat { contentInset }
    /// Where text, media, cards and the action bar start.
    package var bodyLeading: CGFloat { avatarSize + gutter }
    /// Author line to body text: 2u, Twitter's conversation-context margin. The spec's 8u is measured between text
    /// frames that already carry Chirp's leading, so drawn here it reads twice as loose as the app.
    package var authorBodyMargin: CGFloat { 2 * unit }
    /// Name to handle, and either side of the "·" before the time: a Chirp word space (0.2 em).
    package var authorLineSpacing: CGFloat { Self.floor3x(0.2 * bodySize) }
    /// The name over the handle in a stacked author block: Chirp's line boxes already leave ~4 pt between them,
    /// so the lines overlap by a point to read as one unit.
    package var stackedAuthorSpacing: CGFloat { -1 }
    /// A stacked row's avatar to the post under it: 6u, about the gap Twitter leaves under the focused post's avatar.
    package var stackedBodyMargin: CGFloat { 6 * unit }
    /// Between body text, media and cards.
    package var mediaTextMargin: CGFloat { 8 * unit }
    /// Body to the action bar, less the 4 pt the bar is lifted by.
    package var actionTopMargin: CGFloat { 12 * unit - 4 }
    /// Row padding under the action bar: the bar is lifted 4 pt, and its 24 pt slot already leaves 3 pt under the
    /// 18 pt glyph, so the icons end ~8.7 pt above the divider.
    package var actionBarBottomInset: CGFloat { bottomInset - 4 - 3 }
    /// The quoted post's avatar: 0.86 line heights.
    package var quoteAvatarSize: CGFloat { Self.ceil3x(0.86 * lineHeight) }
    /// Extra leading that brings a line of Chirp at `size` to the 18/14 line height.
    package func lineSpacing(for style: TwitterTextStyle) -> CGFloat {
        let size = self.size(style)
        return max(size * 18 / 14 - TwitterFont.lineHeight(size: size), 0)
    }

    /// One line of Chirp at `style`'s size, without the 18/14 leading: the height of a glyph set in a line of it.
    package func glyphSize(for style: TwitterTextStyle) -> CGFloat {
        TwitterFont.lineHeight(size: size(style))
    }

    package func size(_ style: TwitterTextStyle) -> CGFloat {
        bodySize + style.offset
    }

    package func font(_ style: TwitterTextStyle, weight: TwitterFont.Weight = .regular) -> Font {
        TwitterFont.font(size: size(style), weight: isBoldText ? weight.bolder : weight)
    }

    /// `TFNWindowSizeClass`: 0 below 376 pt, 1 to 400, 2 to 512, 3 above.
    package static func widthClass(for width: CGFloat) -> Int {
        switch width {
        case ..<376: 0
        case ..<401: 1
        case ..<513: 2
        default: 3
        }
    }

    static func offset(for size: DynamicTypeSize) -> CGFloat {
        switch size {
        case .xSmall: -2
        case .small: -1
        case .medium, .large: 0
        case .xLarge: 1
        case .xxLarge: 3
        case .xxxLarge: 6
        case .accessibility1: 10
        case .accessibility2: 15
        case .accessibility3: 20
        case .accessibility4: 25
        case .accessibility5: 30
        @unknown default: 0
        }
    }

    static func ceil3x(_ value: CGFloat) -> CGFloat { (value * 3).rounded(.up) / 3 }
    static func floor3x(_ value: CGFloat) -> CGFloat { (value * 3).rounded(.down) / 3 }
}

/// Twitter's type ramp, as offsets from `body`.
package enum TwitterTextStyle: Sendable {
    case body, subtext1, subtext2, subtext3, headline2, headline1, title4, title3, title2, title1

    var offset: CGFloat {
        switch self {
        case .body: 0
        case .subtext1: -1
        case .subtext2: -2
        case .subtext3: -4
        case .headline2: 2
        case .headline1: 5
        case .title4: 8
        case .title3: 11
        case .title2: 16
        case .title1: 19
        }
    }
}

extension EnvironmentValues {
    @Entry package var tweetMetrics = TweetMetrics.standard
}

extension View {
    /// Derives ``TweetMetrics`` from this view's width and the Dynamic Type size, for everything inside it. Apply once
    /// per column; the environment only changes when the width crosses a size class.
    package func tweetMetrics() -> some View {
        modifier(TweetMetricsModifier())
    }
}

private struct TweetMetricsModifier: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.legibilityWeight) private var legibilityWeight
    @State private var column = ColumnClass(widthClass: 1, isNarrow: false)

    func body(content: Content) -> some View {
        let offset = TweetMetrics.offset(for: dynamicTypeSize)
        content
            .onGeometryChange(for: ColumnClass.self) { proxy in
                let width = proxy.size.width
                let widthClass = TweetMetrics.widthClass(for: width)
                return ColumnClass(
                    widthClass: widthClass,
                    isNarrow: TweetMetrics.isNarrow(width: width, bodySize: 14 + offset + CGFloat(widthClass))
                )
            } action: {
                column = $0
            }
            .environment(
                \.tweetMetrics,
                TweetMetrics(
                    bodySize: 14 + offset + CGFloat(column.widthClass),
                    isBoldText: legibilityWeight == .bold,
                    isNarrowColumn: column.isNarrow
                )
            )
    }
}

/// What a column's width decides, so a resize only reaches the column's posts when one of these flips.
private struct ColumnClass: Equatable {
    var widthClass: Int
    var isNarrow: Bool
}
