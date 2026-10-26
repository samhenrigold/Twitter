import ComposableArchitecture
import Models
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

    package var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let replyingTo = store.draft.replyingTo {
                        Text("Replying to @\(replyingTo.author.screenName)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    TextField(
                        store.draft.replyingTo == nil ? "What's happening?" : "Tweet your reply",
                        text: $store.text,
                        axis: .vertical
                    )
                    .font(.title3)
                    .lineLimit(4...)
                    .focused($isEditorFocused)

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

                ToolbarItem(placement: .confirmationAction) {
                    Button("Tweet", twitterIcon: .compose, role: .confirm) {
                        store.send(.postButtonTapped)
                    }
                    .disabled(!store.canPost)
                }

                ToolbarItem(placement: .bottomBar) {
                    CharacterCountGauge(remaining: store.remainingCharacters)
                }
                // A custom view stays horizontal by default and would vanish on the folded display's vertical bar;
                // the circular gauge fits that bar as is.
                .axisBehavior(.verticalPreferred)
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
        .interactiveDismissDisabled(!store.text.isEmpty || store.isPosting)
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
