/// A post as it appears in a feed, with the context of how it got there.
package struct FeedTweet: Identifiable, Hashable, Codable, Sendable {
    package var id: String
    package var tweet: Tweet
    package var repostedBy: User?
    package var socialContext: String?
    /// Glyph for the context line: one of Twitter's icons by asset name, or an SF Symbol ("Pinned", "Twitter liked", "Followed by …").
    package var socialSymbol: String?
    /// Draws a thread line down to the next post (conversation modules and reply chains).
    package var connectsBelow = false
    package var connectsAbove = false
    /// A mention or reply in Notifications that arrived since they were last read.
    package var isUnread = false
}

extension FeedTweet {
    package init(tweet: Tweet) {
        self.init(id: tweet.id, tweet: tweet)
    }
}
