import Foundation
import Testing

@testable import Models
@testable import PostText

/// Differential tests with Twitter's API as the oracle: each fixture is a post as the API sends it, entities and their
/// code-point indices included. The post goes through the app's own path (``TimelineParser`` expands t.co links and
/// trims reply mentions, then the typesetter parses the result) and the entities we find must be exactly the ones the
/// API listed, in order, with nothing extra. Expected values are derived from the API's indices, never written by hand.
@Suite(.tags(.parser, .apiOracle))
struct APIEntityFixtureTests {
    @Test(arguments: APIPostFixture.all)
    func entitiesMatchTheAPI(_ fixture: APIPostFixture) throws {
        try fixture.validate()
        let tweet = try #require(TimelineParser.tweet(from: fixture.tweetResult))
        // The input a timeline row typesets (TweetText.timelineInput).
        let input = PostTextInput(
            text: tweet.text, links: tweet.links, tags: tweet.hashtags + tweet.cashtags, styles: tweet.styles)
        let typeset = PostTextTypesetter.build(input)

        let string = typeset.attributedString
        let found = string.runs[\.postEntity].compactMap { entity, range in
            entity.map { FoundEntity(text: String(string[range].characters), entity: $0) }
        }
        #expect(found == fixture.expectedEntities)
        #expect(String(string.characters) == fixture.expectedText)
    }
}

struct FoundEntity: Equatable, CustomStringConvertible {
    let text: String
    let entity: PostEntity

    var description: String { "\(text) → \(entity)" }
}

/// A legacy post in the API's shape. Indices count Unicode code points of `fullText`, as the API's do.
struct APIPostFixture: CustomTestStringConvertible, Sendable {
    enum Entity: Sendable {
        case hashtag(String, Range<Int>)
        case symbol(String, Range<Int>)
        case mention(String, Range<Int>)
        /// The t.co URL, what the post shows for it, and where it goes.
        case url(String, display: String, expanded: String, Range<Int>)

        var indices: Range<Int> {
            switch self {
            case .hashtag(_, let range), .symbol(_, let range), .mention(_, let range), .url(_, _, _, let range):
                range
            }
        }
    }

    let name: String
    let fullText: String
    var displayTextRange: Range<Int>?
    let entities: [Entity]

    var testDescription: String { name }

    // MARK: Oracle

    private var scalars: [Unicode.Scalar] { Array(fullText.unicodeScalars) }

