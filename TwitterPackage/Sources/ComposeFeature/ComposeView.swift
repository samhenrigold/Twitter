import ComposableArchitecture
import PhotosUI
import SwiftUI
import TwitterClient
import TwitterUI

/// The text field typing goes to: the first Tweet's, or one of the thread's.
private enum Editor: Hashable {
    case first
    case followUp(ComposeFeature.FollowUp.ID)
}

package struct ComposeView: View {
    @Bindable var store: StoreOf<ComposeFeature>

    package init(store: StoreOf<ComposeFeature>) {
        self.store = store
    }
    @FocusState private var focusedEditor: Editor?
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
                    .focused($focusedEditor, equals: .first)

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

                    ForEach(store.followUps) { followUp in
                        FollowUpEditor(
                            text: Binding {
                                followUp.text
                            } set: {
                                store.send(.followUpTextChanged(followUp.id, $0))
                            },
                            remainingCharacters: followUp.remainingCharacters
                        ) {
                            store.send(.removeFollowUpButtonTapped(followUp.id), animation: .snappy)
                        }
                        .focused($focusedEditor, equals: .followUp(followUp.id))
                    }

                    if let errorMessage = store.errorMessage {
                        Label(errorMessage, twitterIcon: .warningStroke)
                            .font(.footnote)
                            .foregroundStyle(.twitterError)
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

                    Button("Add another Tweet", twitterIcon: .plus) {
                        store.send(.addFollowUpButtonTapped, animation: .snappy)
                    }
                    .labelStyle(.iconOnly)
                    .frame(width: 32, height: 32)
                    .disabled(!store.hasText || store.isPosting)

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
        .onAppear { focusedEditor = .first }
        // A Tweet added to the thread is where typing goes next.
        .onChange(of: store.followUps.last?.id) { _, newID in
            if let newID { focusedEditor = .followUp(newID) }
        }
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
            Text(remaining, format: .number)
                .monospacedDigit()
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(remaining < 0 ? .twitterError : remaining < 20 ? .twitterWarning : .accentColor)
        .scaleEffect(0.6)
        // A scale effect doesn't shrink layout; size the slot the toolbar reserves to what's drawn.
        .frame(width: 32, height: 32)
        .accessibilityLabel("\(remaining) characters remaining")
    }
}
