import ComposableArchitecture
import FeedFeature
import Routing
import SwiftUI
import TwitterUI

package struct SearchView: View {
    @Bindable var store: StoreOf<SearchFeature>

    package init(store: StoreOf<SearchFeature>) {
        self.store = store
    }

    package var body: some View {
        Group {
            if let resultsStore = store.scope(state: \.results, action: \.results.presented) {
                FeedsView(store: resultsStore)
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
