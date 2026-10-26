import Foundation

/// How long a Tweet is by Twitter's count (twitter-text's `parseTweet`), and how much of it fits.
///
/// Each code point weighs what its range in the configuration says (most scripts one character, CJK and emoji two),
/// after NFC normalization; with emoji parsing, an emoji sequence weighs two however many code points it takes; and
/// every URL weighs ``TwitterTextConfiguration/transformedURLLength``, the t.co link that will replace it.
///
/// Normalization runs a character at a time, so ``validRange`` and ``overLimitRange`` are ranges of the text as given,
/// not of its normalized form; the conformance cases' UTF-16 offsets come out the same.
package struct TweetLength: Hashable, Sendable {
    /// The weighted length, in characters.
    package let weightedLength: Int
    /// The limit the length was measured against.
    package let maxLength: Int
    /// Whether the text can be tweeted: not empty, within the limit, and free of the characters a Tweet may not hold.
    package let isValid: Bool
    /// The text's leading part that fits the limit, ending before any character a Tweet may not hold. An entity
    /// (a URL or an emoji) is in or out whole.
    package let validRange: Range<String.Index>
    /// The rest of the text, after ``validRange``, when there is any: what a composer highlights as over the limit.
    package let overLimitRange: Range<String.Index>?

    /// How much of the limit is used, in thousandths (`parseTweet`'s `permillage`).
    package var permillage: Int { weightedLength * 1_000 / maxLength }

    /// Characters left under the limit; negative when over it.
    package var remaining: Int { maxLength - weightedLength }

    /// Characters left under `limit` instead of the configuration's.
    package func remaining(limit: Int) -> Int { limit - weightedLength }

    package init(_ text: String, configuration: TwitterTextConfiguration = .current) {
        let scale = configuration.scale
        let limit = configuration.maxWeightedTweetLength * scale
        var weight = 0
        var hasInvalidCharacter = false
        var validEnd = text.startIndex

        func count(_ unitWeight: Int, through end: String.Index, isInvalid: Bool = false) {
            weight += unitWeight
            hasInvalidCharacter = hasInvalidCharacter || isInvalid
            if !hasInvalidCharacter, weight <= limit { validEnd = end }
        }
        func countCharacters(of run: Substring) {
            var index = run.startIndex
            for character in run {
                index = run.index(after: index)
                let (characterWeight, isInvalid) = Self.weigh(character, configuration: configuration)
                count(characterWeight, through: index, isInvalid: isInvalid)
            }
        }

        var cursor = text.startIndex
        for url in TwitterTextExtractor.urls(in: text) {
            countCharacters(of: text[cursor..<url.range.lowerBound])
            count(configuration.transformedURLLength * scale, through: url.range.upperBound)
            cursor = url.range.upperBound
        }
        countCharacters(of: text[cursor...])

        weightedLength = weight / scale
        maxLength = configuration.maxWeightedTweetLength
        isValid = !hasInvalidCharacter && weight > 0 && weight <= limit
        validRange = text.startIndex..<validEnd
        overLimitRange = validEnd < text.endIndex ? validEnd..<text.endIndex : nil
    }

    /// One character's weight, in 1/`scale` of a character, and whether a Tweet may not hold it.
    private static func weigh(
        _ character: Character, configuration: TwitterTextConfiguration
    ) -> (weight: Int, isInvalid: Bool) {
        if character.isASCII {
            return (character.unicodeScalars.reduce(0) { $0 + configuration.weight(of: $1) }, false)
        }
        let normalized = String(character).precomposedStringWithCanonicalMapping
        var scalars = normalized.unicodeScalars[...]
        var weight = 0
        if configuration.emojiParsingEnabled, scalars.first?.properties.isEmoji == true,
            let emoji = try? EmojiSequence.regex.prefixMatch(in: normalized)
        {
            weight += configuration.defaultWeight
            scalars = normalized.unicodeScalars[emoji.range.upperBound...]
        }
        weight += scalars.reduce(0) { $0 + configuration.weight(of: $1) }
        return (weight, scalars.contains(where: TwitterTextPatterns.invalidCharacters.contains))
    }
}
