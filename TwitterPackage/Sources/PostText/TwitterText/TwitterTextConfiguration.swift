/// How Twitter weighs text against its length limit: twitter-text's `config/*.json`, field for field.
///
/// The versions are embedded rather than bundled: they are three small documents that upstream no longer changes, and
/// as constants they cost no bundle lookup and can't fail to load. The conformance tests decode the upstream JSON and
/// check it still matches.
package struct TwitterTextConfiguration: Hashable, Codable, Sendable {
    package var version: Int
    /// The most a Tweet may weigh, in characters.
    package var maxWeightedTweetLength: Int
    /// Weights are in 1/`scale` of a character, so a character can count as less than one.
    package var scale: Int
    /// The weight of a code point outside every range.
    package var defaultWeight: Int
    /// Whether an emoji sequence counts once, at `defaultWeight`, however many code points it takes.
    package var emojiParsingEnabled: Bool
    /// What every URL counts as, in characters: the length of the t.co link Twitter replaces it with.
    package var transformedURLLength: Int
    package var ranges: [WeightedRange]

    package init(
        version: Int,
        maxWeightedTweetLength: Int,
        scale: Int,
        defaultWeight: Int,
        emojiParsingEnabled: Bool = false,
        transformedURLLength: Int,
        ranges: [WeightedRange]
    ) {
        self.version = version
        self.maxWeightedTweetLength = maxWeightedTweetLength
        self.scale = scale
        self.defaultWeight = defaultWeight
        self.emojiParsingEnabled = emojiParsingEnabled
        self.transformedURLLength = transformedURLLength
        self.ranges = ranges
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        maxWeightedTweetLength = try container.decode(Int.self, forKey: .maxWeightedTweetLength)
        scale = try container.decode(Int.self, forKey: .scale)
        defaultWeight = try container.decode(Int.self, forKey: .defaultWeight)
        // v1 and v2 predate the key.
        emojiParsingEnabled = try container.decodeIfPresent(Bool.self, forKey: .emojiParsingEnabled) ?? false
        transformedURLLength = try container.decode(Int.self, forKey: .transformedURLLength)
        ranges = try container.decode([WeightedRange].self, forKey: .ranges)
    }

    /// The weight of one code point, in 1/`scale` of a character.
    package func weight(of scalar: Unicode.Scalar) -> Int {
        ranges.first { $0.contains(scalar) }?.weight ?? defaultWeight
    }

    /// What Twitter counts today: 280 characters, CJK and emoji at two each, emoji sequences once.
    package static let current = v3

    package static let v3 = TwitterTextConfiguration(
        version: 3,
        maxWeightedTweetLength: 280,
        scale: 100,
        defaultWeight: 200,
        emojiParsingEnabled: true,
        transformedURLLength: 23,
        ranges: v2.ranges
    )

    /// 280 characters with CJK at two, but every code point of an emoji sequence counted.
    package static let v2 = TwitterTextConfiguration(
        version: 2,
        maxWeightedTweetLength: 280,
        scale: 100,
        defaultWeight: 200,
        transformedURLLength: 23,
        ranges: [
            WeightedRange(start: 0, end: 4351, weight: 100),
            WeightedRange(start: 8192, end: 8205, weight: 100),
            WeightedRange(start: 8208, end: 8223, weight: 100),
            WeightedRange(start: 8242, end: 8247, weight: 100)
        ]
    )

    /// The original 140 code points.
    package static let v1 = TwitterTextConfiguration(
        version: 1,
        maxWeightedTweetLength: 140,
        scale: 1,
        defaultWeight: 1,
        transformedURLLength: 23,
        ranges: []
    )
}
