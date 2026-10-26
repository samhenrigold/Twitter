import Models

extension TwitterWebSession {
    func feed(_ source: FeedSource, cursor: String?) async throws -> FeedPage {
        switch source {
        case .bookmarks:
            try await bookmarks(cursor: cursor)
        case .home(let following):
            try await homeTimeline(following: following, cursor: cursor)
        case .list(let id, _):
            try await listTimeline(id: id, cursor: cursor)
        case .notifications(let filter):
            try await notifications(type: filter.rawValue, cursor: cursor)
        case .search(let query, let latest):
            try await search(query, product: latest ? "Latest" : "Top", cursor: cursor)
        case .searchMedia(let query):
            try await search(query, product: "Media", cursor: cursor)
        case .thread(let tweetID):
            try await tweetDetail(id: tweetID, cursor: cursor)
        case .userLikes(let userID):
            try await likes(userID: userID, cursor: cursor)
        case .userMedia(let userID):
            try await userMedia(userID: userID, cursor: cursor)
        case .userPosts(let userID):
            try await userTweets(userID: userID, cursor: cursor)
        case .userReplies(let userID):
            try await userReplies(userID: userID, cursor: cursor)
        }
    }
}

extension TwitterWebSession {
    /// The web client's user timelines. `Retweeters` and `Favoriters` ask for promoted content as x.com does (the
    /// parser drops it); `Favoriters` only lists anyone for the viewer's own posts since likes went private.
    func users(_ source: UserListSource, cursor: String?) async throws -> UserPage {
        let operation: String
        var variables: [String: JSONValue] = ["count": 20]
        switch source {
        case .followers(let userID), .following(let userID):
            operation = if case .followers = source { "Followers" } else { "Following" }
            variables["userId"] = .string(userID)
            variables["includePromotedContent"] = false
            variables["withGrokTranslatedBio"] = false
        case .likers(let tweetID), .reposters(let tweetID):
            operation = if case .likers = source { "Favoriters" } else { "Retweeters" }
            variables["tweetId"] = .string(tweetID)
            variables["enableRanking"] = false
            variables["includePromotedContent"] = true
        case .searchPeople(let query):
            // The web client's People tab: a search whose timeline holds accounts.
            operation = "SearchTimeline"
            variables["rawQuery"] = .string(query)
            variables["querySource"] = "typed_query"
            variables["product"] = "People"
            variables["withGrokTranslatedBio"] = false
        }
        if let cursor { variables["cursor"] = .string(cursor) }
        return TimelineParser.userPage(from: try await graphQL(operation, variables: variables))
    }
}
