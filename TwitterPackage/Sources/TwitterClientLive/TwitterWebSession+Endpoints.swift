import Foundation
import Models

extension TwitterWebSession {
    func viewer() async throws -> User {
        _ = try await currentCatalog()
        let settings = try await rest("/i/api/1.1/account/settings.json") as? [String: Any]
        guard let screenName = settings?["screen_name"] as? String else { throw TwitterError.unauthorized }
        return try await user(screenName: screenName)
    }

    func user(screenName: String) async throws -> User {
        let json = try await graphQL(
            "UserByScreenName",
            variables: [
                "screen_name": .string(screenName), "withGrokTranslatedBio": false
            ])
        guard
            let result = (((json as? [String: Any])?["data"] as? [String: Any])?["user"] as? [String: Any])?["result"]
                as? [String: Any],
            let user = TimelineParser.user(from: result)
        else { throw TwitterError.api("Couldn't find @\(screenName).") }
        return user
    }

    func homeTimeline(following: Bool, cursor: String?) async throws -> FeedPage {
        var variables: [String: JSONValue] = [
            "count": 20, "includePromotedContent": false, "latestControlAvailable": true,
            "requestContext": cursor == nil ? "launch" : "ptr", "withCommunity": true
        ]
        if let cursor { variables["cursor"] = .string(cursor) }
        if !following { variables["seenTweetIds"] = [] }
        return try await graphQLPage(
            following ? "HomeLatestTimeline" : "HomeTimeline", variables: variables, usePOST: true)
    }

    func tweetDetail(id: String, cursor: String?) async throws -> FeedPage {
        var variables: [String: JSONValue] = [
            "focalTweetId": .string(id), "with_rux_injections": false, "rankingMode": "Relevance",
            "includePromotedContent": false, "withCommunity": true, "withQuickPromoteEligibilityTweetFields": true,
            "withBirdwatchNotes": true, "withVoice": true
        ]
        if let cursor {
            variables["cursor"] = .string(cursor)
            variables["referrer"] = "tweet"
        }
        return try await graphQLPage("TweetDetail", variables: variables)
    }

    func userTweets(userID: String, cursor: String?) async throws -> FeedPage {
        var variables: [String: JSONValue] = [
            "userId": .string(userID), "count": 20, "includePromotedContent": false,
            "withQuickPromoteEligibilityTweetFields": true, "withVoice": true
        ]
        if let cursor { variables["cursor"] = .string(cursor) }
        return try await graphQLPage("UserTweets", variables: variables)
    }

    func userReplies(userID: String, cursor: String?) async throws -> FeedPage {
        var variables: [String: JSONValue] = [
            "userId": .string(userID), "count": 20, "includePromotedContent": false, "withCommunity": true,
            "withVoice": true
        ]
        if let cursor { variables["cursor"] = .string(cursor) }
        return try await graphQLPage("UserTweetsAndReplies", variables: variables)
    }

    func userMedia(userID: String, cursor: String?) async throws -> FeedPage {
        var variables: [String: JSONValue] = [
            "userId": .string(userID), "count": 20, "includePromotedContent": false,
            "withClientEventToken": false, "withBirdwatchNotes": false, "withVoice": true
        ]
        if let cursor { variables["cursor"] = .string(cursor) }
        return try await graphQLPage("UserMedia", variables: variables)
    }

    func likes(userID: String, cursor: String?) async throws -> FeedPage {
        var variables: [String: JSONValue] = [
            "userId": .string(userID), "count": 20, "includePromotedContent": false,
            "withClientEventToken": false, "withBirdwatchNotes": false, "withVoice": true
        ]
        if let cursor { variables["cursor"] = .string(cursor) }
        return try await graphQLPage("Likes", variables: variables)
    }

    func deleteTweet(id: String) async throws {
        _ = try await graphQL("DeleteTweet", variables: ["tweet_id": .string(id), "dark_request": false])
    }

    func setPinned(_ pinned: Bool, tweetID: String) async throws {
        _ = try await graphQL(pinned ? "PinTweet" : "UnpinTweet", variables: ["tweet_id": .string(tweetID)])
    }

    func setFollowing(_ follow: Bool, userID: String) async throws {
        _ = try await restPost(
            follow ? "/i/api/1.1/friendships/create.json" : "/i/api/1.1/friendships/destroy.json",
            form: ["user_id": userID])
    }

    func setMuted(_ muted: Bool, userID: String) async throws {
        _ = try await restPost(
            muted ? "/i/api/1.1/mutes/users/create.json" : "/i/api/1.1/mutes/users/destroy.json",
            form: ["user_id": userID])
    }

    func setBlocked(_ blocked: Bool, userID: String) async throws {
        _ = try await restPost(
            blocked ? "/i/api/1.1/blocks/create.json" : "/i/api/1.1/blocks/destroy.json", form: ["user_id": userID])
    }

    /// `product` is the web client's tab: Top, Latest or Media (People lists accounts; see `users(_:cursor:)`).
    func search(_ query: String, product: String, cursor: String?) async throws -> FeedPage {
        var variables: [String: JSONValue] = [
            "rawQuery": .string(query), "count": 20, "querySource": "typed_query", "product": .string(product),
            "withGrokTranslatedBio": false
        ]
        if let cursor { variables["cursor"] = .string(cursor) }
        return try await graphQLPage("SearchTimeline", variables: variables)
    }

    func listTimeline(id: String, cursor: String?) async throws -> FeedPage {
        var variables: [String: JSONValue] = ["listId": .string(id), "count": 20]
        if let cursor { variables["cursor"] = .string(cursor) }
        return try await graphQLPage("ListLatestTweetsTimeline", variables: variables)
    }

