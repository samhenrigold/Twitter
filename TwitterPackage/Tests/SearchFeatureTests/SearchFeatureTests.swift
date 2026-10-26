import ComposableArchitecture
import Testing

@testable import FeedFeature
@testable import Models
@testable import SearchFeature
@testable import TwitterClient

@MainActor
struct SearchFeatureTests {
    @Test
    func newQueryCancelsPreviousResultsEffects() async {
        let store = TestStore(initialState: SearchFeature.State(submitting: "swift")) {
            SearchFeature()
        } withDependencies: {
            $0[TwitterClient.self].feed = { _, _ in
                try await Task.sleep(for: .seconds(60))
                return FeedPage(items: [], bottomCursor: nil, topCursor: nil)
            }
        }
        let topSwift = FeedSource.search(query: "swift", latest: false)
        await store.send(.results(.presented(.feeds(.element(id: topSwift, action: .task))))) {
            $0.results?.feeds[id: topSwift]?.isLoading = true
        }
        await store.send(.binding(.set(\.query, "tca"))) {
            $0.query = "tca"
        }
        await store.send(.searchSubmitted) {
            $0.submittedQuery = "tca"
            $0.$recentSearches.withLock { $0 = ["tca"] }
            $0.results = nil
        }
        await store.receive(\.resultsCleared) {
            $0.results = SearchResults.State(query: "tca")
        }
    }

    @Test
    func resultsOfferTopLatestPeopleAndMedia() {
        let results = SearchResults.State(query: "swift")
        #expect(
            results.feeds.ids.elements == [
                .search(query: "swift", latest: false), .search(query: "swift", latest: true),
                .searchMedia(query: "swift")
            ]
        )
        #expect(results.people.source == .searchPeople(query: "swift"))
        #expect(SearchResults.Tab.allCases.compactMap { $0.source(for: "swift") } == results.feeds.ids.elements)
    }

    @Test
    func exploreLoadsTrendsAndATrendSearchesItsQuery() async {
        let trend = Trend(name: "#WWDC", context: "Trending in Technology")
        let store = TestStore(initialState: SearchFeature.State()) {
            SearchFeature()
        } withDependencies: {
            $0[TwitterClient.self].trends = { [trend] }
        }

        await store.send(.task)
        await store.receive(\.trendsResponse) {
            $0.hasLoadedTrends = true
            $0.trends = [trend]
        }
        await store.send(.trendTapped(trend)) {
            $0.query = "#WWDC"
            // Shared, so it reads as changed from the tap that leads to it.
            $0.$recentSearches.withLock { $0 = ["#WWDC"] }
        }
        await store.receive(\.searchSubmitted) {
            $0.submittedQuery = "#WWDC"
        }
        await store.receive(\.resultsCleared) {
            $0.results = SearchResults.State(query: "#WWDC")
        }
    }

    @Test
    func searchesAreRememberedNewestFirstWithoutRepeats() async {
        let store = TestStore(initialState: SearchFeature.State()) {
            SearchFeature()
        }
        store.exhaustivity = .off

        for query in ["swift", "tca", "Swift"] {
            await store.send(.binding(.set(\.query, query)))
            await store.send(.searchSubmitted)
        }
        #expect(store.state.recentSearches == ["Swift", "tca"])
        await store.send(.clearRecentSearchesButtonTapped)
        #expect(store.state.recentSearches.isEmpty)
    }

    @Test
    func resubmittingSameQueryKeepsResults() async {
        let store = TestStore(initialState: SearchFeature.State(submitting: "swift")) {
            SearchFeature()
        }

        await store.send(.searchSubmitted)
    }
}
