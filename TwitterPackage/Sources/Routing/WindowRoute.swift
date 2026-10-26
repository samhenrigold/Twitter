import Foundation
import Models

/// The value a standalone window is opened with and restored from.
package enum WindowRoute: Codable, Hashable, Sendable {
    case list(TwitterList)
    case lists(userID: String)
    case profile(screenName: String)
    case quotes(tweetID: String)
    case search(String)
    case thread(tweetID: String)
    case userList(UserListSource)
    case web(URL)

    package var route: Route {
        switch self {
        case .list(let list): .list(list)
        case .lists(let userID): .lists(userID: userID)
        case .profile(let screenName): .profileHandle(screenName)
        case .quotes(let tweetID): .quotes(tweetID: tweetID)
        case .search(let query): .search(query)
        case .thread(let tweetID): .threadID(tweetID)
        case .userList(let source): .userList(source)
        case .web(let url): .web(url)
        }
    }
}
