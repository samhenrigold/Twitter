import Dependencies
import DependenciesMacros
import Foundation
import Models
import Sharing

package struct MediaUpload: Hashable, Sendable {
    package var data: Data
    package var mimeType: String

    package init(data: Data, mimeType: String) {
        self.data = data
        self.mimeType = mimeType
    }
}

@DependencyClient
package struct TwitterClient: Sendable {
    package var deleteTweet: @Sendable (_ id: String) async throws -> Void
    package var feed: @Sendable (_ source: FeedSource, _ cursor: String?) async throws -> FeedPage
    package var lists: @Sendable (_ userID: String, _ cursor: String?) async throws -> ListPage
    package var post:
        @Sendable (
            _ text: String, _ replyTo: String?, _ quoteURL: URL?, _ media: [MediaUpload]
        ) async throws -> String
    package var restoreSession: @Sendable () async throws -> User?
    package var setBlocking: @Sendable (_ isBlocking: Bool, _ userID: String) async throws -> Void
    package var setBookmarked: @Sendable (_ isBookmarked: Bool, _ tweetID: String) async throws -> Void
    package var setFollowing: @Sendable (_ isFollowing: Bool, _ userID: String) async throws -> Void
    package var setLiked: @Sendable (_ isLiked: Bool, _ tweetID: String) async throws -> Void
    package var setMuting: @Sendable (_ isMuting: Bool, _ userID: String) async throws -> Void
    package var setReposted: @Sendable (_ isReposted: Bool, _ tweetID: String) async throws -> Void
    package var signIn: @Sendable (_ cookies: [String: String]) async throws -> User
    package var signOut: @Sendable () async -> Void
    package var trends: @Sendable () async throws -> [Trend]
    /// Accounts matching what's been typed after an @, for completing a mention.
    package var typeahead: @Sendable (_ query: String) async throws -> [User]
    package var user: @Sendable (_ screenName: String) async throws -> User
    package var users: @Sendable (_ source: UserListSource, _ cursor: String?) async throws -> UserPage
}

extension TwitterClient: TestDependencyKey {
    package static var testValue: TwitterClient { TwitterClient() }

    package static var previewValue: TwitterClient {
        TwitterClient(
            deleteTweet: { _ in },
            feed: { source, cursor in .mock(source, cursor: cursor) },
            lists: { _, _ in .mock },
            post: { _, _, _, _ in "preview" },
            restoreSession: { .mock },
            setBlocking: { _, _ in },
            setBookmarked: { _, _ in },
            setFollowing: { _, _ in },
            setLiked: { _, _ in },
            setMuting: { _, _ in },
            setReposted: { _, _ in },
            signIn: { _ in .mock },
            signOut: {},
            trends: { Trend.mocks },
            typeahead: { query in
                ([User.mock, .mockFriend, .mockBusiness, .mockAffiliate] + User.mockCrowd).filter {
                    $0.screenName.localizedCaseInsensitiveContains(query)
                        || $0.name.localizedCaseInsensitiveContains(query)
                }
            },
            user: { screenName in
                User.mocks.first { $0.screenName.lowercased() == screenName.lowercased() } ?? .mock
            },
            users: { source, cursor in .mock(source, cursor: cursor) }
        )
    }
}

extension SharedKey where Self == FileStorageKey<User?>.Default {
    /// The signed-in account, shared by every window. The main window owns sign-in and sign-out and writes it; other
    /// windows watch it so they can step aside when the account goes away.
    ///
    /// It's kept on disk so the next launch can show the app, and its cached timelines, right away while
    /// `restoreSession` checks with Twitter that the account is still signed in.
    package static var viewer: Self {
        Self[.fileStorage(.applicationSupportDirectory.appending(component: "viewer.json")), default: nil]
    }
}
