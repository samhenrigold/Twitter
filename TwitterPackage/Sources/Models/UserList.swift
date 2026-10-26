import Foundation

/// A list of accounts Twitter keeps about a profile or a post: who follows it, whom it follows, who reposted or liked
/// it. Identified by IDs rather than model snapshots, so a list can be opened in a window and restored from it.
package enum UserListSource: Hashable, Codable, Sendable {
    case followers(userID: String)
    case following(userID: String)
    /// Who liked a post. Twitter made likes private in 2024, so this only lists anyone for the viewer's own posts.
    case likers(tweetID: String)
    case reposters(tweetID: String)
    /// Accounts matching a search.
    case searchPeople(query: String)
}

/// One page of a user list, and the cursor for the next.
package struct UserPage: Sendable {
    package var users: [User]
    package var bottomCursor: String?

    package init(users: [User], bottomCursor: String?) {
        self.users = users
        self.bottomCursor = bottomCursor
    }
}

extension TimelineParser {
    /// A user timeline (`Followers`, `Following`, `Retweeters`, `Favoriters`): `TimelineUser` items and a bottom cursor.
    ///
    /// These timelines always end with a bottom cursor, even on their last page, where its value starts with `0|`;
    /// that one is dropped so paging stops there instead of asking for an empty page.
    package static func userPage(from root: Any) -> UserPage {
        var users: [User] = []
        var seen = Set<String>()
        var bottom: String?

        for instruction in findInstructions(in: root) ?? [] {
            let entries: [JSON] =
                switch instruction["type"] as? String {
                case "TimelineAddEntries": instruction["entries"] as? [JSON] ?? []
                case "TimelineReplaceEntry": (instruction["entry"] as? JSON).map { [$0] } ?? []
                default: []
                }
            for entry in entries {
                let entryID = entry["entryId"] as? String ?? ""
                guard !entryID.hasPrefix("promoted"), let content = entry["content"] as? JSON else { continue }
                if content["cursorType"] as? String == "Bottom" {
                    bottom = content["value"] as? String
                    continue
                }
                guard let itemContent = content["itemContent"] as? JSON,
                    itemContent["promotedMetadata"] == nil,
                    let user = user(fromResult: itemContent),
                    seen.insert(user.id).inserted
                else { continue }
                users.append(user)
            }
        }
        if let cursor = bottom, cursor.hasPrefix("0|") { bottom = nil }
        return UserPage(users: users, bottomCursor: bottom)
    }
}

extension FeedSource {
    package static let quotesQueryPrefix = "quoted_tweet_id:"

    /// A post's quotes, newest first. The web client finds them with a search for `quoted_tweet_id:`, so they page,
    /// refresh and cache like any search.
    package static func quotes(of tweetID: String) -> FeedSource {
        .search(query: quotesQueryPrefix + tweetID, latest: true)
    }
}
