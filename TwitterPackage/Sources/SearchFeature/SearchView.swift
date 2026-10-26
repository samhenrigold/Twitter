import ComposableArchitecture
import Models
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
                SearchResultsView(store: resultsStore)
            } else if !store.trends.isEmpty || !store.recentSearches.isEmpty {
                TrendsList(
                    recentSearches: store.recentSearches,
                    trends: store.trends,
                    searchAgain: { store.send(.recentSearchTapped($0)) },
                    clearRecentSearches: { store.send(.clearRecentSearchesButtonTapped, animation: .snappy) },
                    select: { store.send(.trendTapped($0)) }
                )
            } else if !store.hasLoadedTrends {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "Search Twitter",
                    twitterIcon: .searchStroke,
                    description: Text("Find Tweets, people, and #topics.")
                )
            }
        }
        .task { store.send(.task) }
        .navigationTitle("Explore")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $store.query, prompt: "Search")
        .onSubmit(of: .search) { store.send(.searchSubmitted) }
    }
}

/// Explore before a search: recent searches to run again, then trends, each one's context over its name and how much
/// it's being talked about.
private struct TrendsList: View {
    let recentSearches: [String]
    let trends: [Trend]
    let searchAgain: (String) -> Void
    let clearRecentSearches: () -> Void
    let select: (Trend) -> Void

    var body: some View {
        List {
            if !recentSearches.isEmpty {
                HStack {
                    Text("Recent")
                        .font(.title3.weight(.heavy))

                    Spacer()

                    Button("Clear", action: clearRecentSearches)
                        .font(.subheadline)
                        .buttonStyle(.borderless)
                }
                .listRowSeparator(.hidden)

                ForEach(recentSearches, id: \.self) { query in
                    Button {
                        searchAgain(query)
                    } label: {
                        Label(query, twitterIcon: .searchStroke)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !trends.isEmpty {
                Text("Trends for you")
                    .font(.title3.weight(.heavy))
                    .listRowSeparator(.hidden)
            }

            Section {
                ForEach(trends) { trend in
                    Button {
                        select(trend)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            if let context = trend.context {
                                Text(context)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }

                            Text(trend.name)
                                .font(.body.weight(.bold))

                            if let volume = trend.volume {
                                Text(volume)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.plain)
    }
}
