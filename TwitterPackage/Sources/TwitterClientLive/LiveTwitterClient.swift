import Dependencies
import Models
import TwitterClient

extension TwitterClient: DependencyKey {
    package static var liveValue: TwitterClient {
        let store = SessionStore()
        return TwitterClient(
            deleteTweet: { try await store.session().deleteTweet(id: $0) },
            feed: { source, cursor in try await store.session().feed(source, cursor: cursor) },
            lists: { userID, cursor in try await store.session().lists(userID: userID, cursor: cursor) },
            markNotificationsRead: { cursor in try await store.session().markNotificationsRead(cursor: cursor) },
            post: { text, replyTo, quoteURL, media in
                let session = try await store.session()
                var mediaIDs: [String] = []
                for upload in media {
                    let category: TwitterWebSession.MediaCategory =
                        upload.mimeType.hasPrefix("video") ? .video : upload.mimeType == "image/gif" ? .gif : .image
                    mediaIDs.append(
                        try await session.uploadMedia(upload.data, mimeType: upload.mimeType, category: category)
                    )
                }
                return try await session.post(text: text, replyTo: replyTo, mediaIDs: mediaIDs, quoteURL: quoteURL)
            },
            restoreSession: { try await store.restore() },
            setBlocking: { try await store.session().setBlocked($0, userID: $1) },
            setBookmarked: { try await store.session().setBookmarked($0, tweetID: $1) },
            setFollowing: { try await store.session().setFollowing($0, userID: $1) },
            setLiked: { try await store.session().setLiked($0, tweetID: $1) },
            setMuting: { try await store.session().setMuted($0, userID: $1) },
            setReposted: { try await store.session().setReposted($0, tweetID: $1) },
            signIn: { try await store.signIn(cookies: $0) },
            signOut: { await store.signOut() },
            trends: { try await store.session().trends() },
            typeahead: { try await store.session().typeahead($0) },
            unreadNotificationCount: { try await store.session().unreadNotificationCount() },
            user: { try await store.session().user(screenName: $0) },
            users: { source, cursor in try await store.session().users(source, cursor: cursor) },
            vote: { tweetID, poll, choice in
                guard let cardURI = poll.cardURI, let cardName = poll.cardName else {
                    throw TwitterError.api("This poll can't be voted in.")
                }
                try await store.session().vote(tweetID: tweetID, cardURI: cardURI, cardName: cardName, choice: choice)
            }
        )
    }
}
