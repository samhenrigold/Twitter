import Testing

@testable import PostText

/// The mention being typed, for autocomplete: the same rules as a finished mention.
@Suite(.tags(.parser))
struct PartialMentionTests {
    @Test(
        arguments: [
            ("hey @sam_h", "sam_h"), ("@jack", "jack"), ("RT @biz", "biz"), ("RT@biz", "biz"), ("(@ev", "ev"),
            ("＠fullwidth", "fullwidth")
        ])
    func mentionsBeingTyped(text: String, query: String) {
        let mention = TwitterTextExtractor.partialMention(endingAt: text.endIndex, in: text)
        guard case .mention(let screenName, nil)? = mention?.kind else {
            Issue.record("No mention in \(text)")
            return
        }
        #expect(screenName == query)
        #expect(mention.map { String(text[$0.range]) } == String(text.suffix(query.count + 1)))
    }

    @Test(
        arguments: [
            "mail me at sam@example", "hey @", "@a_name_too_long_for_twitter", "@café", "@jack/list", "a@b@c", "@jack "
        ])
    func notMentions(text: String) {
        #expect(TwitterTextExtractor.partialMention(endingAt: text.endIndex, in: text) == nil)
    }

    @Test
    func atTheCursor() {
        let text = "hi @jac and more"
        let cursor = text.index(text.startIndex, offsetBy: 7)
        let mention = TwitterTextExtractor.partialMention(endingAt: cursor, in: text)
        #expect(mention?.kind == .mention(screenName: "jac", listSlug: nil))
    }
}
