import ComposableArchitecture
import Models
import Routing
import SwiftUI
import TwitterClient
import TwitterUI

/// A column of people, each row laid out like a timeline row: avatar, name and badges over the handle, the start of
/// the bio, and a follow button at the trailing edge. Pull to refresh; the next page loads as the end comes into view.
package struct UserListView: View {
    let store: StoreOf<UserListFeature>

    package init(store: StoreOf<UserListFeature>) {
        self.store = store
    }

    package var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(store.users) { user in
                    UserRow(user: user, store: store)
                        .onAppear { store.send(.rowAppeared(user.id)) }
                }

                UserListFooter(store: store)
            }
            // Caps line length for reading, as timelines do, while the scroll view spans the column.
            .frame(maxWidth: .infinity)
            .frame(maxWidth: 680)
            .tweetMetrics()
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(store.source.title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            ClassicSound.psst2.play()
            await store.send(.refreshPulled).finish()
            ClassicSound.pop.play()
        }
        .task { store.send(.task) }
    }
}

private struct UserRow: View {
    let user: User
    let store: StoreOf<UserListFeature>
    @Environment(\.tweetMetrics) private var metrics
    @SharedReader(.viewer) private var viewer

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: metrics.gutter) {
                Avatar(user: user, size: metrics.avatarSize)
                    .profilePreview(for: user) { store.send(.userTapped(user)) }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            AuthorLine(user: user, date: nil, layout: .stacked)

                            if user.followsViewer {
                                FollowsYouLabel()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if user.id != viewer?.id, !user.isBlocking, !user.blocksViewer {
                            FollowButton(isFollowing: user.isFollowing) {
                                store.send(.followButtonTapped(user.id))
                            }
                        }
                    }

                    if !user.bio.isEmpty {
                        Text(user.bio)
                            .font(metrics.font(.body))
                            .lineSpacing(metrics.lineSpacing(for: .body))
                            .foregroundStyle(.twitterPrimary)
                            .lineLimit(2)
                    }
                }
            }
            .padding(.horizontal, metrics.sideInset)
            .padding(.vertical, metrics.topInset)
            // Opaque, so the row lifted for its avatar's preview isn't see-through.
            .background(.background)
            .contentShape(.rect)
            .onTapGesture { store.send(.userTapped(user)) }
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "View Profile") { store.send(.userTapped(user)) }

            TwitterDivider()
        }
    }
}

/// "Follows you", in the small gray capsule Twitter puts beside the handle.
private struct FollowsYouLabel: View {
    @Environment(\.tweetMetrics) private var metrics

    var body: some View {
        Text("Follows you")
            .font(metrics.font(.subtext2))
            .foregroundStyle(.twitterSecondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.twitterSecondary.opacity(0.12), in: .rect(cornerRadius: 3))
    }
}

/// Loading, empty, failed and finished states under the rows, as a timeline's footer.
private struct UserListFooter: View {
    let store: StoreOf<UserListFeature>

    var body: some View {
        Group {
            if let errorMessage = store.errorMessage {
                ContentUnavailableView {
                    Label("Couldn't load people", twitterIcon: .warningStroke)
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try Again") { store.send(.retryButtonTapped) }
                        .buttonStyle(.bordered)
                }
            } else if store.isLoading {
                ProgressView()
                    .padding(.vertical, 32)
            } else if store.hasLoaded, store.users.isEmpty {
                ContentUnavailableView(store.source.emptyTitle, twitterIcon: .communitiesStroke)
            } else if store.hasLoaded, store.bottomCursor == nil {
                EndOfTimeline()
            }
        }
        .frame(maxWidth: .infinity)
    }
}

extension UserListSource {
    fileprivate var emptyTitle: LocalizedStringKey {
        switch self {
        case .followers: "No followers yet"
        case .following: "Not following anyone yet"
        case .likers: "No likes to show"
        case .reposters: "No Retweets yet"
        }
    }
}

#Preview {
    NavigationStack {
        UserListView(
            store: Store(initialState: UserListFeature.State(source: .followers(userID: User.mock.id))) {
                UserListFeature()
            } withDependencies: {
                $0[TwitterClient.self] = .previewValue
            }
        )
    }
}
