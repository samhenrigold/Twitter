import Foundation
import Models
import Testing

@testable import PostText

/// Precedence between what the API recognized and what the patterns find.
@Suite(.tags(.parser))
struct EntityScannerTests {
    @Test
    func placedLinkBeatsTheURLTheRulesFindThere() throws {
        let destination = try #require(URL(string: "https://example.com/full"))
        let text = "go https://example.com/x now"
        let tokens = EntityScanner.tokens(in: text, links: [TextLink(range: 3..<24, url: destination)], tags: [])
        #expect(entities(tokens, in: text) == [Found("https://example.com/x", .url(destination))])
    }

    @Test
    func linksSharingADisplayTextKeepTheirOwnDestinations() throws {
        let first = try #require(URL(string: "https://a.co/first"))
        let second = try #require(URL(string: "https://a.co/second"))
        let text = "a.co/x… and a.co/x… and a.co/x…"
        let links = [TextLink(range: 0..<7, url: first), TextLink(range: 12..<19, url: second)]
        let tokens = EntityScanner.tokens(in: text, links: links, tags: [])
        // The third is text that looks like a link, so it links where it says, not to either placed link.
        #expect(
            entities(tokens, in: text) == [
                Found("a.co/x…", .url(first)), Found("a.co/x…", .url(second)),
                Found("a.co/x", .url(try #require(URL(string: "https://a.co/x"))))
            ])
    }

    @Test
    func patternsOverlappingAPlacedLinkGiveWay() throws {
        let destination = try #require(URL(string: "https://example.com/a/very/long"))
        let text = "see example.com/a/very… #tag"
        let tokens = EntityScanner.tokens(in: text, links: [TextLink(range: 4..<23, url: destination)], tags: [])
        #expect(
            entities(tokens, in: text) == [
                Found("example.com/a/very…", .url(destination)), Found("#tag", .hashtag("#tag"))
            ])
    }

    @Test
    func linksOutsideTheTextAreDropped() throws {
        let destination = try #require(URL(string: "https://example.com"))
        let tokens = EntityScanner.tokens(in: "short", links: [TextLink(range: 3..<40, url: destination)], tags: [])
        #expect(tokens == [EntityScanner.Token(range: tokens[0].range, entity: nil)])
    }

    @Test
    func knownTagsNeedWordBoundaries() {
        // A digits-only tag the pattern rejects still links when the API recognized it, on word boundaries only.
        let text = "#٣ C#٣ #٣_ #٣"
        let tokens = EntityScanner.tokens(in: text, links: [], tags: ["#٣"])
        #expect(entities(tokens, in: text) == [Found("#٣", .hashtag("#٣")), Found("#٣", .hashtag("#٣"))])
    }

    @Test
    func tokensCoverTheWholeString() {
        let text = "hi @a, see #b and $CD."
        let tokens = EntityScanner.tokens(in: text, links: [], tags: ["#b"])
        #expect(tokens.map { String(text[$0.range]) }.joined() == text)
        #expect(zip(tokens, tokens.dropFirst()).allSatisfy { $0.range.upperBound == $1.range.lowerBound })
    }

    // MARK: Helpers

    private struct Found: Equatable {
        let text: String
        let entity: PostEntity

        init(_ text: String, _ entity: PostEntity) {
            self.text = text
            self.entity = entity
        }
    }

    private func entities(_ tokens: [EntityScanner.Token], in text: String) -> [Found] {
        tokens.compactMap { token in token.entity.map { Found(String(text[token.range]), $0) } }
    }
}
