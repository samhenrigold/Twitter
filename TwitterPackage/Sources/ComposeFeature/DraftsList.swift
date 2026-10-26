import ComposableArchitecture
import SwiftUI
import TwitterUI

/// Drafts to pick up again: tap one to finish it, swipe to delete.
struct DraftsList: View {
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
