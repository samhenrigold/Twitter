import Models
import PostText
import Routing
import SwiftUI

package struct Avatar: View {
    let url: URL?
    let size: CGFloat
    let decodeSize: CGFloat

    /// `decodeSize` is the size the image is decoded at, when it should match a prefetch rather than the drawn size.
    package init(user: User, size: CGFloat, decodeSize: CGFloat? = nil) {
        url = user.avatarURL(forSize: size)
        self.size = size
        self.decodeSize = decodeSize ?? size
    }

    package var body: some View {
        // A hairline frame, and `ProfilePlaceholderOverWhite` until the picture arrives.
        RemoteImage(url: url, pointSize: decodeSize) {
            Image("AvatarPlaceholder", bundle: .module).resizable()
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .overlay { Circle().strokeBorder(.avatarHairline, lineWidth: 0.5) }
        .accessibilityHidden(true)
    }
}

/// Name, badges, handle and time: one line in a timeline row, or the name over the handle beside a stacked row's
/// avatar.
package struct AuthorLine: View {
    package enum Layout: Sendable {
        /// "Name ✓ @handle · 2h" on one line.
        case inline
        /// "Name ✓" over "@handle · 2h".
        case stacked
    }

    let affiliate: AffiliateLabel?
    let badge: VerificationBadge?
    let date: Date?
    let layout: Layout
    let name: String
    let screenName: String
    @Environment(\.tweetMetrics) private var metrics

    package init(user: User, date: Date?, layout: Layout = .inline) {
        affiliate = user.affiliate
        badge = user.verificationBadge
        self.date = date
        self.layout = layout
        name = user.name
        screenName = user.screenName
    }

    package var body: some View {
        Group {
            switch layout {
            case .inline:
                HStack(spacing: metrics.authorLineSpacing) {
                    AuthorName(affiliate: affiliate, badge: badge, name: name)
                        .layoutPriority(1)

                    AuthorHandle(date: date, screenName: screenName)
                }
            case .stacked:
                VStack(alignment: .leading, spacing: metrics.stackedAuthorSpacing) {
                    AuthorName(affiliate: affiliate, badge: badge, name: name)

                    AuthorHandle(date: date, screenName: screenName)
                }
            }
        }
        .font(metrics.font(.body))
        .foregroundStyle(.twitterSecondary)
    }
}

/// The name and its badges. `authorBadgePadding`: 2.5 pt either side of the badge.
private struct AuthorName: View {
    let affiliate: AffiliateLabel?
    let badge: VerificationBadge?
    let name: String
    @Environment(\.tweetMetrics) private var metrics

    var body: some View {
        HStack(spacing: 2.5) {
            Text(name)
                .font(metrics.font(.body, weight: .bold))
                .foregroundStyle(.twitterPrimary)
                .lineLimit(1)

            if let badge {
                VerificationBadgeView(badge: badge)
                    .imageScale(.small)
            }

            if let affiliate {
                AffiliateBadge(label: affiliate, size: 14)
            }
        }
    }
}

/// "@handle · 2h", the time kept current as the row stays on screen.
private struct AuthorHandle: View {
    let date: Date?
    let screenName: String
    @Environment(\.tweetMetrics) private var metrics

    var body: some View {
        HStack(spacing: metrics.authorLineSpacing) {
            Text(verbatim: "@\(screenName)")
                .lineLimit(1)

            if let date {
                Text(verbatim: "·")

                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text(verbatim: date.shortRelative(to: context.date))
                        .fixedSize()
                }
            }
        }
    }
}

