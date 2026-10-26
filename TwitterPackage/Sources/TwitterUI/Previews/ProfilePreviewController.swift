import Models
import SwiftUI
import UIKit

/// A preview for a profile known only by its handle, such as a mention: a placeholder card until the account is
/// found, from memory, the on-disk cache, then the network.
struct LoadingProfilePreview: View {
    let screenName: String
    @State private var user: User?

    var body: some View {
        ProfilePreviewCard(user: user ?? ProfileLookup.remembered(screenName), screenName: screenName)
            .task(id: screenName) {
                if user == nil, let stored = await ProfileLookup.stored(screenName) {
                    user = stored
                }
                if let fresh = await ProfileLookup.fetch(screenName) {
                    withAnimation(.snappy) { user = fresh }
                }
            }
    }
}

/// Hosts ``LoadingProfilePreview`` as a context menu preview, sized to the card as it loads.
final class ProfilePreviewController: UIHostingController<LoadingProfilePreview> {
    init(screenName: String) {
        super.init(rootView: LoadingProfilePreview(screenName: screenName))
        sizingOptions = .preferredContentSize
        view.backgroundColor = .systemBackground
    }

    @available(*, unavailable)
    @MainActor required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
