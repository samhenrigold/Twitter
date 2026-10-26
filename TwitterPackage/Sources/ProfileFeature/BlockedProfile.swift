import ComposableArchitecture
import Models
import SwiftUI
import TwitterUI

/// The header alone, over a notice in place of the posts: someone the viewer blocked, or who blocked the viewer.
struct BlockedProfile: View {
    let user: User
    let store: StoreOf<ProfileFeature>

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ProfileHeader(user: user, isViewer: false, store: store)

                Divider()

                if user.blocksViewer {
                    ContentUnavailableView {
                        Label("You're blocked", twitterIcon: .block)
                    } description: {
                        Text("You can't follow or see @\(user.screenName)'s Tweets.")
                    }
                } else {
                    ContentUnavailableView {
                        Label("You blocked @\(user.screenName)", twitterIcon: .block)
                    } description: {
                        Text(
                            "Are you sure you want to view these Tweets? Viewing Tweets won't unblock @\(user.screenName)."
                        )
                    } actions: {
                        Button("View Tweets") { store.send(.viewPostsButtonTapped) }
                            .buttonStyle(.bordered)
                    }
                }
            }
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
    }
}
