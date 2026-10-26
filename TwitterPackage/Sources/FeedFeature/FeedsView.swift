import ComposableArchitecture
import Models
import Routing
import SwiftUI

package struct FeedsView<Header: View>: View {
    @Bindable var store: StoreOf<FeedsFeature>
    let header: Header

    package init(store: StoreOf<FeedsFeature>, @ContentBuilder header: () -> Header) {
        self.store = store
        self.header = header()
    }

    package var body: some View {
        if let feedStore = store.scope(state: \.feeds[id: store.selection], action: \.feeds[id: store.selection]) {
            FeedView(store: feedStore) {
                header
            }
            .id(store.selection)
            // Under a header (a profile's), in a bar beneath the title; at the top of a tab, in the navigation bar in
            // place of the title.
            .safeAreaBar(edge: .top) {
                if showsSwitcher, !isTopLevel {
                    FeedSwitcher(feeds: store.feeds.map(\.source), selection: $store.selection)
                        .padding(.horizontal, 16)
                        .padding(.top, 2)
                        .padding(.bottom, 10)
                }
            }
            .toolbar {
                if showsSwitcher, isTopLevel {
                    ToolbarItem(placement: .principal) {
                        FeedSwitcher(feeds: store.feeds.map(\.source), selection: $store.selection)
                            .frame(maxWidth: 280)
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
            }
        }
    }

    private var isTopLevel: Bool { Header.self == EmptyView.self }
    private var showsSwitcher: Bool { store.feeds.count > 1 }
}

/// Which of a screen's feeds is showing: For You and Following, or a profile's Posts, Replies and Media.
private struct FeedSwitcher: View {
    let feeds: [FeedSource]
    @Binding var selection: FeedSource

    var body: some View {
        Picker("Feed", selection: $selection.animation(.snappy)) {
            ForEach(feeds, id: \.self) { feed in
                Text(feed.title)
            }
        }
        .pickerStyle(.segmented)
        // Over the readable column on a wide display instead of stretching across it.
        .frame(maxWidth: 680)
    }
}

extension FeedsView where Header == EmptyView {
    package init(store: StoreOf<FeedsFeature>) {
        self.store = store
        header = EmptyView()
    }
}
