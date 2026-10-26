package enum FeedSource: Hashable, Sendable {
    case bookmarks
    case home(following: Bool)
    /// A List's timeline, newest first.
    case list(id: String, name: String)
    case notifications(NotificationFilter)
    case search(query: String, latest: Bool)
    /// A search's photos and videos.
    case searchMedia(query: String)
    case thread(tweetID: String)
    case userLikes(userID: String)
    case userMedia(userID: String)
    case userPosts(userID: String)
    case userReplies(userID: String)
}

/// Which notifications a Notifications tab shows, as Twitter's All, Verified and Mentions.
package enum NotificationFilter: String, Hashable, Sendable {
    case all = "All"
    case verified = "Verified"
    case mentions = "Mentions"
}
