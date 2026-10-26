/// `parseTweet`'s result, as the weighted-length sections write it. Ranges are inclusive UTF-16 offsets.
struct ConformanceTweetLength: Decodable, Hashable, Sendable {
    var weightedLength: Int
    var valid: Bool
    var permillage: Int
    var displayRangeStart: Int
    var displayRangeEnd: Int
    var validRangeStart: Int
    var validRangeEnd: Int
}
