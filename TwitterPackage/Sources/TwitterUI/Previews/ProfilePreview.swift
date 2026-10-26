import Models
import Routing
import SwiftUI
import UIKit

extension View {
    /// Long-pressing this view (an avatar) previews `user`'s profile with a menu to open, copy or share it; `open`
    /// runs for "View Profile" and for a tap on the preview.
    package func profilePreview(for user: User, open: @escaping () -> Void) -> some View {
        modifier(ProfilePreviewMenu(user: user, open: open))
    }
}

private struct ProfilePreviewMenu: ViewModifier {
    let user: User
    let open: () -> Void
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows

    func body(content: Content) -> some View {
        content.contextMenu {
            Button(action: open) {
                Label("View Profile", twitterIcon: .personStroke)
            }

            if supportsMultipleWindows {
                Button {
                    openWindow(value: Route.profile(user).window)
                } label: {
                    Label("Open in New Window", twitterIcon: .newWindow)
                }
            }

            Divider()

            Button {
                UIPasteboard.general.string = "@\(user.screenName)"
            } label: {
                Label("Copy Username", twitterIcon: .at)
            }

            if let url = user.profileURL {
                ShareLink(item: url)
            }
        } preview: {
            ProfilePreviewCard(user: user, screenName: user.screenName)
        }
    }
}
