import SwiftUI

extension View {
    /// Images in timelines, profiles and previews keep HDR photos to a limited headroom, so a bright photo doesn't
    /// outshine the text around it. Applied at the root of each SwiftUI hierarchy (windows, columns, previews); the
    /// media viewer lifts it again for the photo on its own.
    package func limitsImageHeadroom() -> some View {
        allowedDynamicRange(.constrainedHigh)
    }
}
