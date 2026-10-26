import Models
import SwiftUI
import TwitterUI

/// Accounts to complete the mention being typed, as Twitter's composer lists them.
struct MentionSuggestions: View {
    let users: [User]
    let select: (User) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(users) { user in
                Button {
                    select(user)
                } label: {
                    HStack(spacing: 10) {
                        Avatar(user: user, size: 36)

                        AuthorLine(user: user, date: nil, layout: .stacked)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 6)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)

                if user.id != users.last?.id {
                    Divider()
                }
            }
        }
        .tweetMetrics()
    }
}
