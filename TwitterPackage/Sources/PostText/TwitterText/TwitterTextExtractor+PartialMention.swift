extension TwitterTextExtractor {
    /// The longest screen name an account can have; twitter-text links up to 20 characters, so older names still do.
    package static let screenNameLengthLimit = 15

    /// The mention being typed before `index` (a cursor): an `@` and up to ``screenNameLengthLimit`` characters of a
    /// screen name ending there, by the rules a finished mention links by (`mail sam@exam` isn't one). `nil` when the
    /// cursor isn't at the end of one, or when it's at a bare `@`.
    package static func partialMention(endingAt index: String.Index, in text: String) -> TwitterTextEntity? {
        let typed = String(text[..<index])
        guard let mention = mentionsOrLists(in: typed).last, mention.range.upperBound == typed.endIndex,
            case .mention(let screenName, nil) = mention.kind, screenName.count <= screenNameLengthLimit
        else { return nil }
        let start = text.utf8.index(
            text.startIndex, offsetBy: typed.utf8.distance(from: typed.startIndex, to: mention.range.lowerBound))
        return TwitterTextEntity(mention.kind, range: start..<index)
    }
}
