import Models
import SwiftUI
import TwitterUI

/// The post being replied to, above the reply as in Twitter's composer: its author and text, a thread line down
/// toward the reply, and who the reply goes to.
struct ReplyContext: View {
    let tweet: Tweet

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 4) {
                Avatar(user: tweet.author, size: 40)

                Rectangle()
                    .fill(.twitterDivider)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                AuthorLine(user: tweet.author, date: tweet.createdAt)

                Text(tweet.text)
                    .font(.subheadline)
                    .lineLimit(6)

                Text("Replying to @\(tweet.author.screenName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
        }
        .tweetMetrics()
        .accessibilityElement(children: .combine)
    }
}
