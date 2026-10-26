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
