import SwiftUI
import TwitterUI

extension View {
    /// Caps line length for reading while letting the scroll view (and its indicators) span the column, and sizes the
    /// rows' text and metrics for the width they get.
    func readableContentWidth() -> some View {
        // Greedy inside the cap, so the width the metrics measure is the width offered, never one the metrics sized.
        frame(maxWidth: .infinity).frame(maxWidth: 680).tweetMetrics().frame(maxWidth: .infinity)
    }
}
