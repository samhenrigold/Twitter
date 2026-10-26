package enum FeedItem: Identifiable, Hashable, Codable, Sendable {
    case tweet(FeedTweet)
    case notification(TwitterNotification)
    case tombstone(Tombstone)
    case showMore(ShowMoreCursor)

    /// Arrived in Notifications since they were last read. Only posts and notifications can be.
    package var isUnread: Bool {
        get {
            switch self {
            case .tweet(let item): item.isUnread
            case .notification(let item): item.isUnread
            case .tombstone, .showMore: false
            }
        }
        set {
            switch self {
            case .notification(var notification):
                notification.isUnread = newValue
                self = .notification(notification)
            case .tweet(var tweet):
                tweet.isUnread = newValue
                self = .tweet(tweet)
            case .tombstone, .showMore:
                break
            }
        }
    }

    package var id: String {
        switch self {
        case .tweet(let item): "t-\(item.id)"
        case .notification(let item): "n-\(item.id)"
        case .tombstone(let item): "x-\(item.id)"
        case .showMore(let item): "s-\(item.id)"
        }
    }
}
