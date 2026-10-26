import Testing

@testable import PostText

/// What the composer reads from a ``TweetLength``, beyond the conformance cases' numbers.
@Suite(.tags(.parser))
struct TweetLengthTests {
    @Test
    func everyURLCountsAsItsShortLink() {
        let long = "https://example.com/" + String(repeating: "a", count: 200)
        #expect(TweetLength("see \(long)").weightedLength == 4 + 23)
        #expect(TweetLength("see example.com").weightedLength == 4 + 23)
    }

    @Test
    func wideScriptsAndEmojiSequencesCountTwice() {
        #expect(TweetLength("日本").weightedLength == 4)
        #expect(TweetLength("👩🏽‍💻").weightedLength == 2)
        #expect(TweetLength("🇯🇵").weightedLength == 2)
    }

    @Test
    func overLimitRangeStartsWhereTheLimitIsCrossed() throws {
        let text = String(repeating: "a", count: 279) + "日本"
        let length = TweetLength(text)
        #expect(length.weightedLength == 283)
        #expect(!length.isValid)
        #expect(length.remaining == -3)
        let over = try #require(length.overLimitRange)
        #expect(text[over] == "日本")
        #expect(text[length.validRange] == String(repeating: "a", count: 279))
    }

    @Test
    func aURLCrossingTheLimitIsOverItWhole() throws {
        let text = String(repeating: "a", count: 270) + " https://swift.org"
        let length = TweetLength(text)
        #expect(text[try #require(length.overLimitRange)] == "https://swift.org")
    }

    @Test
    func emptyTextIsInvalidButFits() {
        let length = TweetLength("")
        #expect(!length.isValid)
        #expect(length.remaining == 280)
        #expect(length.overLimitRange == nil)
    }

    @Test
    func remainingAgainstAnotherLimit() {
        #expect(TweetLength("hello").remaining(limit: 10) == 5)
    }
}
