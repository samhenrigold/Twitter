import ComposableArchitecture
import FeedFeature
import ListsFeature
import ProfileFeature
import Routing
import SearchFeature
import SwiftUI
import UserListFeature
import WebFeature

struct TabRootView: View {
    let store: StoreOf<TabStack>
    let title: LocalizedStringKey

    var body: some View {
        TabRootContentView(store: store.scope(state: \.root, action: \.root))
            .navigationTitle(title)
    }
}

private struct TabRootContentView: View {
    let store: StoreOf<TabRoot>

    var body: some View {
        switch store.case {
        case .feeds(let store):
            FeedsView(store: store)
                .navigationBarTitleDisplayMode(.inline)
        case .list(let store):
            FeedView(store: store)
                .navigationTitle(store.source.title)
                .navigationBarTitleDisplayMode(.inline)
        case .lists(let store):
            ListsView(store: store)
        case .profile(let store):
            ProfileView(store: store)
        case .quotes(let store):
            FeedView(store: store)
                .navigationTitle("Quote Tweets")
                .navigationBarTitleDisplayMode(.inline)
        case .search(let store):
            SearchView(store: store)
        case .thread(let store):
            ThreadView(store: store)
                .navigationBarTitleDisplayMode(.inline)
        case .userList(let store):
            UserListView(store: store)
        case .web(let store):
            WebPanelView(store: store)
        }
    }
}

struct TabStackPathView: View {
    let store: StoreOf<TabStackPath>

    var body: some View {
        switch store.case {
        case .list(let store):
            FeedView(store: store)
                .navigationTitle(store.source.title)
                .navigationBarTitleDisplayMode(.inline)
        case .lists(let store):
            ListsView(store: store)
        case .profile(let store):
            ProfileView(store: store)
        case .quotes(let store):
            FeedView(store: store)
                .navigationTitle("Quote Tweets")
                .navigationBarTitleDisplayMode(.inline)
        case .search(let store):
            SearchView(store: store)
        case .thread(let store):
            ThreadView(store: store)
                .navigationTitle("Tweet")
                .navigationBarTitleDisplayMode(.inline)
        case .userList(let store):
            UserListView(store: store)
        case .web(let store):
            WebPanelView(store: store)
        }
    }
}
