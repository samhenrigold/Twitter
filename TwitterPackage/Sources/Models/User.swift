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

extension User {
    /// The profile on the web, for sharing.
    package var profileURL: URL? {
        URL(string: "https://x.com/\(screenName)")
    }
}
