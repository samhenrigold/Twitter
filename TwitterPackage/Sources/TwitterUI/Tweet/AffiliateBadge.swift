import Dependencies
import ImagePipeline
import Models
import SwiftUI

/// The small avatar of the organization an account is affiliated with.
package struct AffiliateBadge: View {
    let label: AffiliateLabel
    let size: CGFloat

    package init(label: AffiliateLabel, size: CGFloat) {
        self.label = label
        self.size = size
    }

    @Dependency(ImageLoader.self) private var loader
    @Environment(\.displayScale) private var displayScale
    @State private var loaded: CGImage?

    package var body: some View {
        let request = label.badgeURL.map { ImageRequest(url: $0, pointSize: size, scale: displayScale) }
        // Nothing, at no width, until the badge loads: an empty placeholder next to a name reads as a broken image,
        // and a reserved slot leaves a gap when the badge never arrives.
        if let image = loaded ?? request.flatMap(loader.cached) {
            Image(decorative: image, scale: displayScale)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size / 5))
                .accessibilityElement()
                .accessibilityLabel("Affiliated with \(label.description)")
        } else {
            Color.clear
                .frame(width: 0, height: size)
                .accessibilityHidden(true)
                .task(id: request) {
                    guard let request else { return }
                    loaded = await loader.image(request)
                }
        }
    }
}
