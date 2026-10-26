import Foundation
import Models

/// Finds links, mentions, hashtags and cashtags, covering the whole string with tokens.
///
/// What the API recognized is data, not a guess to re-detect (the transcript app treats a resolved reference the same
/// way): its links sit where it placed them, and the rest of the text is read by twitter-text's rules, as Twitter
/// itself reads it. A hashtag or cashtag the API recognized links on word boundaries even where the rules wouldn't
/// (`#٣`), and wins over a pattern that starts at the same place. Otherwise the leftmost candidate wins.
enum EntityScanner {
    struct Token: Equatable {
        var range: Range<String.Index>
        var entity: PostEntity?
    }

    static func tokens(in text: String, links: [TextLink], tags: [String]) -> [Token] {
        guard !text.isEmpty else { return [] }
        let placed = placedLinks(links, in: text)

        // Known tags first, longest first, so a tag beats a pattern (or a shorter tag) starting with it.
        var candidates: [(range: Range<String.Index>, entity: PostEntity)] = []
        for tag in Set(tags).sorted(by: { $0.count > $1.count }) where !tag.isEmpty {
            let entity: PostEntity = tag.hasPrefix("$") ? .cashtag(tag) : .hashtag(normalizedTag(tag))
            candidates += knownTagRanges(tag, in: text).map { ($0, entity) }
        }
        candidates += TwitterTextExtractor.entities(in: text).compactMap { entity in
            postEntity(for: entity, in: text).map { (entity.range, $0) }
        }
        // A stable sort keeps the known tags ahead of a pattern at the same place.
        candidates.sort { $0.range.lowerBound < $1.range.lowerBound }

        var found = placed
        var lastEnd = text.startIndex
        for candidate in candidates {
            guard candidate.range.lowerBound >= lastEnd,
                !placed.contains(where: { $0.range.overlaps(candidate.range) })
            else { continue }
            found.append(candidate)
            lastEnd = candidate.range.upperBound
        }
        found.sort { $0.range.lowerBound < $1.range.lowerBound }

        var tokens: [Token] = []
        var cursor = text.startIndex
        for (range, entity) in found {
            if cursor < range.lowerBound { tokens.append(Token(range: cursor..<range.lowerBound, entity: nil)) }
            tokens.append(Token(range: range, entity: entity))
            cursor = range.upperBound
        }
        if cursor < text.endIndex { tokens.append(Token(range: cursor..<text.endIndex, entity: nil)) }
        return tokens
    }

    /// The API's links as ranges of `text`, in order; any that run outside it or into an earlier one are dropped.
    private static func placedLinks(
        _ links: [TextLink], in text: String
    ) -> [(range: Range<String.Index>, entity: PostEntity)] {
        let scalars = text.unicodeScalars
        let count = scalars.count
        var placed: [(range: Range<String.Index>, entity: PostEntity)] = []
        var lastEnd = 0
        for link in links.sorted(by: { $0.range.lowerBound < $1.range.lowerBound })
        where link.range.lowerBound >= lastEnd && link.range.upperBound <= count && !link.range.isEmpty {
            let start = scalars.index(scalars.startIndex, offsetBy: link.range.lowerBound)
            let end = scalars.index(start, offsetBy: link.range.count)
            placed.append((start..<end, .url(link.url)))
            lastEnd = link.range.upperBound
        }
        return placed
    }

    /// What a twitter-text entity links to: a list mention links its account, and a URL without a scheme goes over
    /// HTTPS, as Twitter's t.co link for it would.
    private static func postEntity(for entity: TwitterTextEntity, in text: String) -> PostEntity? {
        switch entity.kind {
        case .url(let written):
            let lowercased = written.lowercased()
            let hasScheme = lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://")
            return URL(string: hasScheme ? written : "https://" + written).map(PostEntity.url)
        case .mention(let screenName, _):
            // twitter-text stops a name at 20 characters; one that runs on is no one's.
            let next = text.unicodeScalars[entity.range.upperBound...].first
            guard !(next.map(TwitterTextPatterns.mentionNameCharacters.contains) ?? false) else { return nil }
            return .mention(screenName)
        case .hashtag(let tag):
            return .hashtag("#" + tag)
        case .cashtag(let symbol):
            return .cashtag("$" + symbol)
        }
    }

    /// Every occurrence of `tag` that sits on word boundaries: not after a word character or `&@#$`, not before a
    /// word character.
    private static func knownTagRanges(_ tag: String, in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var start = text.startIndex
        while let range = text.range(of: tag, options: .literal, range: start..<text.endIndex) {
            let before = text.unicodeScalars[..<range.lowerBound].last
            let after = text.unicodeScalars[range.upperBound...].first
            if !(before.map { isWordScalar($0) || "&@#$".unicodeScalars.contains($0) } ?? false),
                !(after.map(isWordScalar) ?? false)
            {
                ranges.append(range)
            }
            start = text.index(after: range.lowerBound)
        }
        return ranges
    }

    private static func isWordScalar(_ scalar: Unicode.Scalar) -> Bool {
        let properties = scalar.properties
        return scalar == "_" || properties.isAlphabetic || properties.numericType == .decimal
            || properties.generalCategory == .nonspacingMark
    }

    /// Fullwidth `＃` searches as `#`.
    private static func normalizedTag(_ token: String) -> String {
        token.hasPrefix("＃") ? "#" + token.dropFirst() : token
    }
}
