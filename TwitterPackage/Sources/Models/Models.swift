import Foundation

package struct User: Identifiable, Hashable, Codable, Sendable {
    package var id: String
    package var name: String
    package var screenName: String
    package var avatarURL: URL?
    package var bannerURL: URL?
    package var bio: String = ""
    package var location: String = ""
    package var website: String?
    package var websiteURL: URL?
    package var followersCount: Int = 0
    package var followingCount: Int = 0
    package var postsCount: Int = 0
    package var isVerified: Bool = false
    package var verifiedType: String?
    package var isProtected: Bool = false
    package var isFollowing: Bool = false
    package var followsViewer: Bool = false
    package var isMuting: Bool = false
    package var isBlocking: Bool = false
    /// The account blocked the viewer.
    package var blocksViewer: Bool = false
    package var affiliate: AffiliateLabel?
    package var pinnedTweetID: String?
    package var joined: Date?

    /// The avatar variant to fetch for a given display size in points.
    package func avatarURL(forSize size: Double) -> URL? {
        if size > 56 { return largeAvatarURL }
        return avatarURL.flatMap {
            URL(string: $0.absoluteString.replacingOccurrences(of: "_normal.", with: "_bigger."))
        }
    }

    /// A sharper avatar than the 48px `_normal` default.
    package var largeAvatarURL: URL? {
        guard let avatarURL else { return nil }
        return URL(string: avatarURL.absoluteString.replacingOccurrences(of: "_normal.", with: "_400x400."))
    }
}

package struct Media: Identifiable, Hashable, Codable, Sendable {
    package enum Kind: String, Codable, Sendable { case photo, video, gif }
    package var id: String
    package var kind: Kind
    package var previewURL: URL
    package var videoURL: URL?
    /// A lighter variant (≤ ~2 Mbps) for muted inline autoplay.
    package var inlineVideoURL: URL?
    package var width: Double
    package var height: Double
    package var altText: String?
    package var durationMillis: Int?

    package var aspectRatio: Double { width > 0 && height > 0 ? width / height : 16 / 9 }

    package var fullSizeURL: URL {
        guard kind == .photo else { return previewURL }
        return URL(string: previewURL.absoluteString + "?name=orig") ?? previewURL
    }
}

extension Media {
    /// A photo, for images the viewer shows that aren't a post's, such as a profile's avatar.
    package init(id: String, photoURL: URL, width: Double, height: Double, altText: String? = nil) {
        self.init(id: id, kind: .photo, previewURL: photoURL, width: width, height: height, altText: altText)
    }
}

package struct LinkCard: Hashable, Codable, Sendable {
    package var title: String
    package var domain: String
    package var url: URL
    package var imageURL: URL?
}

package struct Tweet: Identifiable, Hashable, Codable, Sendable {
    package var id: String
    package var author: User
    package var text: String
    /// Display URL → destination, for linking the shortened URLs shown in `text`.
    package var links: [String: URL] = [:]
    package var createdAt: Date?
    package var replyCount = 0
    package var repostCount = 0
    package var likeCount = 0
    package var quoteCount = 0
    package var bookmarkCount = 0
    package var viewCount: Int?
    package var isLiked = false
    package var isReposted = false
    package var isBookmarked = false
    package var media: [Media] = []
    /// Zero or one quoted post (an array keeps the struct non-recursive).
    package var quoted: [Tweet] = []
    package var card: LinkCard?
    package var replyingTo: [String] = []
    /// The language Twitter detected (BCP 47, "en", "ja"); `nil` or `und` when it couldn't tell.
    package var language: String?
    package var conversationID: String?
    /// Bold/italic ranges of a long post's text.
    package var styles: [TextStyleRange] = []
    /// Hashtags and cashtags (with their `#`/`$`) Twitter recognized in `text`.
    package var hashtags: [String] = []
    package var cashtags: [String] = []
    package var communityNote: CommunityNote?
    package var poll: Poll?
    package var replyRestriction: ReplyRestriction?
    /// Shown in place of a quoted post Twitter won't show ("This post is unavailable").
    package var quotedTombstone: Tombstone?

    package var viewerCanReply: Bool { replyRestriction?.viewerCanReply ?? true }

    /// Whether the text is in a language other than `preferred` (the reader's), and so worth offering to translate.
    /// Twitter marks text it can't place (links, emoji, mentions alone) `und`, `zxx`, `qme` and the like.
    package func isInAnotherLanguage(than preferred: Locale.Language = Locale.current.language) -> Bool {
        guard let language, !text.isEmpty, !Self.unplacedLanguages.contains(language) else { return false }
        return Locale.Language(identifier: language).languageCode != preferred.languageCode
    }

    private static let unplacedLanguages: Set<String> = ["und", "zxx", "qam", "qct", "qht", "qme", "qst"]

    package var url: URL { URL(string: "https://x.com/\(author.screenName)/status/\(id)")! }
}

