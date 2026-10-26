/// twitter-text's validators for single entities (`isValidUsername`, `isValidList`, `isValidHashtag`): each is valid
/// when it is exactly one entity and nothing else. A Tweet's own validity is ``TweetLength/isValid``.
package enum TwitterTextValidation {
    /// `@name`, alone.
    package static func isValidUsername(_ text: String) -> Bool {
        let mentions = TwitterTextExtractor.mentions(in: text)
        guard mentions.count == 1, case .mention(let screenName, _) = mentions[0].kind else { return false }
        return screenName == text.dropFirst()
    }

    /// `@name/slug`, alone.
    package static func isValidList(_ text: String) -> Bool {
        let lists = TwitterTextExtractor.mentionsOrLists(in: text)
        guard lists.count == 1, case .mention(_, let slug?) = lists[0].kind else { return false }
        return lists[0].range == text.startIndex..<text.endIndex && !slug.isEmpty
    }

    /// `#tag`, alone.
    package static func isValidHashtag(_ text: String) -> Bool {
        let hashtags = TwitterTextExtractor.hashtags(in: text)
        guard hashtags.count == 1, case .hashtag(let tag) = hashtags[0].kind else { return false }
        return tag == text.dropFirst()
    }
}
