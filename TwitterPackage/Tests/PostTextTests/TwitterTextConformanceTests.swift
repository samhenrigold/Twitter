import Foundation
import Testing

@testable import PostText

/// twitter-text's conformance suite against the port (see ``TwitterTextConformanceCase`` for where the cases come
/// from). Every case of `extract.yml`, `tlds.yml`, and `validate.yml` runs, with these exceptions:
///
/// - `validate.yml`'s `urls` (24) and `urls_without_protocol` (5): they test `isValidUrl`, twitter-text's RFC 3986
///   validator for a URL on its own, which nothing here needs (extraction's checks are ported and tested).
/// - `autolink.yml` (196) and `hit_highlighting.yml` (14): they test HTML markup, which the typesetter's attributed
///   strings replace.
@Suite(.tags(.parser, .conformance))
struct TwitterTextConformanceTests {
    typealias Case = TwitterTextConformanceCase

    // MARK: Extraction

    @Test(arguments: try Case<[String]>.load(.extract, "mentions"))
    func mentions(_ test: Case<[String]>) {
        #expect(TwitterTextExtractor.mentions(in: test.text).map(\.text) == test.expected)
    }

    @Test(arguments: try Case<[ConformanceEntity]>.load(.extract, "mentions_with_indices"))
    func mentionsWithIndices(_ test: Case<[ConformanceEntity]>) {
        let found = TwitterTextExtractor.mentions(in: test.text).map { ConformanceEntity($0, in: test.text) }
        #expect(found == test.expected)
    }

    @Test(arguments: try Case<[ConformanceEntity]>.load(.extract, "mentions_or_lists_with_indices"))
    func mentionsOrListsWithIndices(_ test: Case<[ConformanceEntity]>) {
        let found = TwitterTextExtractor.mentionsOrLists(in: test.text).map {
            ConformanceEntity($0, in: test.text, withListSlug: true)
        }
        #expect(found == test.expected)
    }

    @Test(arguments: try Case<String?>.load(.extract, "replies"))
    func replies(_ test: Case<String?>) {
        #expect(TwitterTextExtractor.replyScreenName(in: test.text) == test.expected)
    }

    @Test(
        arguments: try Case<[String]>.load(.extract, "urls") + Case<[String]>.load(.extract, "tco_urls_with_params"))
    func urls(_ test: Case<[String]>) {
        #expect(TwitterTextExtractor.urls(in: test.text).map(\.text) == test.expected)
    }

    @Test(
        arguments: try Case<[ConformanceEntity]>.load(.extract, "urls_with_indices")
            + Case<[ConformanceEntity]>.load(.extract, "urls_with_directional_markers"))
    func urlsWithIndices(_ test: Case<[ConformanceEntity]>) {
        let found = TwitterTextExtractor.urls(in: test.text).map { ConformanceEntity($0, in: test.text) }
        #expect(found == test.expected)
    }

    @Test(
        arguments: try Case<[String]>.load(.tlds, "country") + Case<[String]>.load(.tlds, "generic"))
    func topLevelDomains(_ test: Case<[String]>) {
        #expect(TwitterTextExtractor.urls(in: test.text).map(\.text) == test.expected)
    }

    @Test(
        arguments: try Case<[String]>.load(.extract, "hashtags") + Case<[String]>.load(.extract, "hashtags_from_astral")
    )
    func hashtags(_ test: Case<[String]>) {
        #expect(TwitterTextExtractor.hashtags(in: test.text).map(\.text) == test.expected)
    }

    @Test(arguments: try Case<[ConformanceEntity]>.load(.extract, "hashtags_with_indices"))
    func hashtagsWithIndices(_ test: Case<[ConformanceEntity]>) {
        let found = TwitterTextExtractor.hashtags(in: test.text).map { ConformanceEntity($0, in: test.text) }
        #expect(found == test.expected)
    }

    @Test(arguments: try Case<[String]>.load(.extract, "cashtags"))
    func cashtags(_ test: Case<[String]>) {
        #expect(TwitterTextExtractor.cashtags(in: test.text).map(\.text) == test.expected)
    }

