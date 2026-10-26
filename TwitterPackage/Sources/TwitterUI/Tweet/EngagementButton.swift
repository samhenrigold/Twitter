import SwiftUI

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
