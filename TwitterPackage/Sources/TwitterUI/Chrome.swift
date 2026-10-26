import SwiftUI

/// A screen's "…" menu: at the trailing end of its bar, or in iPhone Duo's vertical bar while the screen is the focused
/// column (`isInVerticalBar`, from ``EnvironmentValues/columnBarItemsInVerticalBar``).
package struct ColumnMenuToolbarItem<Items: View>: ToolbarContent {
    let icon: TwitterIcon
    let isInVerticalBar: Bool
    let title: LocalizedStringKey
    let items: Items

    package init(
        _ title: LocalizedStringKey, twitterIcon icon: TwitterIcon = .more, isInVerticalBar: Bool,
        @ViewBuilder items: () -> Items
    ) {
        self.icon = icon
        self.isInVerticalBar = isInVerticalBar
        self.title = title
        self.items = items()
    }

    package var body: some ToolbarContent {
        ToolbarItem(placement: isInVerticalBar ? .bottomBar : .topBarTrailing) {
            Menu {
                items
            } label: {
                Label(title, twitterIcon: icon)
            }
        }
        .axisBehavior(.verticalPreferred)
    }
}

/// Follow and Following: prominent to follow, the call to action; plain once following.
package struct FollowButton: View {
    let action: () -> Void
    let isFollowing: Bool

    package init(isFollowing: Bool, action: @escaping () -> Void) {
        self.action = action
        self.isFollowing = isFollowing
    }

    package var body: some View {
        Group {
            if isFollowing {
                Button("Following", action: action)
                    .buttonStyle(.bordered)
            } else {
                Button("Follow", action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
        .buttonBorderShape(.capsule)
        .font(.subheadline.weight(.bold))
        .sensoryFeedback(.success, trigger: isFollowing)
    }
}

/// The actions under a post's details: spread evenly across the full width, between hairlines.
package struct DetailActionBar<Content: View>: View {
    @ViewBuilder let content: Content

    package init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    package var body: some View {
        HStack(spacing: 0) {
            ForEach(subviews: content) { action in
                action.frame(maxWidth: .infinity)
            }
        }
        .environment(\.engagementIconSize, 22)
        .frame(minHeight: 44)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
    }
}

extension EnvironmentValues {
    /// Whether this screen is the focused column, whose bar buttons iPhone Duo's vertical bar carries.
    @Entry package var columnBarItemsInVerticalBar = false
}
