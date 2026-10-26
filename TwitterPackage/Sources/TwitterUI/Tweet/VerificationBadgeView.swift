import Models
import SwiftUI

/// The check next to a verified name: blue for subscribers, gold for businesses, gray for governments.
package struct VerificationBadgeView: View {
    let badge: VerificationBadge

    package init(badge: VerificationBadge) {
        self.badge = badge
    }

    package var body: some View {
        // Twitter's badge, in the account's color, sized to the name it follows; a business's is its own gold.
        icon.image
            .resizable()
            .scaledToFit()
            .frame(width: 16, height: 16)
            .foregroundStyle(color)
            .accessibilityLabel(label)
    }

    private var icon: TwitterIcon {
        badge == .business ? .verifiedGold : .verified
    }

    private var color: Color {
        badge == .government ? Color(.badgeGovernment) : .twitterBlue
    }

    private var label: Text {
        switch badge {
        case .blue: Text("Verified")
        case .business: Text("Verified organization")
        case .government: Text("Verified government account")
        }
    }
}
