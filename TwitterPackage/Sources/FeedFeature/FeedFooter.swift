import ComposableArchitecture
import SwiftUI
import TwitterUI

struct FeedFooter: View {
    let store: StoreOf<FeedFeature>

    var body: some View {
        Group {
            if let errorMessage = store.errorMessage {
                ContentUnavailableView {
                    Label("Couldn't load Tweets", twitterIcon: .warningStroke)
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try Again") { store.send(.retryButtonTapped) }
                        .buttonStyle(.bordered)
                }
            } else if store.isLoading {
                ProgressView()
                    .padding(.vertical, 32)
            } else if store.hasLoaded, store.items.isEmpty {
                ContentUnavailableView("Nothing here yet", twitterIcon: .twitter)
            } else if store.hasLoaded, store.bottomCursor == nil {
                EndOfTimeline()
            }
        }
        .frame(maxWidth: .infinity)
    }
}
