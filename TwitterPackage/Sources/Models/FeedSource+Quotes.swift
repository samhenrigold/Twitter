extension FeedSource {
    package static let quotesQueryPrefix = "quoted_tweet_id:"

    /// A post's quotes, newest first. The web client finds them with a search for `quoted_tweet_id:`, so they page,
    /// refresh and cache like any search.
    package static func quotes(of tweetID: String) -> FeedSource {
        .search(query: quotesQueryPrefix + tweetID, latest: true)
    }
}
