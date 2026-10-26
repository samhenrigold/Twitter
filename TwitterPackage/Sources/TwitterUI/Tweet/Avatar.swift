import Models
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
