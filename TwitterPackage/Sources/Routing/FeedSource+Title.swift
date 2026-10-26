import Models

extension FeedSource {
    package var title: String {
        switch self {
        case .bookmarks: "Bookmarks"
        case .home(let following): following ? "Following" : "For You"
        case .list(_, let name): name
        case .notifications(let filter): filter.rawValue
        case .search(_, let latest): latest ? "Latest" : "Top"
        case .searchMedia: "Media"
        case .thread: "Tweet"
        case .userLikes: "Likes"
        case .userMedia: "Media"
        case .userPosts: "Tweets"
        case .userReplies: "Replies"
        }
    }
}
