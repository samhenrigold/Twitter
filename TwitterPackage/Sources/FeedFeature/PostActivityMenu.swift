import ComposableArchitecture
import Models
import SwiftUI
import TwitterUI

/// A post's activity in its menu: who reposted it, the posts quoting it, and, for the viewer's own posts, who liked
/// it (Twitter made likes private in 2024, so nobody else's list shows anyone). Lists with nothing in them are left
/// out, and the whole submenu when every one is.
struct PostActivityMenu: View {
    let tweet: Tweet
    let isOwnPost: Bool
    let store: StoreOf<FeedFeature>

    var body: some View {
        if tweet.repostCount > 0 || tweet.quoteCount > 0 || (isOwnPost && tweet.likeCount > 0) {
            Menu {
                if tweet.repostCount > 0 {
                    Button {
                        store.send(.repostsButtonTapped(tweet))
                    } label: {
                        Label("Retweets", twitterIcon: .repostStroke)
                    }
                }

                if tweet.quoteCount > 0 {
                    Button {
                        store.send(.quotesButtonTapped(tweet))
                    } label: {
                        Label("Quote Tweets", twitterIcon: .quote)
                    }
                }

                if isOwnPost, tweet.likeCount > 0 {
                    Button {
                        store.send(.likesButtonTapped(tweet))
                    } label: {
                        Label("Likes", twitterIcon: .heartStroke)
                    }
                }
            } label: {
                Label("View Tweet Activity", twitterIcon: .views)
            }
        }
    }
}
