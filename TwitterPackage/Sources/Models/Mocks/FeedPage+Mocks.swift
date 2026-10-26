import Foundation

extension FeedPage {
    package static let mockShowMoreCursor = "mock-show-more"
    /// The rest of ``Tweet/mockReply``'s conversation, above what its thread first sends.
    package static let mockEarlierCursor = "mock-earlier"

    package static func mock(_ source: FeedSource) -> FeedPage {
        mock(source, cursor: nil)
    }

    package static func mock(_ source: FeedSource, cursor: String?) -> FeedPage {
        func item(_ tweet: Tweet) -> FeedItem { .tweet(FeedTweet(id: tweet.id, tweet: tweet)) }
        if cursor == mockShowMoreCursor {
            return FeedPage(
                items: [
                    .tweet(
                        FeedTweet(id: "203", tweet: .mock(id: "203", text: "Late to the party, but this is great."))),
                    .tombstone(Tombstone(id: "tweet-204", text: "This Tweet is unavailable."))
                ],
                bottomCursor: nil,
                topCursor: nil
            )
        }
        if cursor == mockEarlierCursor {
            return FeedPage(items: Tweet.mockReplyAncestors.dropLast().map(item), bottomCursor: nil, topCursor: nil)
        }
        if case .thread(let tweetID) = source {
            // The opened post is the thread's focus, so mock threads show it focused like real ones.
            let focused = (Tweet.mocks + [.mockRestricted, .mockReply]).first { $0.id == tweetID } ?? .mockRestricted
            var replies = Tweet.mockReplies.map { FeedTweet(id: $0.id, tweet: $0) }
            replies[0].connectsBelow = true
            replies[1].connectsAbove = true
            // A reply's thread starts with the conversation above it: like a long conversation, only the nearest of
            // it, with a cursor for the rest.
            let ancestors = tweetID == Tweet.mockReply.id ? Array(Tweet.mockReplyAncestors.suffix(1)) : []
            return FeedPage(
                items: ancestors.map(item) + [
                    item(focused),
                    .tweet(replies[0]),
                    .tweet(replies[1]),
                    .tombstone(Tombstone(id: "tweet-209", text: "This Tweet was hidden by the Tweet author.")),
                    .showMore(ShowMoreCursor(id: "cursor-showmorethreads-1", cursor: mockShowMoreCursor))
                ],
                bottomCursor: nil,
                topCursor: ancestors.isEmpty ? nil : mockEarlierCursor
            )
        }
        if source == .notifications(.all) {
            // What arrived since they were last read is marked unread, as Twitter marks it.
            let users = Array(User.mockCrowd.prefix(3))
            let notifications = [
                TwitterNotification(
                    id: "n1", icon: "heart_icon", message: "\(users[0].name) and 2 others liked your Tweet",
                    boldRanges: [0..<users[0].name.unicodeScalars.count], users: users,
                    date: .now.addingTimeInterval(-300),
                    tweet: Tweet.mocks[0], tweetID: Tweet.mocks[0].id, isUnread: true),
                TwitterNotification(
                    id: "n2", icon: "person_icon", message: "\(users[1].name) followed you",
                    boldRanges: [0..<users[1].name.unicodeScalars.count], users: [users[1]],
                    date: .now.addingTimeInterval(-7200))
            ]
            var mention = FeedTweet(id: Tweet.mockReply.id, tweet: .mockReply)
            mention.isUnread = true
            return FeedPage(
                items: [.tweet(mention)] + notifications.map(FeedItem.notification), bottomCursor: nil,
                topCursor: "mock-top")
        }
        if case .searchMedia = source {
            // A search's photos and videos: only posts with media.
            return FeedPage(items: [item(.mockPhotos)], bottomCursor: nil, topCursor: nil)
        }
        if case .search(let query, _) = source, query.hasPrefix(FeedSource.quotesQueryPrefix) {
            // Quotes of the post the search names, as a post's Quotes list shows them.
            let quotedID = String(query.dropFirst(FeedSource.quotesQueryPrefix.count))
            let quoted = (Tweet.mocks + [.mockRestricted]).first { $0.id == quotedID } ?? Tweet.mocks[0]
            let quotes = zip(User.mockCrowd.prefix(3), ["This is the one.", "Finally!", "Saving this for later."])
            return FeedPage(
                items: quotes.enumerated().map { index, quote in
                    var tweet = Tweet.mock(
                        id: "q\(index)-\(quotedID)", author: quote.0, text: quote.1, secondsAgo: Double(index + 1) * 900
                    )
                    tweet.quoted = [quoted]
                    return item(tweet)
                },
                bottomCursor: nil,
                topCursor: nil
            )
        }
        var items = Tweet.mocks.map(item)
        items.insert(item(.mockLongPost), at: 1)
        items.insert(item(.mockPoll), at: 2)
        items.insert(item(.mockReply), at: 3)
        items.insert(item(.mockJapanese), at: 4)
        items.insert(item(.mockOpenPoll), at: 5)
        items.insert(.tombstone(Tombstone(id: "tweet-109", text: "This Tweet was deleted by the Tweet author.")), at: 6)
        items += [item(.mockCommunityNote), item(.mockRestricted), item(.mockQuotingDeleted), item(.mockFinalPoll)]
        // `--mock-media`: a video, a GIF and photos to open in the viewer, kept out of the default set so snapshots stay
        // put.
        if ProcessInfo.processInfo.arguments.contains("--mock-media") {
            items.insert(contentsOf: [item(.mockVideo), item(.mockGIF), item(.mockPhotos)], at: 0)
        }
        return FeedPage(items: items, bottomCursor: nil, topCursor: nil)
    }
}