    @Test(arguments: try Case<[ConformanceEntity]>.load(.extract, "cashtags_with_indices"))
    func cashtagsWithIndices(_ test: Case<[ConformanceEntity]>) {
        let found = TwitterTextExtractor.cashtags(in: test.text).map { ConformanceEntity($0, in: test.text) }
        #expect(found == test.expected)
    }

    // MARK: Validation

    /// The original 140-character rules (`isValidTweetText` with the v1 configuration).
    @Test(arguments: try Case<Bool>.load(.validate, "tweets"))
    func tweets(_ test: Case<Bool>) {
        #expect(TweetLength(test.text, configuration: .v1).isValid == test.expected)
    }

    @Test(arguments: try Case<Bool>.load(.validate, "usernames"))
    func usernames(_ test: Case<Bool>) {
        #expect(TwitterTextValidation.isValidUsername(test.text) == test.expected)
    }

    @Test(arguments: try Case<Bool>.load(.validate, "lists"))
    func lists(_ test: Case<Bool>) {
        #expect(TwitterTextValidation.isValidList(test.text) == test.expected)
    }

    @Test(arguments: try Case<Bool>.load(.validate, "hashtags"))
    func validHashtags(_ test: Case<Bool>) {
        #expect(TwitterTextValidation.isValidHashtag(test.text) == test.expected)
    }

    /// v2: weighted code points, emoji counted by code point.
    @Test(arguments: try Case<ConformanceTweetLength>.load(.validate, "WeightedTweetsCounterTest"))
    func weightedLength(_ test: Case<ConformanceTweetLength>) {
        #expect(ConformanceTweetLength(TweetLength(test.text, configuration: .v2), of: test.text) == test.expected)
    }

    /// v3, today's count: emoji sequences once.
    @Test(
        arguments: try Case<ConformanceTweetLength>.load(.validate, "WeightedTweetsWithDiscountedEmojiCounterTest")
            + Case<ConformanceTweetLength>.load(.validate, "UnicodeDirectionalMarkerCounterTest"))
    func weightedLengthWithEmojiSequences(_ test: Case<ConformanceTweetLength>) {
        #expect(ConformanceTweetLength(TweetLength(test.text), of: test.text) == test.expected)
    }

    /// The embedded configurations are upstream's `config/v*.json`, field for field.
    @Test(arguments: [TwitterTextConfiguration.v1, .v2, .v3])
    func configurationMatchesUpstream(_ configuration: TwitterTextConfiguration) throws {
        let url = try #require(
            Bundle.module.url(
                forResource: "v\(configuration.version)", withExtension: "json", subdirectory: "TwitterText/config"))
        let upstream = try JSONDecoder().decode(TwitterTextConfiguration.self, from: Data(contentsOf: url))
        #expect(upstream == configuration)
        #expect(TwitterTextConfiguration.current == .v3)
    }
}

extension TwitterTextEntity {
    /// What the conformance cases list for it: the URL as written, or the name, tag or symbol without its sign.
    fileprivate var text: String {
        switch kind {
        case .url(let url): url
        case .mention(let screenName, _): screenName
        case .hashtag(let tag): tag
        case .cashtag(let symbol): symbol
        }
    }
}

extension ConformanceEntity {
    fileprivate init(_ entity: TwitterTextEntity, in text: String, withListSlug: Bool = false) {
        var listSlug: String?
        if withListSlug, case .mention(_, let slug) = entity.kind { listSlug = slug.map { "/" + $0 } ?? "" }
        self.init(
            text: entity.text, listSlug: listSlug,
            indices: [entity.range.lowerBound, entity.range.upperBound].map {
                text.utf16.distance(from: text.startIndex, to: $0)
            })
    }
}

extension ConformanceTweetLength {
    /// `parseTweet`'s fields from a ``TweetLength`` of `text`: inclusive UTF-16 ranges, `0` for an empty one.
    fileprivate init(_ length: TweetLength, of text: String) {
        func offset(_ index: String.Index) -> Int { text.utf16.distance(from: text.startIndex, to: index) }
        self.init(
            weightedLength: length.weightedLength,
            valid: length.isValid,
            permillage: length.permillage,
            displayRangeStart: 0,
            displayRangeEnd: max(text.utf16.count - 1, 0),
            validRangeStart: offset(length.validRange.lowerBound),
            validRangeEnd: max(offset(length.validRange.upperBound) - 1, 0)
        )
    }
}
