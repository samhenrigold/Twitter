import Models

extension FeedItem {
    package var tweets: [Tweet] {
        switch self {
        case .notification(let notification):
            notification.tweet.map { [$0] } ?? []
        case .tweet(let feedTweet):
            [feedTweet.tweet] + feedTweet.tweet.quoted
        case .tombstone, .showMore:
            []
        }
    }

    /// Applies `update` to every copy of a user in this item (author, quoted author, reposter).
    mutating func updateUser(id: String, _ update: (inout User) -> Void) {
        guard case .tweet(var feedTweet) = self else { return }
        if feedTweet.tweet.author.id == id { update(&feedTweet.tweet.author) }
        for index in feedTweet.tweet.quoted.indices where feedTweet.tweet.quoted[index].author.id == id {
            update(&feedTweet.tweet.quoted[index].author)
        }
        if feedTweet.repostedBy?.id == id { update(&feedTweet.repostedBy!) }
        self = .tweet(feedTweet)
    }
}
