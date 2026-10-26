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
    func resubmittingSameQueryKeepsResults() async {
        let store = TestStore(initialState: SearchFeature.State(submitting: "swift")) {
            SearchFeature()
        }

        await store.send(.searchSubmitted)
    }
}
