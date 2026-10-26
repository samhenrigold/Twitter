import Foundation

package struct Tweet: Identifiable, Hashable, Codable, Sendable {
    package var id: String
    package var author: User
    package var text: String
    /// Where `text` shows a link (its display URL) and where each goes.
    package var links: [TextLink] = []
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
