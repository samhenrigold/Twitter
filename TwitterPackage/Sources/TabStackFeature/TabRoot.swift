import ComposableArchitecture
import FeedFeature
import ListsFeature
import ProfileFeature
import Routing
import SearchFeature
import UserListFeature
import WebFeature

@Reducer
package enum TabRoot {
    case feeds(FeedsFeature)
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

extension TabRoot.State: Equatable {}

extension TabRoot.State {
    func shows(_ route: Route) -> Bool {
        switch self {
        case .profile(let profile): TabStackPath.State.profile(profile).shows(route)
        case .quotes(let feed): TabStackPath.State.quotes(feed).shows(route)
        case .thread(let feed): TabStackPath.State.thread(feed).shows(route)
        case .userList(let list): TabStackPath.State.userList(list).shows(route)
        case .list(let feed): TabStackPath.State.list(feed).shows(route)
        case .lists(let lists): TabStackPath.State.lists(lists).shows(route)
        case .web(let web): TabStackPath.State.web(web).shows(route)
        case .feeds, .search: false
        }
    }
}

extension TabRoot.Action {
    package var contentDelegate: ContentDelegate? {
        switch self {
        case .feeds(.delegate(let delegate)), .list(.delegate(let delegate)), .lists(.delegate(let delegate)),
            .profile(.delegate(let delegate)), .quotes(.delegate(let delegate)),
            .search(.delegate(let delegate)), .thread(.delegate(let delegate)), .userList(.delegate(let delegate)),
            .web(.delegate(let delegate)):
            delegate
        default:
            nil
        }
    }
}
