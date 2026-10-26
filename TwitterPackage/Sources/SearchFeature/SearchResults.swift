import ComposableArchitecture
import FeedFeature
import Models
import Routing
import UserListFeature

/// A search's results, as Twitter's tabs: Top and Latest Tweets, the People it matches, and its photos and videos.
@Reducer
package struct SearchResults {
    @ObservableState
    package struct State: Equatable {
        var feeds: IdentifiedArrayOf<FeedFeature.State>
        var people: UserListFeature.State
        let query: String
        var tab = Tab.top

        init(query: String) {
            self.query = query
            feeds = [
                FeedFeature.State(source: Tab.top.source(for: query)!),
                FeedFeature.State(source: Tab.latest.source(for: query)!),
                FeedFeature.State(source: Tab.media.source(for: query)!)
            ]
            people = UserListFeature.State(source: .searchPeople(query: query))
        }
    }

    package enum Tab: CaseIterable, Hashable {
        case top
        case latest
        case people
        case media

        var title: String {
            switch self {
            case .top: "Top"
            case .latest: "Latest"
            case .people: "People"
            case .media: "Media"
            }
        }

        /// The timeline the tab shows (People shows accounts instead).
        func source(for query: String) -> FeedSource? {
            switch self {
            case .top: .search(query: query, latest: false)
            case .latest: .search(query: query, latest: true)
            case .people: nil
            case .media: .searchMedia(query: query)
            }
        }
    }

    package enum Action: BindableAction {
        case binding(BindingAction<State>)
        case delegate(ContentDelegate)
        case feeds(IdentifiedActionOf<FeedFeature>)
        case people(UserListFeature.Action)
    }

    package var body: some Reducer<State, Action> {
        BindingReducer()
        Scope(state: \.people, action: \.people) {
            UserListFeature()
        }
        Reduce { _, action in
            switch action {
            case .feeds(.element(_, .delegate(let delegate))), .people(.delegate(let delegate)):
                .send(.delegate(delegate))
            case .binding, .delegate, .feeds, .people:
                .none
            }
        }
        .forEach(\.feeds, action: \.feeds) {
            FeedFeature()
        }
    }
}
