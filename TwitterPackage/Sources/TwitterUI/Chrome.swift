import SwiftUI

/// A screen's "…" menu, at the trailing end of its bar.
package struct ColumnMenuToolbarItem<Items: View>: ToolbarContent {
    let systemImage: String
    let title: LocalizedStringKey
    let items: Items

    package init(_ title: LocalizedStringKey, systemImage: String = "ellipsis", @ViewBuilder items: () -> Items) {
        self.systemImage = systemImage
        self.title = title
        self.items = items()
    }

    package var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu(title, systemImage: systemImage) {
                items
            }
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
