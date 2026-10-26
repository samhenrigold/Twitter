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

@Reducer
package struct TabStack {
    @ObservableState
    package struct State: Equatable {
        /// Whether the display is wide enough to lay what's opened out as columns. Without columns a web page opens in
        /// Safari's view, as on iPhone, rather than as a screen on the stack.
        var canShowColumns = false
        package var path = StackState<TabStackPath.State>()
        var root: TabRoot.State
        /// A web page in Safari's view over everything, on a single stack.
        var safari: SafariPage?
        /// Asking for what a column already shows shakes it, a gentle "already here".
        var shake = ColumnShake()
    }

    /// The column that last refused to open a duplicate (`nil` is the root), and a count that changes on every shake.
    package struct ColumnShake: Equatable {
        package var column: StackElementID?
        package var count = 0
    }

    /// A page shown in Safari's view.
    package struct SafariPage: Equatable, Identifiable {
        package let url: URL
        package var id: URL { url }
    }

    package enum Action {
        case columnAvailabilityChanged(Bool)
        case composeButtonTapped
        case delegate(ContentDelegate)
        case path(StackActionOf<TabStackPath>)
        case root(TabRoot.Action)
        case safariDismissed
        /// The tab's button tapped while it's showing: back to the root, or at the root, its timeline to the top.
        case tabReselected
    }

    package init() {}

    package var body: some Reducer<State, Action> {
        Scope(state: \.root, action: \.root) {
            TabRoot.body
        }
        Reduce { state, action in
            switch action {
            case .columnAvailabilityChanged(let canShowColumns):
                state.canShowColumns = canShowColumns
                return .none

            case .composeButtonTapped:
                return .send(.delegate(.compose(Draft())))

            case .delegate:
                return .none

            case .path(.element(let id, let action)):
                guard let delegate = action.contentDelegate else { return .none }
                return open(delegate, from: id, state: &state)

            case .path:
                return .none

            case .root(let action):
                guard let delegate = action.contentDelegate else { return .none }
                return open(delegate, from: nil, state: &state)

            case .safariDismissed:
                state.safari = nil
                return .none

            case .tabReselected:
                // Back to the root; already there, a timeline goes back to its top and refreshes.
                guard state.path.isEmpty else {
                    state.path.removeAll()
                    return .none
                }
                guard case .feeds = state.root else { return .none }
                return .send(.root(.feeds(.reselected)))
            }
        }
        .forEach(\.path, action: \.path)
    }

    /// Like Twitter for iPad's column stack: opening something from a column (`nil` is the root) replaces every column
    /// after it, and on one stack, where only the top is on screen, that's an ordinary push. Never a duplicate: if the
    /// next column already shows it, that column comes to the front; if the asking column shows it, it shakes. A web
    /// page is a panel among the columns, but on one stack it's Safari's view, as Twitter for iPhone did.
    private func open(_ delegate: ContentDelegate, from id: StackElementID?, state: inout State) -> Effect<Action> {
        guard case .open(let route) = delegate else { return .send(.delegate(delegate)) }
        let sourceIndex = id.flatMap { state.path.ids.firstIndex(of: $0) }
        let sourceShowsRoute = sourceIndex.map { state.path[$0].shows(route) } ?? state.root.shows(route)
        if sourceShowsRoute {
            state.shake = ColumnShake(column: id, count: state.shake.count + 1)
            return .none
        }
        if case .web(let url) = route, !state.canShowColumns {
            state.safari = SafariPage(url: url)
            return .none
        }
        let nextIndex = sourceIndex.map { $0 + 1 } ?? 0
        if nextIndex < state.path.count, state.path[nextIndex].shows(route) {
            state.path.removeLast(state.path.count - nextIndex - 1)
            return .none
        }
        state.path.removeLast(state.path.count - nextIndex)
        state.path.append(route.pathState)
        return .none
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

extension ProfileFeature.State {
    fileprivate func shows(screenName other: String) -> Bool {
        screenName.caseInsensitiveCompare(other) == .orderedSame
    }
}

extension Route {
    package var pathState: TabStackPath.State {
        switch self {
        case .list(let list):
            .list(FeedFeature.State(source: .list(id: list.id, name: list.name)))
        case .lists(let userID):
            .lists(ListsFeature.State(userID: userID))
        case .profile(let user):
            .profile(ProfileFeature.State(user: user))
        case .profileHandle(let screenName):
            .profile(ProfileFeature.State(screenName: screenName))
        case .quotes(let tweetID):
            .quotes(FeedFeature.State(source: .quotes(of: tweetID)))
        case .search(let query):
            .search(SearchFeature.State(submitting: query))
        case .thread(let tweet):
            .thread(
                FeedFeature.State(
                    source: .thread(tweetID: tweet.id),
                    items: [.tweet(FeedTweet(tweet: tweet))]
                )
            )
        case .threadID(let id):
            .thread(FeedFeature.State(source: .thread(tweetID: id)))
        case .userList(let source):
            .userList(UserListFeature.State(source: source))
        case .web(let url):
            .web(WebFeature.State(url: url))
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

extension TabStack.State {
    package static var bookmarks: Self {
        Self(root: .feeds(FeedsFeature.State(sources: [.bookmarks])))
    }

    package static var explore: Self {
        Self(root: .search(SearchFeature.State()))
    }

    package static var home: Self {
        Self(root: .feeds(FeedsFeature.State(sources: [.home(following: false), .home(following: true)])))
    }

    package static var notifications: Self {
        Self(
            root: .feeds(
                FeedsFeature.State(sources: [.notifications(mentionsOnly: false), .notifications(mentionsOnly: true)])
            )
        )
    }

    /// A standalone window rooted at a route, opened from a post's or profile's "Open in New Window".
    package static func window(_ route: WindowRoute) -> Self {
        let root: TabRoot.State =
            switch route.route.pathState {
            case .list(let list): .list(list)
            case .lists(let lists): .lists(lists)
            case .profile(let profile): .profile(profile)
            case .quotes(let quotes): .quotes(quotes)
            case .search(let search): .search(search)
            case .thread(let thread): .thread(thread)
            case .userList(let list): .userList(list)
            case .web(let web): .web(web)
            }
        return Self(root: root)
    }

    package static func profile(viewer: User) -> Self {
        Self(root: .profile(ProfileFeature.State(user: viewer, isViewer: true)))
    }
}
