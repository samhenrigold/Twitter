import ComposableArchitecture
import Models
import PhotosUI
import Routing
import SwiftUI
import TwitterClient
import TwitterUI

package struct ComposeView: View {
    @Bindable var store: StoreOf<ComposeFeature>

    package init(store: StoreOf<ComposeFeature>) {
        self.store = store
    }
    @FocusState private var isEditorFocused: Bool
    @State private var pickedItems: [PhotosPickerItem] = []

    package var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let replyingTo = store.draft.replyingTo {
                        ReplyContext(tweet: replyingTo)
                    }

                    TextField(
                        store.draft.replyingTo == nil ? "What's happening?" : "Tweet your reply",
                        text: $store.text,
                        axis: .vertical
                    )
                    .font(.title3)
                    .lineLimit(4...)
                    .focused($isEditorFocused)

                    if !store.mentionSuggestions.isEmpty {
                        MentionSuggestions(users: store.mentionSuggestions) {
                            store.send(.mentionSuggestionTapped($0))
                        }
                    }

                    if !store.attachments.isEmpty {
                        AttachmentStrip(attachments: store.attachments) { id in
                            store.send(.removeAttachmentButtonTapped(id), animation: .snappy)
                        }
                    }

                    if let quoting = store.draft.quoting {
                        QuoteCard(tweet: quoting) {}
                            .disabled(true)
                    }

                    if let errorMessage = store.errorMessage {
                        Label(errorMessage, twitterIcon: .warningStroke)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding()
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(store.draft.replyingTo == nil ? "New Tweet" : "Reply")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", twitterIcon: .close, role: .cancel) {
                        store.send(.cancelButtonTapped)
                    }
                    .disabled(store.isPosting || store.isDismissing)
                }

                if store.offersDrafts {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Drafts") { store.send(.draftsButtonTapped) }
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Tweet", twitterIcon: .compose, role: .confirm) {
                        store.send(.postButtonTapped)
                    }
                    .disabled(!store.canPost)
                }

            }
            // Above the keyboard, as Twitter's composer keeps them.
            .safeAreaBar(edge: .bottom) {
                HStack {
                    PhotosPicker(
                        selection: $pickedItems,
                        maxSelectionCount: max(store.remainingPhotos, 1),
                        matching: .any(of: [.images, .videos])
                    ) {
                        Label("Add Media", twitterIcon: .mediaStroke)
                            .labelStyle(.iconOnly)
                            .frame(width: 32, height: 32)
                    }
                    .disabled(store.remainingPhotos == 0 || store.isPosting)

                    Spacer()

                    CharacterCountGauge(remaining: store.remainingCharacters)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .overlay {
                if store.isPosting {
                    ProgressView()
                        .controlSize(.large)
                        .padding()
                        .glassEffect(.regular, in: .rect(cornerRadius: 20))
                }
            }
        }
        .interactiveDismissDisabled(!store.text.isEmpty || !store.attachments.isEmpty || store.isPosting)
        .confirmationDialog($store.scope(state: \.confirmation, action: \.confirmation))
        .sheet(isPresented: $store.isShowingDrafts) {
            DraftsList(store: store)
        }
        .task(id: pickedItems) {
            guard !pickedItems.isEmpty else { return }
            let uploads = await MediaUpload.load(pickedItems)
            pickedItems = []
            store.send(.mediaPicked(uploads), animation: .snappy)
        }
        .onAppear { isEditorFocused = true }
    }
}

private struct CharacterCountGauge: View {
    let remaining: Int