/// Post text: links, mentions, hashtags, cashtags and Twitter's bold/italic, typeset by ``PostTextTypesetter``.
///
/// The first frame draws from the typesetter's cache, or typesets inline when the text is short; long text draws as
/// plain text in the same font (so the row doesn't change height) while it typesets off the main actor, then swaps in
/// without animation. Long-pressing a mention, tag or link previews it (see ``PostTextPreviews``).
package struct TweetText: View {
    let input: PostTextInput
    /// Overrides the metrics' type ramp; `nil` draws `style` in Chirp at Twitter's line height.
    var font: Font?
    var style: TwitterTextStyle = .body
    @State private var prepared: TypesetPostText?
    @Environment(\.tweetMetrics) private var metrics

    /// Free text with its links (community notes, bios), read like a post: Markdown punctuation stays literal.
    package init(links: [String: URL], text: String, font: Font? = nil) {
        input = PostTextInput(text: text, links: links)
        self.font = font
    }

    /// The input a timeline row typesets for a post (cut to the timeline limit when it's long), so a feed can prepare
    /// it off the main actor before the row appears.
    nonisolated package static func timelineInput(for tweet: Tweet) -> PostTextInput {
        let isTruncated = PostTextInput.needsTruncation(tweet.text, limit: timelineCharacterLimit)
        return PostTextInput(
            text: tweet.text,
            links: tweet.links,
            tags: tweet.hashtags + tweet.cashtags,
            styles: tweet.styles,
            characterLimit: isTruncated ? timelineCharacterLimit : nil
        )
    }

    /// A post's text with its bold/italic styling and recognized hashtags and cashtags, cut to `characterLimit` when
    /// given (see ``truncated(_:limit:)``).
    package init(
        tweet: Tweet, style: TwitterTextStyle = .body, font: Font? = nil, characterLimit: Int? = nil
    ) {
        input = PostTextInput(
            text: tweet.text,
            links: tweet.links,
            tags: tweet.hashtags + tweet.cashtags,
            styles: tweet.styles,
            characterLimit: characterLimit
        )
        self.font = font
        self.style = style
    }

    package var body: some View {
        let typeset = prepared?.input == input ? prepared : PostTextTypesetter.cachedOrInline(input)
        Group {
            if let typeset {
                Text(entitiesTaggedIn: typeset)
                    .modifier(PostTextPreviews(typeset: typeset))
            } else {
                Text(verbatim: input.placeholderText)
                    .task(id: input) {
                        let result = await PostTextTypesetter.prepare(input)
                        // A recycled row may have moved on to another post while this one typeset.
                        guard !Task.isCancelled, result.input == input else { return }
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) { prepared = result }
                    }
            }
        }
        .font(font ?? metrics.font(style))
        .lineSpacing(font == nil ? metrics.lineSpacing(for: style) : 0)
        .foregroundStyle(.twitterPrimary)
        .tint(.twitterBlue)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Timeline rows show this many characters of a long post before "Show more".
    nonisolated package static let timelineCharacterLimit = 280

    /// `text` cut at a word boundary near `limit` with an ellipsis, or `nil` when it already fits.
    package static func truncated(_ text: String, limit: Int) -> String? {
        PostTextInput.truncated(text, limit: limit)
    }
}

