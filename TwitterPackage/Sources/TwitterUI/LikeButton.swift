import Pow
import SwiftUI

package struct LikeButton: View {
    let action: () -> Void
    let count: Int
    let isLiked: Bool
    @Environment(\.tweetMetrics) private var metrics

    package init(isLiked: Bool, count: Int, action: @escaping () -> Void) {
        self.action = action
        self.count = count
        self.isLiked = isLiked
    }

    package var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                ZStack {
                    if isLiked {
                        TwitterIconView(.heart)
                            .foregroundStyle(.twitterLike)
                            .transition(.movingParts.pop(Color.twitterLike))
                    } else {
                        TwitterIconView(.heartStroke)
                            .foregroundStyle(.twitterSecondary)
                            .transition(.identity)
                    }
                }
                .animation(.default, value: isLiked)

                if count > 0 {
                    Text(count.compact)
                        // A count never wraps mid-number; the bar's flexible gaps give way instead.
                        .lineLimit(1)
                        .fixedSize()
                        .font(metrics.font(.subtext2))
                        .monospacedDigit()
                        .foregroundStyle(isLiked ? .twitterLike : .twitterSecondary)
                        .animation(isLiked ? .default.delay(0.4) : nil, value: isLiked)
                }
            }
            .frame(minWidth: EngagementLabel.minimumWidth, minHeight: 24, alignment: .leading)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.vertical, 8.5)
            .contentShape(.rect)
            .padding(.vertical, -8.5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isLiked ? "Unlike" : "Like")
        .accessibilityValue(count.formatted())
        .sensoryFeedback(.selection, trigger: isLiked)
    }
}

#Preview {
    @Previewable @State var isLiked = false
    LikeButton(isLiked: isLiked, count: isLiked ? 561 : 560) {
        isLiked.toggle()
    }
    .padding()
}
