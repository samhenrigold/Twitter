import ComposableArchitecture
import FeedFeature
import Foundation
import Models
import ProfileFeature
import Routing
import SearchFeature

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
        /// The compose button held: its drafts, as Twitter's.
        case composeButtonLongPressed
        case delegate(ContentDelegate)
        case path(StackActionOf<TabStackPath>)
        case root(TabRoot.Action)
        case safariDismissed
        /// The tab's button tapped while it's showing: back to the root, or at the root, its timeline to the top.
        case tabReselected
        /// The tab was chosen: its timeline refreshes if it's gone stale, or Twitter has said there's something new.
        case tabSelected(hasNew: Bool)
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

            case .composeButtonLongPressed:
                return .send(.delegate(.drafts))

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

            case .tabSelected(let hasNew):
                guard case .feeds = state.root else { return .none }
                return .send(.root(.feeds(.tabSelected(hasNew: hasNew))))
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
                FeedsFeature.State(sources: [.notifications(.all), .notifications(.verified), .notifications(.mentions)]
                )
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
