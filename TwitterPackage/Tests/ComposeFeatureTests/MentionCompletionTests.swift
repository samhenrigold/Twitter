import ComposableArchitecture
import Testing

@testable import ComposeFeature
@testable import Models
@testable import Routing
@testable import TwitterClient

@MainActor
struct MentionCompletionTests {
    @Test
    func typingAHandleSuggestsAccountsAndPickingOneCompletesIt() async {
        let clock = TestClock()
        let store = TestStore(initialState: ComposeFeature.State(draft: Draft())) {
            ComposeFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0[TwitterClient.self].typeahead = { query in
                #expect(query == "poin")
                return [.mockFriend]
            }
        }

        await store.send(.binding(.set(\.text, "Thanks @poin"))) {
            $0.text = "Thanks @poin"
        }
        await clock.advance(by: .milliseconds(250))
        await store.receive(\.mentionSuggestionsResponse) {
            $0.mentionSuggestions = [.mockFriend]
        }
        await store.send(.mentionSuggestionTapped(.mockFriend)) {
            $0.text = "Thanks @\(User.mockFriend.screenName) "
            $0.mentionSuggestions = []
        }
    }

    @Test
    func anEmailAddressIsNotAMention() {
        var state = ComposeFeature.State(draft: Draft())
        state.text = "mail me at sam@example"
        #expect(state.mentionQuery == nil)
        state.text = "hey @"
        #expect(state.mentionQuery == nil)
        state.text = "hey @sam_h"
        #expect(state.mentionQuery == "sam_h")
    }
}
