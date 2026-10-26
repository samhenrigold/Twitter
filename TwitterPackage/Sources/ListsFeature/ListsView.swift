import ComposableArchitecture
import Models
import SwiftUI
import TwitterUI

package struct ListsView: View {
    let store: StoreOf<ListsFeature>

    package init(store: StoreOf<ListsFeature>) {
        self.store = store
    }

    package var body: some View {
        Group {
            if let errorMessage = store.errorMessage, store.lists.isEmpty {
                ContentUnavailableView {
                    Label("Couldn't load Lists", twitterIcon: .warningStroke)
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try Again") { store.send(.retryButtonTapped) }
                        .buttonStyle(.bordered)
                }
            } else if store.hasLoaded, store.lists.isEmpty {
                ContentUnavailableView("No Lists yet", twitterIcon: .lists)
            } else if !store.hasLoaded {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(store.lists) { list in
                    Button {
                        store.send(.listTapped(list))
                    } label: {
                        ListRow(list: list)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Lists")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.send(.refreshPulled).finish() }
        .task { store.send(.task) }
    }
}

private struct ListRow: View {
    let list: TwitterList

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TwitterIcon.lists.image
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .padding(11)
                .foregroundStyle(.white)
                .background(Color.twitterBlue, in: .rect(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(list.name)
                        .font(.body.weight(.bold))

                    if list.isPrivate {
                        TwitterIcon.lock.image
                            .resizable()
                            .scaledToFit()
                            .frame(width: 13, height: 13)
                            .accessibilityLabel("Private")
                    }
                }

                if !list.description.isEmpty {
                    Text(list.description)
                        .font(.subheadline)
                        .lineLimit(2)
                }

                Text("\(list.memberCount.formatted()) members")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