    /// The Lists someone made or follows, as their profile's Lists page shows them.
    func lists(userID: String, cursor: String?) async throws -> ListPage {
        var variables: [String: JSONValue] = ["userId": .string(userID), "count": 100]
        if let cursor { variables["cursor"] = .string(cursor) }
        return TimelineParser.listPage(from: try await graphQL("CombinedLists", variables: variables))
    }

    /// Accounts for completing a mention, as x.com's composer suggests them.
    func typeahead(_ query: String) async throws -> [User] {
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "include_ext_is_blue_verified", value: "1"),
            URLQueryItem(name: "q", value: "@" + query),
            URLQueryItem(name: "src", value: "compose"),
            URLQueryItem(name: "result_type", value: "users")
        ]
        return TimelineParser.typeaheadUsers(
            from: try await rest("/i/api/1.1/search/typeahead.json?" + (components.percentEncodedQuery ?? "")))
    }

    /// A poll vote, through the cards passthrough x.com's poll uses.
    func vote(tweetID: String, cardURI: String, cardName: String, choice: Int) async throws {
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "twitter:string:card_uri", value: cardURI),
            URLQueryItem(name: "twitter:long:original_tweet_id", value: tweetID),
            URLQueryItem(name: "twitter:string:response_card_name", value: cardName),
            URLQueryItem(name: "twitter:string:cards_platform", value: "Web-12"),
            URLQueryItem(name: "twitter:string:selected_choice", value: String(choice + 1))
        ]
        let url = URL(string: "https://caps.x.com/v2/capi/passthrough/1")!
        var request = apiRequest(
            url: url, method: "POST", body: Data((components.percentEncodedQuery ?? "").utf8),
            transactionPath: url.path(), generator: catalog?.transactionGenerator)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let (json, status) = try await perform(request)
        guard (200..<300).contains(status) else {
            throw TwitterError.http(status, Self.errorMessages(json).first ?? "")
        }
    }

    /// The unread notifications count the web client badges its Notifications tab with.
    func unreadNotificationCount() async throws -> Int {
        let json = try await rest("/i/api/2/badge_count/badge_count.json?supports_ntab_urt=1") as? [String: Any]
        return (json?["ntab_unread_count"] as? Int) ?? 0
    }

    /// Where Notifications were last read up to, as the web client reports it on opening them.
    func markNotificationsRead(cursor: String) async throws {
        _ = try await restPost("/i/api/2/notifications/all/last_seen_cursor.json", form: ["cursor": cursor])
    }

    /// What's trending, from the web client's Explore page.
    func trends() async throws -> [Trend] {
        TimelineParser.trends(from: try await graphQL("ExplorePage", variables: [:]))
    }

    func bookmarks(cursor: String?) async throws -> FeedPage {
        var variables: [String: JSONValue] = ["count": 20, "includePromotedContent": false]
        if let cursor { variables["cursor"] = .string(cursor) }
        return try await graphQLPage("Bookmarks", variables: variables)
    }

    func notifications(type: String = "All", cursor: String?) async throws -> FeedPage {
        var variables: [String: JSONValue] = ["timeline_type": .string(type), "count": 20]
        if let cursor { variables["cursor"] = .string(cursor) }
        return try await graphQLPage("NotificationsTimeline", variables: variables)
    }

    func setLiked(_ liked: Bool, tweetID: String) async throws {
        _ = try await graphQL(liked ? "FavoriteTweet" : "UnfavoriteTweet", variables: ["tweet_id": .string(tweetID)])
    }

    func setReposted(_ reposted: Bool, tweetID: String) async throws {
        if reposted {
            _ = try await graphQL("CreateRetweet", variables: ["tweet_id": .string(tweetID), "dark_request": false])
        } else {
            _ = try await graphQL(
                "DeleteRetweet", variables: ["source_tweet_id": .string(tweetID), "dark_request": false])
        }
    }

    func setBookmarked(_ bookmarked: Bool, tweetID: String) async throws {
        _ = try await graphQL(
            bookmarked ? "CreateBookmark" : "DeleteBookmark", variables: ["tweet_id": .string(tweetID)])
    }

    /// Creates a post and returns its ID (needed to chain thread replies).
    @discardableResult
    func post(text: String, replyTo: String?, mediaIDs: [String] = [], quoteURL: URL? = nil) async throws -> String {
        let entities: [JSONValue] = mediaIDs.map { ["media_id": .string($0), "tagged_users": []] }
        var variables: [String: JSONValue] = [
            "tweet_text": .string(text), "dark_request": false,
            "media": ["media_entities": .array(entities), "possibly_sensitive": false],
            "semantic_annotation_ids": [], "disallowed_reply_options": nil
        ]
        if let replyTo { variables["reply"] = ["in_reply_to_tweet_id": .string(replyTo), "exclude_reply_user_ids": []] }
        if let quoteURL { variables["attachment_url"] = .string(quoteURL.absoluteString) }
        let json = try await graphQL("CreateTweet", variables: variables)
        let result =
            ((((json as? [String: Any])?["data"] as? [String: Any])?["create_tweet"] as? [String: Any])?[
                "tweet_results"] as? [String: Any])?["result"] as? [String: Any]
        let unwrapped = result.flatMap(TimelineParser.unwrapTweet)
        guard
            let id = (unwrapped?["rest_id"] as? String)
                ?? ((unwrapped?["legacy"] as? [String: Any])?["id_str"] as? String)
        else {
            throw TwitterError.api("Twitter didn't confirm the Tweet.")
        }
        return id
    }
}
