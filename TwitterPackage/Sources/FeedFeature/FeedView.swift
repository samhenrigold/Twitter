import ComposableArchitecture
import Models
import SwiftUI
import TwitterUI

package struct FeedView<Header: View>: View {
    let store: StoreOf<FeedFeature>
    let header: Header

    package init(store: StoreOf<FeedFeature>, @ContentBuilder header: () -> Header) {
        self.store = store
        self.header = header()
    }

    /// Bound by item, so posts arriving above never move what's on screen.
    @State private var position = ScrollPosition(idType: FeedItem.ID.self)

    package var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                header

                if case .userMedia = store.source {
                    FeedMediaGrid(store: store)
                } else {
                    FeedRows(store: store)
                }

                FeedFooter(store: store)
            }
            .scrollTargetLayout()
            .readableContentWidth()
        }
        .scrollPosition($position, anchor: .top)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y <= -geometry.contentInsets.top + 8
        } action: { _, isAtTop in
            store.send(.isAtTopChanged(isAtTop))
        }
        .onScrollPhaseChange { _, phase in
            guard phase == .idle, let id = position.viewID(type: FeedItem.ID.self) else { return }
            store.send(.scrollStopped(topItemID: id))
        }
        .onChange(of: store.scrollToTopRequests) {
            // Like the status bar's scroll to top: straight there, no bounce.
            withAnimation(.smooth) { position.scrollTo(edge: .top) }
        }
        .onChange(of: store.restoringTopItemID, initial: true) {
            guard let topItemID = store.restoringTopItemID else { return }
            position.scrollTo(id: topItemID, anchor: .top)
            store.send(.topItemRestored)
        }
        // Just under the column's bar (the overlay keeps to the safe area the bar insets), pointing up at where the
        // new posts are.
        .overlay(alignment: .top) {
            ZStack {
                if store.newPostCount > 0 {
                    NewPostsButton(count: store.newPostCount) {
                        // Like the status bar's scroll to top: straight there, no bounce.
                        withAnimation(.smooth) { position.scrollTo(edge: .top) }
                        store.send(.newPostsButtonTapped)
                    }
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: store.newPostCount > 0)
        }
        .feedInteractions(store: store)
    }
}

/// Newer posts waiting above where the reader is: said quietly, never by moving them.
private struct NewPostsButton: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(count == 1 ? "1 new Tweet" : "\(count) new Tweets", twitterIcon: .arrowUp)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 6)
        }
        .buttonStyle(.borderedProminent)
        .sensoryFeedback(.increase, trigger: count)
    }
}

extension FeedView where Header == EmptyView {
    package init(store: StoreOf<FeedFeature>) {
        self.store = store
        header = EmptyView()
    }
}
