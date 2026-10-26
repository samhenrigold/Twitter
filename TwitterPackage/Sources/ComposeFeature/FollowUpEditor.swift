import SwiftUI
import TwitterUI

/// A Tweet after the first in a thread: a thread line down from the one before, its own text and count, and a way
/// to take it out.
struct FollowUpEditor: View {
    @Binding var text: String
    let remainingCharacters: Int
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Rectangle()
                .fill(.twitterDivider)
                .frame(width: 2)
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 7)

            VStack(alignment: .trailing, spacing: 4) {
                TextField("Add another Tweet", text: $text, axis: .vertical)
                    .font(.title3)
                    .lineLimit(2...)

                HStack {
                    Text(remainingCharacters, format: .number)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(remainingCharacters < 0 ? .twitterError : .secondary)

                    Button("Remove", twitterIcon: .close, action: remove)
                        .labelStyle(.iconOnly)
                        .controlSize(.small)
                }
            }
        }
    }
}
