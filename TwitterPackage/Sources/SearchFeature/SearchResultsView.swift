import ComposableArchitecture
import FeedFeature
import SwiftUI
import UserListFeature

/// The tab on screen, with Twitter's Top, Latest, People and Media tabs over it.
struct SearchResultsView: View {
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