    private func slice(_ range: Range<Int>) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars[range])
        return String(view)
    }

    /// The fixture is self-consistent: every entity's indices cover its own text.
    func validate() throws {
        for entity in entities {
            let text = slice(entity.indices)
            switch entity {
            case .hashtag(let tag, _): #expect(text.dropFirst() == tag && "#＃".contains(text.first!), "\(name)")
            case .symbol(let symbol, _): #expect(text == "$" + symbol, "\(name)")
            case .mention(let screenName, _):
                #expect(text.dropFirst().lowercased() == screenName.lowercased(), "\(name)")
            case .url(let short, _, _, _): #expect(text == short, "\(name)")
            }
        }
    }

    /// The text after the app's rewrite: shown range only, t.co links replaced by their display text.
    var expectedText: String {
        var text = slice(displayTextRange ?? 0..<scalars.count)
        for case .url(let short, let display, _, _) in entities { text = text.replacing(short, with: display) }
        return TimelineParser.decodeEntities(text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// What the API recognized inside the shown range, in order, as the typesetter should tag it.
    var expectedEntities: [FoundEntity] {
        let shown = displayTextRange ?? 0..<scalars.count
        return entities.filter { shown.contains($0.indices.lowerBound) }.sorted {
            $0.indices.lowerBound < $1.indices.lowerBound
        }
        .map { entity in
            let text = slice(entity.indices)
            switch entity {
            case .hashtag(let tag, _): return FoundEntity(text: text, entity: .hashtag("#" + tag))
            case .symbol(let symbol, _): return FoundEntity(text: text, entity: .cashtag("$" + symbol))
            case .mention: return FoundEntity(text: text, entity: .mention(String(text.dropFirst())))
            case .url(_, let display, let expanded, _):
                return FoundEntity(text: display, entity: .url(URL(string: expanded)!))
            }
        }
    }

    var tweetResult: [String: Any] {
        var hashtags: [[String: Any]] = []
        var symbols: [[String: Any]] = []
        var mentions: [[String: Any]] = []
        var urls: [[String: Any]] = []
        for entity in entities {
            let indices = [entity.indices.lowerBound, entity.indices.upperBound]
            switch entity {
            case .hashtag(let tag, _): hashtags.append(["text": tag, "indices": indices])
            case .symbol(let symbol, _): symbols.append(["text": symbol, "indices": indices])
            case .mention(let screenName, _): mentions.append(["screen_name": screenName, "indices": indices])
            case .url(let short, let display, let expanded, _):
                urls.append(["url": short, "display_url": display, "expanded_url": expanded, "indices": indices])
            }
        }
        var legacy: [String: Any] = [
            "full_text": fullText,
            "id_str": name,
            "entities": ["hashtags": hashtags, "symbols": symbols, "user_mentions": mentions, "urls": urls]
        ]
        if let displayTextRange {
            legacy["display_text_range"] = [displayTextRange.lowerBound, displayTextRange.upperBound]
        }
        return [
            "__typename": "Tweet",
            "rest_id": name,
            "core": [
                "user_results": ["result": ["rest_id": "u1", "core": ["screen_name": "author", "name": "Author"]]]
            ],
            "legacy": legacy
        ]
    }

    // MARK: Corpus

    static let all: [APIPostFixture] = [
        APIPostFixture(
            name: "mixed",
            fullText: "Shipping today with @jack and @Biz 🎉 #SwiftUI #iOS27 $AAPL https://t.co/abc123XYZ",
            entities: [
                .mention("jack", 20..<25), .mention("biz", 30..<34), .hashtag("SwiftUI", 37..<45),
                .hashtag("iOS27", 46..<52), .symbol("AAPL", 53..<58),
                .url(
                    "https://t.co/abc123XYZ", display: "developer.apple.com/swiftui/",
                    expanded: "https://developer.apple.com/swiftui/", 59..<81)
            ]),
        APIPostFixture(
            name: "mention punctuation",
            fullText: "(@jack) .@biz: thoughts? mail sam@example.com",
            entities: [.mention("jack", 1..<6), .mention("biz", 9..<13)]),
        APIPostFixture(
            name: "hashtag boundaries",
            fullText: "#1 isn't a tag, C#dev isn't either, but #1st and #hash_tag are",
            entities: [.hashtag("1st", 40..<44), .hashtag("hash_tag", 49..<58)]),
        APIPostFixture(
            name: "unicode tags",
            fullText: "#日本語 と #café ＃全角",
            entities: [.hashtag("日本語", 0..<4), .hashtag("café", 7..<12), .hashtag("全角", 13..<16)]),
        APIPostFixture(
            name: "emoji before entities",
            fullText: "🧑‍🧑‍🧒 dinner with @alice #family",
            entities: [.mention("alice", 18..<24), .hashtag("family", 25..<32)]),
        APIPostFixture(
            name: "cashtags",
            fullText: "$BRK.B up, $5 isn't a symbol, $TSLA down",
            entities: [.symbol("BRK.B", 0..<6), .symbol("TSLA", 30..<35)]),
        APIPostFixture(
            name: "link before sentence punctuation",
            fullText: "Read this: https://t.co/x1y2z3a4b5. Then https://t.co/q9w8e7r6t5!",
            entities: [
                .url(
                    "https://t.co/x1y2z3a4b5", display: "en.wikipedia.org/wiki/Swift_(pr…",
                    expanded: "https://en.wikipedia.org/wiki/Swift_(programming_language)", 11..<34),
                .url(
                    "https://t.co/q9w8e7r6t5", display: "swift.org", expanded: "https://swift.org", 41..<64)
            ]),
        APIPostFixture(
            name: "reply mentions outside the shown range",
            fullText: "@jack @biz agreed, cc @ev",
            displayTextRange: 11..<25,
            entities: [.mention("jack", 0..<5), .mention("biz", 6..<10), .mention("ev", 22..<25)]),
        APIPostFixture(
            name: "too-long name",
            fullText: "@this_name_is_far_too_long isn't a mention but @ok_name is",
            entities: [.mention("ok_name", 47..<55)]),
        APIPostFixture(
            name: "character references",
            fullText: "#cartoons Tom &amp; Jerry &lt;3",
            entities: [.hashtag("cartoons", 0..<9)]),
        // The Tweet says "&lt;div&gt;" literally: decoded once, by the models, it stays that way.
        APIPostFixture(
            name: "escaped character references",
            fullText: "Use &amp;lt;div&amp;gt; for this #html",
            entities: [.hashtag("html", 33..<38)]),
        // Two links Twitter shortens to the same display text still go to their own pages.
        APIPostFixture(
            name: "links sharing a display text",
            fullText: "Two stories: https://t.co/one111 and https://t.co/two222",
            entities: [
                .url(
                    "https://t.co/one111", display: "nytimes.com/2026/10/26/tec…",
                    expanded: "https://www.nytimes.com/2026/10/26/technology/one.html", 13..<32),
                .url(
                    "https://t.co/two222", display: "nytimes.com/2026/10/26/tec…",
                    expanded: "https://www.nytimes.com/2026/10/26/technology/two.html", 37..<56)
            ])
    ]
}
