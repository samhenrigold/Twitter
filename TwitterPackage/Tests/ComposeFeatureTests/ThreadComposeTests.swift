import ComposableArchitecture
import Testing

@testable import ComposeFeature
@testable import Routing
@testable import TwitterClient

@MainActor
struct ThreadComposeTests {
    @Test
    func aThreadPostsEachPartReplyingToTheOneBefore() async {
        let posted = LockIsolated<[(text: String, replyTo: String?)]>([])
        let store = TestStore(initialState: ComposeFeature.State(draft: Draft())) {
            ComposeFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.dismiss = DismissEffect {}
            $0[TwitterClient.self].post = { text, replyTo, _, _ in
                posted.withValue { $0.append((text, replyTo)) }
                return "id-\(posted.value.count)"
            }
        }
        store.exhaustivity = .off

        await store.send(.binding(.set(\.text, "1/ A thread")))
        await store.send(.addFollowUpButtonTapped)
        await store.send(.followUpTextChanged(store.state.followUps[0].id, "2/ The end"))
        await store.send(.postButtonTapped)
        await store.receive(\.threadPartPosted)
        await store.receive(\.postResponse)
        #expect(posted.value.map(\.text) == ["1/ A thread", "2/ The end"])
        #expect(posted.value.map(\.replyTo) == [nil, "id-1"])
    }

    @Test
    func aThreadThatStopsPartwayRetriesOnlyWhatsLeft() async {
        struct Failure: Error {}
        let calls = LockIsolated(0)
        let store = TestStore(initialState: ComposeFeature.State(draft: Draft())) {
            ComposeFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0[TwitterClient.self].post = { _, _, _, _ in
                calls.withValue { $0 += 1 }
                if calls.value == 2 { throw Failure() }
                return "id-\(calls.value)"
            }
        }
        store.exhaustivity = .off

        await store.send(.binding(.set(\.text, "1/")))
        await store.send(.addFollowUpButtonTapped)
        await store.send(.followUpTextChanged(store.state.followUps[0].id, "2/"))
        await store.send(.postButtonTapped)
        await store.receive(\.threadPartPosted)
        await store.receive(\.postResponse)
        #expect(store.state.text == "2/")
        #expect(store.state.followUps.isEmpty)
        #expect(store.state.postedThreadTweetID == "id-1")
        #expect(store.state.errorMessage != nil)
    }
}
