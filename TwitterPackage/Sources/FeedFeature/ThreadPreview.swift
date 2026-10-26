import ComposableArchitecture
import Models
import SwiftUI
import TweetEngagement
import TwitterUI

/// A long-pressed post's context menu preview: the thread it opens to, as modern Twitter peeks at it, live and loading
/// its replies with the post pinned at the top. Until the feed has presented the thread (its first frame) it's the
/// post alone in its focused layout, which is also what the thread starts from.
///
/// SwiftUI gives a preview no commit action, so tapping it only dismisses the menu; the thread opens from a tap on
/// the post itself.
struct ThreadPreview: View {
    let tweet: Tweet
    let store: StoreOf<FeedFeature>

    /// About a column's width, and tall enough to show the start of the replies.
    private static let size = CGSize(width: 400, height: 560)

    var body: some View {
        Group {
            if let thread = store.scope(state: \.preview, action: \.preview.presented),
                thread.source == .thread(tweetID: tweet.id)
            {
                ThreadView(store: thread)
            } else {
                ScrollView {
                    TweetRow(
                        item: FeedTweet(tweet: tweet),
                        engagement: store.engagements.engagement(for: tweet),
                        quotedEngagement: tweet.quoted.first.map { store.engagements.engagement(for: $0) },
                        store: store,
                        isFocused: true
                    )
                }
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(.background)
        .onAppear { store.send(.previewShown(tweet)) }
        .onDisappear { store.send(.previewHidden(tweetID: tweet.id)) }
    }
}
