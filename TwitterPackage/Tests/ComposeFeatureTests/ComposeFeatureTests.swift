import ComposableArchitecture
import Foundation
import Testing

@testable import ComposeFeature
@testable import Models
@testable import Routing
@testable import TwitterClient

@MainActor
struct ComposeFeatureTests {
    let photo = MediaUpload(data: Data([1]), mimeType: "image/jpeg")
    let video = MediaUpload(data: Data([2]), mimeType: "video/mp4")

    @Test
    func photosAttachUpToFour() async {
        let store = TestStore(initialState: ComposeFeature.State(draft: Draft())) {
            ComposeFeature()
        } withDependencies: {
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off

        await store.send(.mediaPicked(Array(repeating: photo, count: 3)))
        await store.send(.mediaPicked(Array(repeating: photo, count: 3)))
        #expect(store.state.attachments.count == 4)
        #expect(store.state.remainingPhotos == 0)
    }

    @Test
    func aVideoGoesOnItsOwn() async {
        let store = TestStore(initialState: ComposeFeature.State(draft: Draft())) {
            ComposeFeature()
        } withDependencies: {
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off

        await store.send(.mediaPicked([photo, photo]))
        await store.send(.mediaPicked([video]))
        #expect(store.state.attachments.map(\.upload) == [video])
        #expect(store.state.remainingPhotos == 0)

        await store.send(.removeAttachmentButtonTapped(store.state.attachments[0].id))
        #expect(store.state.attachments.isEmpty)
        #expect(store.state.remainingPhotos == ComposeFeature.State.photoLimit)
    }

    @Test
    func mediaAloneCanBePostedAndIsUploaded() async {
        let posted = LockIsolated<[MediaUpload]?>(nil)
        let store = TestStore(initialState: ComposeFeature.State(draft: Draft())) {
            ComposeFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0[TwitterClient.self].post = { text, _, _, media in
                #expect(text.isEmpty)
                posted.setValue(media)
                return "1"
            }
            $0.dismiss = DismissEffect {}
        }
        store.exhaustivity = .off

        #expect(!store.state.canPost)
        await store.send(.mediaPicked([photo]))
        #expect(store.state.canPost)
        await store.send(.postButtonTapped)
        await store.receive(\.postResponse)
        #expect(posted.value == [photo])
    }
}

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
