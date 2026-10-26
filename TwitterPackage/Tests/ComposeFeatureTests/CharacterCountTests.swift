import Foundation
import Testing

@testable import ComposeFeature
@testable import Routing

/// The count is Twitter's, not `String.count`: links weigh their t.co link, CJK and emoji two, emoji sequences once.
@MainActor
struct CharacterCountTests {
    @Test
    func linksCountAsTheirShortLink() {
        var state = ComposeFeature.State(draft: Draft())
        state.text = "read https://example.com/" + String(repeating: "x", count: 300)
        #expect(state.remainingCharacters == 280 - 5 - 23)
        #expect(state.canPost)
    }

    @Test
    func wideCharactersCountTwice() {
        var state = ComposeFeature.State(draft: Draft())
        state.text = String(repeating: "あ", count: 140)
        #expect(state.remainingCharacters == 0)
        #expect(state.canPost)
        state.text += "あ"
        #expect(state.remainingCharacters == -2)
        #expect(!state.canPost)
    }

    @Test
    func anEmojiSequenceCountsOnce() {
        var state = ComposeFeature.State(draft: Draft())
        state.text = String(repeating: "👨‍👩‍👧‍👦", count: 141)
        #expect(state.remainingCharacters == -2)
        #expect(!state.canPost)
    }

    @Test
    func aThreadPostsOnlyWhenEveryTweetFits() {
        var state = ComposeFeature.State(draft: Draft())
        state.text = "first"
        var followUp = ComposeFeature.FollowUp(id: UUID())
        followUp.text = String(repeating: "字", count: 141)
        state.followUps.append(followUp)
        #expect(followUp.remainingCharacters == -2)
        #expect(!state.canPost)
    }
}
