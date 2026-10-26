import ComposableArchitecture
import Models
import Routing
import SwiftUI
import TweetEngagement
import TwitterClient
import TwitterUI

package struct TweetMenu: View {
    let tweet: Tweet
    let engagement: Engagement
    let store: StoreOf<FeedFeature>
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows
    @SharedReader(.viewer) private var viewer

    package var body: some View {
        Button {
            store.send(.replyButtonTapped(tweet))
        } label: {
            Label("Reply", twitterIcon: .replyStroke)
        }
        .disabled(!tweet.viewerCanReply)

        Button {
            store.send(.repostButtonTapped(tweet))
        } label: {
            Label(engagement.repost.isOn ? "Undo Retweet" : "Retweet", twitterIcon: .repostStroke)
        }

        Button {
            store.send(.quoteButtonTapped(tweet))
        } label: {
            Label("Quote Tweet", twitterIcon: .quoteTweet)
        }

        PostActivityMenu(tweet: tweet, isOwnPost: tweet.author.id == viewer?.id, store: store)

        Button {
            store.send(.authorTapped(tweet.author))
        } label: {
            Label("View @\(tweet.author.screenName)", twitterIcon: .personStroke)
        }

        if tweet.author.id == viewer?.id {
            Button(role: .destructive) {
                store.send(.deleteButtonTapped(tweet))
            } label: {
                Label("Delete Tweet", twitterIcon: .trash)
            }
        } else {
            Button {
                store.send(.muteButtonTapped(tweet.author))
            } label: {
                Label(
                    tweet.author.isMuting
                        ? "Unmute @\(tweet.author.screenName)" : "Mute @\(tweet.author.screenName)",
                    twitterIcon: tweet.author.isMuting ? .unmute : .mute)
            }

            Button {
                store.send(.blockButtonTapped(tweet.author))
            } label: {
                Label(
                    tweet.author.isBlocking
                        ? "Unblock @\(tweet.author.screenName)" : "Block @\(tweet.author.screenName)",
                    twitterIcon: tweet.author.isBlocking ? .unblock : .block)
            }
        }

        if supportsMultipleWindows {
            Divider()

            Button {
                openWindow(value: Route.thread(tweet).window)
            } label: {
                Label("Open in New Window", twitterIcon: .newWindow)
            }

            Button {
                openWindow(value: Route.profile(tweet.author).window)
            } label: {
                Label("Open @\(tweet.author.screenName) in New Window", twitterIcon: .newWindow)
            }
        }

        Divider()

        ShareLink(item: tweet.url)

        Button {
            UIPasteboard.general.url = tweet.url
        } label: {
            Label("Copy Link", twitterIcon: .link)
        }

        if tweet.isInAnotherLanguage() {
            Button {
                store.send(.translateButtonTapped(tweet))
            } label: {
                Label("Translate Tweet", twitterIcon: .globe)
            }
        }

        if !tweet.text.isEmpty {
            Button {
                UIPasteboard.general.string = tweet.text
            } label: {
                Label("Copy Text", twitterIcon: .copyStroke)
            }
        }
    }
}
