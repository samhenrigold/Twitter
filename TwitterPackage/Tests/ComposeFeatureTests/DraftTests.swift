import ComposableArchitecture
import Foundation
import Testing

@testable import ComposeFeature
@testable import Routing
@testable import TwitterClient

@MainActor
struct DraftTests {
    @Test
    func cancellingWithTextSavesADraftToFinishLater() async {
        let store = TestStore(initialState: ComposeFeature.State(draft: Draft())) {
            ComposeFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.date.now = Date(timeIntervalSince1970: 0)
            $0.dismiss = DismissEffect {}
        }
        store.exhaustivity = .off

        await store.send(.binding(.set(\.text, "Half a thought")))
        await store.send(.cancelButtonTapped)
        #expect(store.state.confirmation != nil)
        await store.send(.confirmation(.presented(.saveDraftTapped)))
        #expect(store.state.drafts.map(\.text) == ["Half a thought"])

        // A new composer offers it, and finishing it posts and removes it.
        let next = TestStore(initialState: ComposeFeature.State(draft: Draft())) {
            ComposeFeature()
        } withDependencies: {
            $0[TwitterClient.self].post = { _, _, _, _ in "1" }
            $0.dismiss = DismissEffect {}
        }
        next.exhaustivity = .off
        #expect(next.state.offersDrafts)
        await next.send(.draftTapped(next.state.drafts[0]))
        #expect(next.state.text == "Half a thought")
        await next.send(.postButtonTapped)
        await next.receive(\.postResponse)
        #expect(next.state.drafts.isEmpty)
    }

    @Test
    func cancellingAnEmptyTweetJustCloses() async {
        let store = TestStore(initialState: ComposeFeature.State(draft: Draft())) {
            ComposeFeature()
        } withDependencies: {
            $0.dismiss = DismissEffect {}
        }

        await store.send(.cancelButtonTapped) {
            $0.isDismissing = true
        }
    }
}
