import ComposableArchitecture
import Models
import Routing
import TwitterClient

@Reducer
package struct SearchFeature {
    @ObservableState
    package struct State: Equatable {
        var query = ""
        /// What was searched lately, newest first.
        @Shared(.recentSearches) var recentSearches
        @Presents var results: SearchResults.State?
        var submittedQuery: String?
        /// What's trending, shown before anything's searched.
        var trends: [Trend] = []
        var trendsError: String?
        var hasLoadedTrends = false

        package init() {}

        package init(submitting query: String) {
            self.query = query
            submittedQuery = query
            results = SearchResults.State(query: query)
        }
    }

    package enum Action: BindableAction {
        case binding(BindingAction<State>)
        case clearRecentSearchesButtonTapped
        case delegate(ContentDelegate)
        case recentSearchTapped(String)
        case results(PresentationAction<SearchResults.Action>)
        case resultsCleared(query: String)
        case searchSubmitted
        case task
        case trendTapped(Trend)
        case trendsResponse(Result<[Trend], any Error>)
    }

    @Dependency(TwitterClient.self) var client

    package init() {}

    package var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding(\.query):
                if state.query.isEmpty {
                    state.results = nil
                    state.submittedQuery = nil
                }
                return .none

            case .binding, .delegate:
                return .none

            case .clearRecentSearchesButtonTapped:
                state.$recentSearches.withLock { $0 = [] }
                return .none

            case .recentSearchTapped(let query):
                state.query = query
                return .send(.searchSubmitted)

            case .results(.presented(.delegate(let delegate))):
                return .send(.delegate(delegate))

            case .results:
                return .none

            case .resultsCleared(let query):
                state.results = SearchResults.State(query: query)
                return .none

            case .searchSubmitted:
                let query = state.query.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !query.isEmpty, query != state.submittedQuery else { return .none }
                state.submittedQuery = query
                state.$recentSearches.withLock {
                    $0.removeAll { $0.caseInsensitiveCompare(query) == .orderedSame }
                    $0.insert(query, at: 0)
                    $0 = Array($0.prefix(State.recentSearchLimit))
                }
                // Gone first, so the old results' effects are cancelled before the new ones start.
                state.results = nil
                return .send(.resultsCleared(query: query))

            case .task:
                // Only Explore shows them; a search opened from elsewhere starts with its results.
                guard !state.hasLoadedTrends, state.results == nil else { return .none }
                return .run { send in
                    await send(.trendsResponse(Result { try await client.trends() }))
                }

            case .trendTapped(let trend):
                state.query = trend.query
                return .send(.searchSubmitted)

            case .trendsResponse(.success(let trends)):
                state.hasLoadedTrends = true
                state.trends = trends
                state.trendsError = nil
                return .none

            case .trendsResponse(.failure(let error)):
                state.hasLoadedTrends = true
                state.trendsError = error.localizedDescription
                return .none
            }
        }
        .ifLet(\.$results, action: \.results) {
            SearchResults()
        }
    }
}

extension SearchFeature.State {
    static let recentSearchLimit = 10
}

extension SharedKey where Self == FileStorageKey<[String]>.Default {
    /// Searches made lately, kept on disk, newest first.
    static var recentSearches: Self {
        Self[.fileStorage(.applicationSupportDirectory.appending(component: "recent-searches.json")), default: []]
    }
}