    var body: some View {
        let progress =
            Double(ComposeFeature.State.characterLimit - remaining) / Double(ComposeFeature.State.characterLimit)
        Gauge(value: min(max(progress, 0), 1)) {
            Text("Characters")
        } currentValueLabel: {
            Text("\(remaining)")
                .monospacedDigit()
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(remaining < 0 ? .red : remaining < 20 ? .orange : .accentColor)
        .scaleEffect(0.6)
        // A scale effect doesn't shrink layout; size the slot the toolbar reserves to what's drawn.
        .frame(width: 32, height: 32)
        .accessibilityLabel("\(remaining) characters remaining")
    }
}

/// What's attached, as thumbnails to remove before posting.
private struct AttachmentStrip: View {
    let attachments: IdentifiedArrayOf<ComposeFeature.Attachment>
    let remove: (ComposeFeature.Attachment.ID) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    AttachmentThumbnail(attachment: attachment)
                        .overlay(alignment: .topTrailing) {
                            Button("Remove", twitterIcon: .close) { remove(attachment.id) }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.glass)
                                .buttonBorderShape(.circle)
                                .controlSize(.small)
                                .padding(6)
                        }
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

private struct AttachmentThumbnail: View {
    let attachment: ComposeFeature.Attachment

    var body: some View {
        Group {
            if attachment.isVideo {
                Rectangle()
                    .fill(.fill.secondary)
                    .overlay {
                        TwitterIcon.play.image
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .foregroundStyle(.secondary)
                    }
            } else if let image = UIImage(data: attachment.upload.data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: attachment.isVideo ? 160 : 120, height: 120)
        .clipShape(.rect(cornerRadius: 12))
        .accessibilityLabel(attachment.isVideo ? "Video" : "Photo")
    }
}

extension MediaUpload {
    /// Loads picked library items for upload: photos as JPEG, GIFs and videos as they are. Items that fail to load are
    /// left out.
    static func load(_ items: [PhotosPickerItem]) async -> [MediaUpload] {
        var uploads: [MediaUpload] = []
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let types = item.supportedContentTypes
            if types.contains(where: { $0.conforms(to: .movie) }) {
                uploads.append(MediaUpload(data: data, mimeType: "video/mp4"))
            } else if types.contains(where: { $0.conforms(to: .gif) }) {
                uploads.append(MediaUpload(data: data, mimeType: "image/gif"))
            } else if let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.9) {
                uploads.append(MediaUpload(data: jpeg, mimeType: "image/jpeg"))
            }
        }
        return uploads
    }
}

/// The post being replied to, above the reply as in Twitter's composer: its author and text, a thread line down
/// toward the reply, and who the reply goes to.
private struct ReplyContext: View {
    let tweet: Tweet

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 4) {
                Avatar(user: tweet.author, size: 40)

                Rectangle()
                    .fill(.separator)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                AuthorLine(user: tweet.author, date: tweet.createdAt)

                Text(tweet.text)
                    .font(.subheadline)
                    .lineLimit(6)

                Text("Replying to @\(tweet.author.screenName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
        }
        .tweetMetrics()
        .accessibilityElement(children: .combine)
    }
}

/// Accounts to complete the mention being typed, as Twitter's composer lists them.
private struct MentionSuggestions: View {
    let users: [User]
    let select: (User) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(users) { user in
                Button {
                    select(user)
                } label: {
                    HStack(spacing: 10) {
                        Avatar(user: user, size: 36)

                        AuthorLine(user: user, date: nil, layout: .stacked)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 6)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)

                if user.id != users.last?.id {
                    Divider()
                }
            }
        }
        .tweetMetrics()
    }
}

/// Drafts to pick up again: tap one to finish it, swipe to delete.
private struct DraftsList: View {
    let store: StoreOf<ComposeFeature>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.drafts) { draft in
                    Button {
                        store.send(.draftTapped(draft))
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            if let replyingTo = draft.replyingTo {
                                Text("Replying to @\(replyingTo.author.screenName)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }

                            Text(draft.text)
                                .lineLimit(3)

                            Text(draft.savedAt, format: .relative(presentation: .named))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { store.send(.deleteDrafts($0)) }
            }
            .listStyle(.plain)
            .navigationTitle("Drafts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", twitterIcon: .close, role: .close) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
