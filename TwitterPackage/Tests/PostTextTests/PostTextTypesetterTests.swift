import Foundation
import Models
import Testing

@testable import PostText

/// Asserts on the typeset attributed string's runs and attributes; nothing here renders.
struct PostTextTypesetterTests {
    @Test
    func mentionsHashtagsAndCashtagsBecomeInAppLinks() {
        let typeset = PostTextTypesetter.build(PostTextInput(text: "hey @jack, #SwiftUI and $AAPL"))

        #expect(
            entities(typeset) == [
                Run("@jack", .mention("jack")),
                Run("#SwiftUI", .hashtag("#SwiftUI")),
                Run("$AAPL", .cashtag("$AAPL"))
            ])
        #expect(link(of: "@jack", in: typeset) == URL(string: "twitter-client://user/jack"))
        #expect(link(of: "#SwiftUI", in: typeset) == URL(string: "twitter-client://search?q=%23SwiftUI"))
        #expect(link(of: "$AAPL", in: typeset) == URL(string: "twitter-client://search?q=$AAPL"))
        #expect(String(typeset.attributedString.characters) == "hey @jack, #SwiftUI and $AAPL")
    }

    @Test
    func knownLinksWinOverBarePatterns() throws {
        let destination = try #require(URL(string: "https://example.com/a/very/long/path"))
        let placed = TextLink(range: 5..<24, url: destination)
        let typeset = PostTextTypesetter.build(PostTextInput(text: "read example.com/a/very… now", links: [placed]))

        #expect(entities(typeset) == [Run("example.com/a/very…", .url(destination))])
        #expect(link(of: "example.com/a/very…", in: typeset) == destination)
    }

    @Test
    func bareURLsDropTrailingSentencePunctuation() throws {
        let typeset = PostTextTypesetter.build(
            PostTextInput(text: "see https://en.wikipedia.org/wiki/Swift_(language)). And https://a.co/x."))

        #expect(
            entities(typeset) == [
                Run(
                    "https://en.wikipedia.org/wiki/Swift_(language)",
                    .url(
                        try #require(
                            URL(string: "https://en.wikipedia.org/wiki/Swift_(language)")))),
                Run("https://a.co/x", .url(try #require(URL(string: "https://a.co/x"))))
            ])
    }

    @Test
    func emailsAndNumericHashesAreNotEntities() {
        let typeset = PostTextTypesetter.build(PostTextInput(text: "mail me@example.com, we're #1"))
        #expect(entities(typeset).isEmpty)
    }

    @Test
    func textShowsAsWritten() {
        // The models decode character references; what reaches the typesetter is what the Tweet says.
        let text = "Tom &amp; Jerry &lt;3 &#39;hi&#x27; @a"
        #expect(String(PostTextTypesetter.build(PostTextInput(text: text)).attributedString.characters) == text)
    }

    @Test
    func bareDomainsLinkAsTwitterLinksThem() throws {
        let typeset = PostTextTypesetter.build(PostTextInput(text: "docs at swift.org/documentation, not file.txt"))
        #expect(
            entities(typeset) == [
                Run("swift.org/documentation", .url(try #require(URL(string: "https://swift.org/documentation"))))
            ])
    }

    @Test
    func twitterStylesSurviveEmojiAndSplitEntities() {
        // "🧑‍🧑‍🧒" is five scalars; the bold range is counted in scalars, as the API sends it.
        let text = "🧑‍🧑‍🧒 Big news @alice"
        let bold = TextStyleRange(range: 6..<16, isBold: true)
        let typeset = PostTextTypesetter.build(PostTextInput(text: text, styles: [bold]))

        let runs = typeset.attributedString.runs.map {
            (String(typeset.attributedString[$0.range].characters), $0.inlinePresentationIntent, $0.link != nil)
        }
        #expect(runs.count == 4)
        #expect(runs[0].0 == "🧑‍🧑‍🧒 " && runs[0].1 == nil)
        #expect(runs[1].0 == "Big news " && runs[1].1 == .stronglyEmphasized)
        // The style ends inside the mention: its first character is bold and still a link, the rest a plain link.
        #expect(runs[2].0 == "@" && runs[2].1 == .stronglyEmphasized && runs[2].2)
        #expect(runs[3].0 == "alice" && runs[3].1 == nil && runs[3].2)
    }

    @Test
    func truncationNeverCutsAnEntity() {
        let text =
            String(repeating: "word ", count: 6) + "https://example.com/long " + String(repeating: "x", count: 40)
        let typeset = PostTextTypesetter.build(PostTextInput(text: text, characterLimit: 35))

        #expect(String(typeset.attributedString.characters) == "word word word word word word…")
        #expect(entities(typeset).isEmpty)
    }

    @Test
    func shortOverrunsAreNotTruncated() {
        let input = PostTextInput(text: String(repeating: "a", count: 290), characterLimit: 280)
        #expect(input.characterLimit == nil)
        #expect(PostTextInput.truncated(input.text, limit: 280) == nil)
    }

    @Test
    func segmentsSplitAroundEntities() {
        let typeset = PostTextTypesetter.build(PostTextInput(text: "cc @a and @b_c #tag"))
        #expect(
            typeset.segments.map { (String($0.text.characters), $0.entity) }.elementsEqual(
                [
                    ("cc ", nil), ("@a", .mention("a")), (" and ", nil), ("@b_c", .mention("b_c")), (" ", nil),
                    ("#tag", .hashtag("#tag"))
                ],
                by: ==))
        #expect(typeset.segments.map(\.mention) == [nil, "a", nil, "b_c", nil, nil])

        #expect(PostTextTypesetter.build(PostTextInput(text: "nothing to see here")).segments.isEmpty)
    }

    /// Twitter has no Markdown: asterisks around a word are asterisks. Posts, community notes and bios all take this
    /// path (notes with their links, bios without).
    @Test(
        arguments: [
            "**word**", "*word*", "`x`", "__word__ and _word_", "~~gone~~", "2*3*4", "# not a heading",
            "[docs](https://swift.org)", "\\*escaped\\*"
        ],
        [[], [TextLink(range: 0..<1, url: URL(string: "https://swift.org")!)]] as [[TextLink]]
    )
    func markdownPunctuationStaysLiteral(text: String, links: [TextLink]) {
        let typeset = PostTextTypesetter.build(PostTextInput(text: text, links: links))
        #expect(typeset.attributedString.runs.allSatisfy { $0.inlinePresentationIntent == nil })
        #expect(String(typeset.attributedString.characters) == text)
    }

    @Test
    func officialRangesStyleBesideLiteralPunctuation() {
        let text = "**not** bold, _not_ italic"
        let styles = [TextStyleRange(range: 8..<12, isBold: true), TextStyleRange(range: 20..<26, isItalic: true)]
        let typeset = PostTextTypesetter.build(PostTextInput(text: text, styles: styles))

        let runs = typeset.attributedString.runs.map {
            (String(typeset.attributedString[$0.range].characters), $0.inlinePresentationIntent)
        }
        #expect(
            runs.elementsEqual(
                [("**not** ", nil), ("bold", .stronglyEmphasized), (", _not_ ", nil), ("italic", .emphasized)],
                by: ==))
    }

    @Test
    func officialRangesWrapEntities() {
        let styles = [TextStyleRange(range: 0..<11, isBold: true)]
        let typeset = PostTextTypesetter.build(PostTextInput(text: "thanks @bob", styles: styles))
        let mention = typeset.attributedString.runs.first { $0[PostEntityAttribute.self] == .mention("bob") }
        #expect(mention?.inlinePresentationIntent == .stronglyEmphasized)
    }

    @Test
    func cacheReturnsTheSameTypesetTextForEqualInputs() async {
        let input = PostTextInput(text: "cache me @\(UUID().uuidString.prefix(8))")
        #expect(PostTextTypesetter.cached(input) == nil)
        let prepared = await PostTextTypesetter.prepare(input)
        #expect(PostTextTypesetter.cached(input) == prepared)
        #expect(PostTextTypesetter.cachedOrInline(input)?.attributedString == prepared.attributedString)
    }

    @Test
    func longTextIsLeftForTheBackground() {
        let input = PostTextInput(text: String(repeating: "long ", count: 200) + UUID().uuidString)
        #expect(PostTextTypesetter.cachedOrInline(input) == nil)
    }

    @Test
    func generationalCacheKeepsRecentEntries() {
        var cache = GenerationalCache<Int, Int>(capacity: 3)
        for key in 0..<3 { cache[key] = key }
        // The third insert rolled the generation; a read promotes 0 back into the current one.
        #expect(cache[0] == 0)
        for key in 3..<5 { cache[key] = key }
        #expect(cache[0] == 0)
        #expect(cache[1] == nil)
    }

    // MARK: Helpers

    private struct Run: Equatable, CustomStringConvertible {
        let text: String
        let entity: PostEntity

        init(_ text: String, _ entity: PostEntity) {
            self.text = text
            self.entity = entity
        }

        var description: String { "\(text) → \(entity)" }
    }

    private func entities(_ typeset: TypesetPostText) -> [Run] {
        let string = typeset.attributedString
        return string.runs[\.postEntity].compactMap { entity, range in
            entity.map { Run(String(string[range].characters), $0) }
        }
    }

    private func link(of text: String, in typeset: TypesetPostText) -> URL? {
        let string = typeset.attributedString
        return string.runs.first { String(string[$0.range].characters) == text }?.link
    }
}
