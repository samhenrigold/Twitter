import Models
import SwiftUI

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
