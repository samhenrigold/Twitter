import ComposableArchitecture
import FeedFeature
import Routing
import SwiftUI
import TwitterUI
import UserListFeature

package struct SearchView: View {
    @Bindable var store: StoreOf<SearchFeature>

    package init(store: StoreOf<SearchFeature>) {
        self.store = store
    }

    package var body: some View {
        Group {
            if let resultsStore = store.scope(state: \.results, action: \.results.presented) {
                SearchResultsView(store: resultsStore)
            } else {
                ContentUnavailableView(
                    "Search Twitter",
                    twitterIcon: .searchStroke,
                    description: Text("Find Tweets, people, and #topics.")
                )
            }
        }
        .navigationTitle("Explore")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $store.query, prompt: "Search")
        .onSubmit(of: .search) { store.send(.searchSubmitted) }
    }
}

/// The tab on screen, with Twitter's Top, Latest, People and Media tabs over it.
private struct SearchResultsView: View {
    @Bindable var store: StoreOf<SearchResults>

    var body: some View {
        Group {
            if let source = store.tab.source(for: store.query),
                let feedStore = store.scope(state: \.feeds[id: source], action: \.feeds[id: source])
            {
                FeedView(store: feedStore)
                    .id(source)
            } else {
                UserListView(store: store.scope(state: \.people, action: \.people))
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Results", selection: $store.tab.animation(.snappy)) {
                    ForEach(SearchResults.Tab.allCases, id: \.self) { tab in
                        Text(tab.title)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
            }
        }
    }
}
