import Dependencies
import Foundation
import Models
import Synchronization
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

private actor SessionStore {
    private var current: TwitterWebSession?
    private let vault = CookieVault()
    private var restoring: Task<User?, any Error>?
    private var viewer: User?

    /// Every window restores on launch; concurrent calls share one round trip and later calls reuse its result.
    func restore() async throws -> User? {
        if current != nil, let viewer { return viewer }
        if let restoring { return try await restoring.value }
        let task = Task { try await performRestore() }
        restoring = task
        defer { restoring = nil }
        return try await task.value
    }

    func signIn(cookies: [String: String]) async throws -> User {
        let session = makeSession(cookies: cookies, saving: true)
        let viewer = try await session.viewer()
        // The actor is reentrant: a sign-out or newer sign-in during `viewer()` supersedes this one.
        guard current === session else { throw TwitterError.notSignedIn }
        self.viewer = viewer
        return viewer
    }

    func signOut() {
        current = nil
        viewer = nil
        vault.clear()
    }

    /// The signed-in session, picked up from the Keychain if this launch hasn't made one yet. Requests don't wait for
    /// `restore` to validate it: the app shows a remembered account at launch, and its timelines load in parallel.
    func session() throws -> TwitterWebSession {
        if let current { return current }
        guard let cookies = Keychain.loadCookies() else { throw TwitterError.notSignedIn }
        return makeSession(cookies: cookies, saving: false)
    }

    private func performRestore() async throws -> User? {
        guard let session = try? session() else { return nil }
        do {
            let viewer = try await session.viewer()
            // The actor is reentrant: a sign-in or sign-out during `viewer()` supersedes this restore.
            guard current === session else { return self.viewer }
            self.viewer = viewer
            return viewer
        } catch TwitterError.unauthorized {
            guard current === session else { return self.viewer }
            signOut()
            return nil
        }
    }

    private func makeSession(cookies: [String: String], saving: Bool) -> TwitterWebSession {
        let generation = vault.begin(saving: saving ? cookies : nil)
        let session = TwitterWebSession(cookies: cookies) { [vault] cookies in
            vault.save(cookies, generation: generation)
        }
        current = session
        return session
    }
}

/// Persists session cookies in call order. Each session gets a generation; a superseded or signed-out session's
/// rotations are dropped, so a stale session can never write its cookies back over a newer one.
private final class CookieVault: Sendable {
    private let generation = Mutex(0)

    /// Starts a new generation (optionally saving its initial cookies) and returns it.
    func begin(saving cookies: [String: String]?) -> Int {
        generation.withLock { generation in
            generation += 1
            if let cookies { Keychain.saveCookies(cookies) }
            return generation
        }
    }

    func save(_ cookies: [String: String], generation: Int) {
        self.generation.withLock { current in
            guard current == generation else { return }
            Keychain.saveCookies(cookies)
        }
    }

    func clear() {
        generation.withLock { generation in
            generation += 1
            Keychain.deleteCookies()
        }
    }
}

extension TwitterWebSession {
    func feed(_ source: FeedSource, cursor: String?) async throws -> FeedPage {
        switch source {
        case .bookmarks:
            try await bookmarks(cursor: cursor)
        case .home(let following):
            try await homeTimeline(following: following, cursor: cursor)
        case .list(let id, _):
            try await listTimeline(id: id, cursor: cursor)
        case .notifications(let filter):
            try await notifications(type: filter.rawValue, cursor: cursor)
        case .search(let query, let latest):
            try await search(query, product: latest ? "Latest" : "Top", cursor: cursor)
        case .searchMedia(let query):
            try await search(query, product: "Media", cursor: cursor)
        case .thread(let tweetID):
            try await tweetDetail(id: tweetID, cursor: cursor)
        case .userLikes(let userID):
            try await likes(userID: userID, cursor: cursor)
        case .userMedia(let userID):
            try await userMedia(userID: userID, cursor: cursor)
        case .userPosts(let userID):
            try await userTweets(userID: userID, cursor: cursor)
        case .userReplies(let userID):
            try await userReplies(userID: userID, cursor: cursor)
        }
    }
}

extension TwitterWebSession {
    /// The web client's user timelines. `Retweeters` and `Favoriters` ask for promoted content as x.com does (the
    /// parser drops it); `Favoriters` only lists anyone for the viewer's own posts since likes went private.
    func users(_ source: UserListSource, cursor: String?) async throws -> UserPage {
        let operation: String
        var variables: [String: JSONValue] = ["count": 20]
        switch source {
        case .followers(let userID), .following(let userID):
            operation = if case .followers = source { "Followers" } else { "Following" }
            variables["userId"] = .string(userID)
            variables["includePromotedContent"] = false
            variables["withGrokTranslatedBio"] = false
        case .likers(let tweetID), .reposters(let tweetID):
            operation = if case .likers = source { "Favoriters" } else { "Retweeters" }
            variables["tweetId"] = .string(tweetID)
            variables["enableRanking"] = false
            variables["includePromotedContent"] = true
        case .searchPeople(let query):
            // The web client's People tab: a search whose timeline holds accounts.
            operation = "SearchTimeline"
            variables["rawQuery"] = .string(query)
            variables["querySource"] = "typed_query"
            variables["product"] = "People"
            variables["withGrokTranslatedBio"] = false
        }
        if let cursor { variables["cursor"] = .string(cursor) }
        return TimelineParser.userPage(from: try await graphQL(operation, variables: variables))
    }
}
