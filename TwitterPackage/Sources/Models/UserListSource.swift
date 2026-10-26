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
