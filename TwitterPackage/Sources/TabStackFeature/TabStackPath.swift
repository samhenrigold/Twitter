import ComposableArchitecture
import FeedFeature
import Foundation
import ListsFeature
import Models
import ProfileFeature
import Routing
import SearchFeature
import UserListFeature
import WebFeature

@Reducer
package enum TabStackPath {
    /// A List's timeline.
    case list(FeedFeature)
    case lists(ListsFeature)
    case profile(ProfileFeature)
    /// A post's quotes: a timeline of the posts quoting it.
    case quotes(FeedFeature)
    case search(SearchFeature)
    case thread(FeedFeature)
    case userList(UserListFeature)
    case web(WebFeature)
}

extension TabStackPath.State: Equatable {
    /// Twitter for iPad's web panels are wide: a page needs more room than a timeline.
    var isWide: Bool {
        if case .web = self { true } else { false }
    }
}

extension TabStackPath.State {
    /// Whether this column already shows what the route would open.
    func shows(_ route: Route) -> Bool {
        switch (self, route) {
        case (.thread(let feed), .thread(let tweet)): feed.source == .thread(tweetID: tweet.id)
        case (.thread(let feed), .threadID(let id)): feed.source == .thread(tweetID: id)
        case (.profile(let profile), .profile(let user)): profile.shows(screenName: user.screenName)
        case (.profile(let profile), .profileHandle(let screenName)): profile.shows(screenName: screenName)
        case (.quotes(let feed), .quotes(let tweetID)): feed.source == .quotes(of: tweetID)
        case (.userList(let list), .userList(let source)): list.source == source
        case (.list(let feed), .list(let list)): feed.source == .list(id: list.id, name: list.name)
        case (.lists(let lists), .lists(let userID)): lists.userID == userID
        case (.web(let web), .web(let url)): web.shows(url)
        default: false
        }
    }
}

extension ProfileFeature.State {
    fileprivate func shows(screenName other: String) -> Bool {
        screenName.caseInsensitiveCompare(other) == .orderedSame
    }
}

extension TabStackPath.Action {
    package var contentDelegate: ContentDelegate? {
        switch self {
        case .list(.delegate(let delegate)), .lists(.delegate(let delegate)), .profile(.delegate(let delegate)),
            .quotes(.delegate(let delegate)), .search(.delegate(let delegate)), .thread(.delegate(let delegate)),
            .userList(.delegate(let delegate)), .web(.delegate(let delegate)):
            delegate
        default:
            nil
        }
    }
}
