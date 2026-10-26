import Models

extension UserListSource {
    /// The list's title: "Followers" and "Following" as on a profile, "Retweets" and "Likes" as on a Tweet.
    package var title: String {
        switch self {
        case .followers: "Followers"
        case .following: "Following"
        case .likers: "Likes"
        case .reposters: "Retweets"
        case .searchPeople: "People"
        }
    }
}
