import ComposableArchitecture
import Foundation
import Models
import Routing
import TwitterClient
import TwitterUI

@Reducer
package struct ComposeFeature {
    @ObservableState
    package struct State: Equatable {
        /// Photos, a GIF or a video to post with the text.
        var attachments: IdentifiedArrayOf<Attachment> = []
        let draft: Draft
        var errorMessage: String?
        /// The sheet is on its way out: a second tap on Cancel, while it slides away, would reach a parent that has
        /// already let go of it.
        var isDismissing = false
        var isPosting = false
        var text = ""

        package init(draft: Draft) {
            self.draft = draft
        }

        static let characterLimit = 280
        /// Twitter takes up to four photos, or one GIF or video on its own.
        static let photoLimit = 4

        var remainingCharacters: Int { Self.characterLimit - text.count }
        var canPost: Bool {
            !isPosting && !isDismissing && remainingCharacters >= 0
                && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty)
        }

        /// How many more photos fit; none once a GIF or video is attached.
        var remainingPhotos: Int {
            attachments.contains { !$0.isPhoto } ? 0 : Self.photoLimit - attachments.count
        }
    }

    /// Something picked to post with the Tweet.
    package struct Attachment: Equatable, Identifiable {
        package let id: UUID
        package let upload: MediaUpload

        var isPhoto: Bool { upload.mimeType.hasPrefix("image/") && upload.mimeType != "image/gif" }
        var isVideo: Bool { upload.mimeType.hasPrefix("video/") }
    }

    package enum Action: BindableAction {
        case binding(BindingAction<State>)
        case cancelButtonTapped
        /// Media picked from the library, loaded and ready to upload.
        case mediaPicked([MediaUpload])
        case postButtonTapped
        case postResponse(Result<String, any Error>)
        case removeAttachmentButtonTapped(Attachment.ID)
    }

    @Dependency(TwitterClient.self) var client
    @Dependency(\.dismiss) var dismiss
    @Dependency(\.uuid) var uuid

    package init() {}

    package var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .cancelButtonTapped:
                // Dismissing cancels the in-flight post effect, which could leave a post sent but unconfirmed.
                guard !state.isPosting, !state.isDismissing else { return .none }
                state.isDismissing = true
                return .run { _ in await dismiss() }

            case .mediaPicked(let uploads):
                for upload in uploads {
                    let attachment = Attachment(id: uuid(), upload: upload)
                    if attachment.isPhoto {
                        guard state.remainingPhotos > 0 else { continue }
                        state.attachments.append(attachment)
                    } else {
                        // A GIF or video goes on its own, in place of whatever was attached.
                        state.attachments = [attachment]
                    }
                }
                return .none

            case .removeAttachmentButtonTapped(let id):
                state.attachments.remove(id: id)
                return .none

            case .postButtonTapped:
                guard state.canPost else { return .none }
                state.isPosting = true
                state.errorMessage = nil
                let text = state.text
                let draft = state.draft
                let media = state.attachments.map(\.upload)
                return .run { send in
                    await send(
                        .postResponse(
                            Result {
                                try await client.post(text, draft.replyingTo?.id, draft.quoting?.url, media)
                            }
                        )
                    )
                }

            case .postResponse(.success):
                state.isPosting = false
                state.isDismissing = true
                return .run { _ in await dismiss() }

            case .postResponse(.failure(let error)):
                state.isPosting = false
                state.errorMessage = error.localizedDescription
                return .none
            }
        }
    }
}