package struct EngagementButton: View {
    let action: () -> Void
    var activeColor: Color = .twitterBlue
    var activeIcon: TwitterIcon?
    var count: Int?
    let icon: TwitterIcon
    var isActive = false
    let label: LocalizedStringKey

    package init(
        action: @escaping () -> Void,
        activeColor: Color = .twitterBlue,
        activeIcon: TwitterIcon? = nil,
        count: Int? = nil,
        icon: TwitterIcon,
        isActive: Bool = false,
        label: LocalizedStringKey
    ) {
        self.action = action
        self.activeColor = activeColor
        self.activeIcon = activeIcon
        self.count = count
        self.icon = icon
        self.isActive = isActive
        self.label = label
    }

    package var body: some View {
        Button(action: action) {
            EngagementLabel(
                icon: isActive ? activeIcon ?? icon : icon,
                count: count,
                minWidth: count == nil ? EngagementLabel.iconOnlyWidth : EngagementLabel.minimumWidth
            )
            .foregroundStyle(isActive ? activeColor : .twitterSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .sensoryFeedback(.selection, trigger: isActive)
    }
}

/// An action bar glyph and its count: an 18 pt icon in a 24 pt tall slot, with a 44 × 41 pt hit area around it
/// (`inlineActionMinimumTappingSize`) that doesn't push the neighbouring rows apart.
package struct EngagementLabel: View {
    let icon: TwitterIcon
    let count: Int?
    var minWidth: CGFloat = EngagementLabel.minimumWidth
    @Environment(\.tweetMetrics) private var metrics

    /// Buttons with counts are at least as wide as their hit area.
    package static let minimumWidth: CGFloat = 44
    /// Icon-only buttons draw narrower and grow their hit area to 44 sideways.
    package static let iconOnlyWidth: CGFloat = 34
    static let height: CGFloat = 24
    static let hitHeight: CGFloat = 41

    package init(icon: TwitterIcon, count: Int?, minWidth: CGFloat = EngagementLabel.minimumWidth) {
        self.icon = icon
        self.count = count
        self.minWidth = minWidth
    }

    package var body: some View {
        let horizontalSlack = max(EngagementLabel.minimumWidth - minWidth, 0) / 2
        let verticalSlack = (EngagementLabel.hitHeight - EngagementLabel.height) / 2
        HStack(spacing: 4) {
            TwitterIconView(icon)

            if let count, count > 0 {
                Text(count.compact)
                    // A count never wraps mid-number; the bar's flexible gaps give way instead.
                    .lineLimit(1)
                    .fixedSize()
                    .font(metrics.font(.subtext2))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(count)))
            }
        }
        .frame(
            minWidth: minWidth, minHeight: EngagementLabel.height,
            alignment: count == nil ? .center : .leading
        )
        // Never narrower than its icon and count, so a bar too tight for every label reports that it doesn't fit
        // instead of overlapping them.
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, horizontalSlack)
        .padding(.vertical, verticalSlack)
        .contentShape(.rect)
        .padding(.horizontal, -horizontalSlack)
        .padding(.vertical, -verticalSlack)
    }
}

extension Int {
    /// Twitter's count style: the full number below 10,000 ("1,234"), then K / M / B with one decimal, truncated and
    /// without a trailing ".0" ("12.3K", "123K", "1.2M").
    package var compact: String { compact(locale: .current) }

    /// ``compact`` in a given locale, which decides the grouping and decimal separators.
    package func compact(locale: Locale) -> String {
        guard magnitude >= 10_000 else { return formatted(.number.locale(locale)) }
        let units: [(Int, String)] = [
            (1_000_000_000_000, "T"), (1_000_000_000, "B"), (1_000_000, "M"), (1_000, "K")
        ]
        let value = self.magnitude
        guard let (divisor, suffix) = units.first(where: { value >= UInt($0.0) }) else {
            return formatted(.number.locale(locale))
        }
        // Integer division truncates, so 1,299,999 reads "1.2M", never "1.3M".
        let tenths = value / (UInt(divisor) / 10)
        let number = Double(tenths / 10) + Double(tenths % 10) / 10
        return (self < 0 ? "-" : "") + number.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
            + suffix
    }
}

extension Date {
    package var shortRelative: String { shortRelative(to: .now) }

    /// "2m", "3h", "4d", then the date, as of `now`.
    package func shortRelative(to now: Date) -> String {
        let seconds = now.timeIntervalSince(self)
        switch seconds {
        case ..<60: return "\(Swift.max(Int(seconds), 0))s"
        case ..<3_600: return "\(Int(seconds / 60))m"
        case ..<86_400: return "\(Int(seconds / 3_600))h"
        case ..<(86_400 * 7): return "\(Int(seconds / 86_400))d"
        default: return formatted(.dateTime.month(.abbreviated).day())
        }
    }
}
