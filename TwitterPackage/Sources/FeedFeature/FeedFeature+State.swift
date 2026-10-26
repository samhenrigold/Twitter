import ComposableArchitecture
import Models

extension FeedFeature.State {
    /// A thread opened from one of its posts, which shows at once in its focused layout while the rest loads.
    ///
    /// A reply starts out joined to the conversation above it, as it will be once that arrives, so the focused
    /// row's layout doesn't change under the reader when it does.
    package static func thread(opening tweet: Tweet) -> Self {
        var item = FeedTweet(tweet: tweet)
        item.connectsAbove = !tweet.replyingTo.isEmpty
        return Self(source: .thread(tweetID: tweet.id), items: [.tweet(item)])
    }

    /// In a thread, joins the conversation above the focused post into one line down to it, and offers whatever
    /// Twitter left out above it (a long conversation sends only its last few posts, with a cursor for the rest).
    mutating func showEarlierConversation(above topCursor: String?) {
        guard let focusedID = focusedItemID, let focusedIndex = items.index(id: focusedID) else { return }
        items.remove(id: FeedItem.showMore(ShowMoreCursor(id: Self.earlierConversationID, cursor: "")).id)
        if let topCursor {
            items.insert(
                .showMore(
                    ShowMoreCursor(
                        id: Self.earlierConversationID, cursor: topCursor, label: "Show earlier Tweets")),
                at: 0
            )
        }
        let focusedIndexNow = items.index(id: focusedID) ?? focusedIndex
        for index in items.indices.prefix(through: focusedIndexNow) {
            guard case .tweet(var tweet) = items[index] else { continue }
            let follows = index > 0 && { if case .tweet = items[index - 1] { true } else { false } }()
            tweet.connectsAbove = follows
            if index < focusedIndexNow { tweet.connectsBelow = true }
            items[index] = .tweet(tweet)
        }
    }

    mutating func setBlocking(_ isBlocking: Bool, userID: String) {
        for id in items.ids {
            items[id: id]?.updateUser(id: userID) { $0.isBlocking = isBlocking }
        }
    }

    /// The poll of post `tweetID`, wherever it shows (or is quoted).
    func poll(of tweetID: Tweet.ID) -> Poll? {
        for item in items {
            if let poll = item.tweets.first(where: { $0.id == tweetID })?.poll { return poll }
        }
        return nil
    }

    mutating func updatePoll(of tweetID: Tweet.ID, _ update: (inout Poll) -> Void) {
        for id in items.ids {
            guard case .tweet(var feedTweet) = items[id: id] else { continue }
            if feedTweet.tweet.id == tweetID, feedTweet.tweet.poll != nil { update(&feedTweet.tweet.poll!) }
            for index in feedTweet.tweet.quoted.indices
            where feedTweet.tweet.quoted[index].id == tweetID && feedTweet.tweet.quoted[index].poll != nil {
                update(&feedTweet.tweet.quoted[index].poll!)
            }
            items[id: id] = .tweet(feedTweet)
        }
    }

    mutating func setMuting(_ isMuting: Bool, userID: String) {
        for id in items.ids {
            items[id: id]?.updateUser(id: userID) { $0.isMuting = isMuting }
        }
    }
}
