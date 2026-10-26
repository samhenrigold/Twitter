import SwiftUI

/// A screen's "…" menu: at the trailing end of its bar, in iPhone Duo's vertical bar while the screen is the focused
/// column, or nowhere while the vertical bar shows another column's (`placement`, from
/// ``EnvironmentValues/columnBarPlacement``).
package struct ColumnMenuToolbarItem<Items: View>: ToolbarContent {
    let icon: TwitterIcon
    let placement: ColumnBarPlacement
    let title: LocalizedStringKey
    let items: Items

    package init(
        _ title: LocalizedStringKey, twitterIcon icon: TwitterIcon = .more, placement: ColumnBarPlacement,
        @ViewBuilder items: () -> Items
    ) {
        self.icon = icon
        self.placement = placement
        self.title = title
        self.items = items()
    }

    package var body: some ToolbarContent {
        if placement != .hidden {
            ToolbarItem(placement: placement == .verticalBar ? .bottomBar : .topBarTrailing) {
                Menu {
                    items
                } label: {
                    Label(title, twitterIcon: icon)
                }
            }
            .axisBehavior(.verticalPreferred)
        }
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

/// Where a screen's bar buttons go.
package enum ColumnBarPlacement: Sendable {
    /// Its own bar.
    case ownBar
    /// iPhone Duo's vertical bar: the screen is the focused column.
    case verticalBar
    /// Nowhere: the vertical bar carries the focused column's, and the other columns' bars stay empty.
    case hidden
}

extension EnvironmentValues {
    @Entry package var columnBarPlacement = ColumnBarPlacement.ownBar
}