/// A post as it appears in a feed, with the context of how it got there.
package struct FeedTweet: Identifiable, Hashable, Codable, Sendable {
    package var id: String
    package var tweet: Tweet
    package var repostedBy: User?
    package var socialContext: String?
    /// Glyph for the context line: one of Twitter's icons by asset name, or an SF Symbol ("Pinned", "Twitter liked", "Followed by …").
    package var socialSymbol: String?
    /// Draws a thread line down to the next post (conversation modules and reply chains).
    package var connectsBelow = false
    package var connectsAbove = false
    /// A mention or reply in Notifications that arrived since they were last read.
    package var isUnread = false
}

package struct TwitterNotification: Identifiable, Hashable, Codable, Sendable {
    package var id: String
    package var icon: String
    package var message: String
    /// Unicode-scalar ranges in `message` that Twitter renders bold (the people's names).
    package var boldRanges: [Range<Int>] = []
    package var users: [User]
    package var date: Date?
    package var tweet: Tweet?
    package var tweetID: String?
    /// Arrived since Notifications were last read.
    package var isUnread = false
}

package enum FeedItem: Identifiable, Hashable, Codable, Sendable {
    case tweet(FeedTweet)
    case notification(TwitterNotification)
    case tombstone(Tombstone)
    case showMore(ShowMoreCursor)

    /// Arrived in Notifications since they were last read.
    package var isUnread: Bool {
        switch self {
        case .tweet(let item): item.isUnread
        case .notification(let item): item.isUnread
        case .tombstone, .showMore: false
        }
    }

    package var id: String {
        switch self {
        case .tweet(let item): "t-\(item.id)"
        case .notification(let item): "n-\(item.id)"
        case .tombstone(let item): "x-\(item.id)"
        case .showMore(let item): "s-\(item.id)"
        }
    }
}

package struct FeedPage: Sendable {
    package var items: [FeedItem]
    package var bottomCursor: String?
    package var topCursor: String?
}

package enum TwitterError: LocalizedError, Sendable {
    case notSignedIn
    case unauthorized
    case rateLimited(resetAt: Date?)
    case http(Int, String)
    case api(String)
    case catalog(String)
    case missingOperation(String)

    package var errorDescription: String? {
        switch self {
        case .notSignedIn: "You're not signed in."
        case .unauthorized: "Your Twitter session expired. Sign in again."
        case .rateLimited(let reset):
            if let reset {
                "Twitter rate limit reached. Try again \(reset.formatted(.relative(presentation: .named)))."
            } else {
                "Twitter rate limit reached. Try again in a few minutes."
            }
        case .http(let code, let body): "Twitter returned HTTP \(code). \(body.prefix(200))"
        case .api(let message): message
        case .catalog(let message): message
        case .missingOperation(let name): "Twitter's web client no longer exposes \(name)."
        }
    }
}

extension FeedTweet {
    package init(tweet: Tweet) {
        self.init(id: tweet.id, tweet: tweet)
    }
}

package enum FeedSource: Hashable, Sendable {
    case bookmarks
    case home(following: Bool)
    /// A List's timeline, newest first.
    case list(id: String, name: String)
    case notifications(NotificationFilter)
    case search(query: String, latest: Bool)
    /// A search's photos and videos.
    case searchMedia(query: String)
    case thread(tweetID: String)
    case userLikes(userID: String)
    case userMedia(userID: String)
    case userPosts(userID: String)
    case userReplies(userID: String)
}

extension User {
    /// The profile on the web, for sharing.
    package var profileURL: URL? {
        URL(string: "https://x.com/\(screenName)")
    }
}

/// Which notifications a Notifications tab shows, as Twitter's All, Verified and Mentions.
package enum NotificationFilter: String, Hashable, Sendable {
    case all = "All"
    case verified = "Verified"
    case mentions = "Mentions"
}
