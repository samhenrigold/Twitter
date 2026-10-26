import Foundation

extension UserPage {
    package static let mockPageSize = 12

    /// `User.mockCrowd`, a page at a time, with Point-Free first so a list always starts with an account the viewer
    /// follows. Lists of who liked or reposted a post are shorter than lists of followers.
    package static func mock(_ source: UserListSource, cursor: String?) -> UserPage {
        var everyone = [User.mockFriend, .mockBusiness, .mockGovernment] + User.mockCrowd
        switch source {
        case .followers, .following: break
        case .likers, .reposters: everyone = Array(everyone.prefix(8))
        case .searchPeople(let query):
            // Whoever's name or handle has the query in it, as a people search finds them.
            everyone = everyone.filter {
                $0.name.localizedCaseInsensitiveContains(query) || $0.screenName.localizedCaseInsensitiveContains(query)
            }
        }
        let start = cursor.flatMap(Int.init) ?? 0
        let end = min(start + mockPageSize, everyone.count)
        guard start < end else { return UserPage(users: [], bottomCursor: nil) }
        return UserPage(users: Array(everyone[start..<end]), bottomCursor: end < everyone.count ? "\(end)" : nil)
    }
}
