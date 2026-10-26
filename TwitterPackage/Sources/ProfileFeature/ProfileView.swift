import ComposableArchitecture
import FeedFeature
import Models
import Routing
import SwiftUI
import TwitterClient
import TwitterUI

package struct ProfileView: View {
    let store: StoreOf<ProfileFeature>
    @Environment(\.columnBarItemsInVerticalBar) private var columnBarItemsInVerticalBar

    package init(store: StoreOf<ProfileFeature>) {
        self.store = store
    }

    package var body: some View {
        Group {
            if let user = store.user, user.blocksViewer || (user.isBlocking && !store.isShowingBlockedPosts) {
                BlockedProfile(user: user, store: store)
            } else if let feedsStore = store.scope(state: \.feeds, action: \.feeds), let user = store.user {
                FeedsView(store: feedsStore) {
                    ProfileHeader(user: user, isViewer: store.isViewer, store: store)
                }
            } else if let errorMessage = store.errorMessage {
                ContentUnavailableView {
                    Label("Couldn't load @\(store.screenName)", twitterIcon: .warningStroke)
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try Again") { store.send(.task) }
                        .buttonStyle(.bordered)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(store.user?.name ?? "@\(store.screenName)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if store.hasMenu {
                ColumnMenuToolbarItem("Account", isInVerticalBar: columnBarItemsInVerticalBar) {
                    ProfileMenuItems(store: store)
                }
            }
        }
        .task { store.send(.task) }
    }
}

/// A profile's "…" menu: the viewer's own account settings, or blocking someone else.
package struct ProfileMenuItems: View {
    let store: StoreOf<ProfileFeature>

    package init(store: StoreOf<ProfileFeature>) {
        self.store = store
    }

    package var body: some View {
        Button("Lists", twitterIcon: .lists) {
            store.send(.listsButtonTapped)
        }

        if let url = store.user?.profileURL {
            ShareLink(item: url) {
                Label("Share Profile", twitterIcon: .shareStroke)
            }

            Button("Copy Link to Profile", twitterIcon: .link) {
                UIPasteboard.general.url = url
            }
        }

        Divider()

        if store.isViewer {
            PostRowStylePicker()

            Divider()

            Button("Sign Out", twitterIcon: .signOut, role: .destructive) {
                store.send(.signOutButtonTapped)
            }
        } else if let user = store.user {
            Button(
                user.isMuting ? "Unmute @\(user.screenName)" : "Mute @\(user.screenName)",
                twitterIcon: user.isMuting ? .unmute : .mute
            ) {
                store.send(.muteButtonTapped)
            }

            Button(
                user.isBlocking ? "Unblock @\(user.screenName)" : "Block @\(user.screenName)",
                twitterIcon: .block,
                role: user.isBlocking ? nil : .destructive
            ) {
                store.send(.blockButtonTapped)
            }
        }
    }
}

extension ProfileFeature.State {
    /// Whether ``ProfileMenuItems`` has anything to offer yet.
    package var hasMenu: Bool { isViewer || user != nil }
}

/// The header alone, over a notice in place of the posts: someone the viewer blocked, or who blocked the viewer.
private struct BlockedProfile: View {
    let user: User
    let store: StoreOf<ProfileFeature>

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ProfileHeader(user: user, isViewer: false, store: store)

                Divider()

                if user.blocksViewer {
                    ContentUnavailableView {
                        Label("You're blocked", twitterIcon: .block)
                    } description: {
                        Text("You can't follow or see @\(user.screenName)'s Tweets.")
                    }
                } else {
                    ContentUnavailableView {
                        Label("You blocked @\(user.screenName)", twitterIcon: .block)
                    } description: {
                        Text(
                            "Are you sure you want to view these Tweets? Viewing Tweets won't unblock @\(user.screenName)."
                        )
                    } actions: {
                        Button("View Tweets") { store.send(.viewPostsButtonTapped) }
                            .buttonStyle(.bordered)
                    }
                }
            }
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct ProfileHeader: View {
    let user: User
    let isViewer: Bool
    let store: StoreOf<ProfileFeature>
    @Environment(\.tweetMetrics) private var metrics

    /// `_t1_standardAvatarSize`: an 88 pt container whose 4 pt background-coloured ring leaves an 80 pt image.
    private let avatarSize: CGFloat = 88

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Either picture opens full screen on a tap, and previews with its menu on a long press.
            Banner(url: user.bannerURL)
                .opensInLightbox(user.bannerMedia, cornerRadius: 0, label: "Header photo")
                .overlay(alignment: .bottomLeading) {
                    // The ring is a background around a smaller avatar, in the avatar's own shape, so no
                    // stroke sits over the clipped image's antialiased edge.
                    Avatar(user: user, size: avatarSize - 8)
                        .opensInLightbox(
                            user.avatarMedia,
                            cornerRadius: Avatar.cornerRadius(size: avatarSize - 8, isSquare: user.hasSquareAvatar),
                            label: "Profile photo"
                        )
                        .padding(4)
                        .background(
                            .background,
                            in: RoundedRectangle(
                                cornerRadius: Avatar.cornerRadius(size: avatarSize - 8, isSquare: user.hasSquareAvatar)
                                    + 4
                            )
                        )
                        .alignmentGuide(.bottom) { $0[VerticalAlignment.center] }
                        .padding(.leading, 16)
                }
                .padding(.bottom, avatarSize / 2)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        // `contentFont + 7`, or headline size when the name is just the handle.
                        Text(user.name)
                            .font(
                                TwitterFont.font(
                                    size: user.name == user.screenName ? 17 : metrics.bodySize + 7, weight: .bold)
                            )
                            .foregroundStyle(.twitterPrimary)

                        if let badge = user.verificationBadge {
                            VerificationBadgeView(badge: badge)
                        }

                        if let affiliate = user.affiliate {
                            AffiliateBadge(label: affiliate, size: 20)
                        }
                    }

                    HStack(spacing: 6) {
                        Text(verbatim: "@\(user.screenName)")
                            .font(metrics.font(.body))
                            .foregroundStyle(.twitterSecondary)

                        if user.followsViewer {
                            Text("Follows you")
                                .font(metrics.font(.subtext3))
                                .foregroundStyle(.twitterSecondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: .rect(cornerRadius: 4))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !isViewer {
                    if user.isBlocking {
                        Button("Unblock") { store.send(.blockButtonTapped) }
                            .buttonStyle(.bordered)
                    } else if !user.blocksViewer {
                        FollowButton(isFollowing: user.isFollowing) { store.send(.followButtonTapped) }
                    }
                }
            }
            .padding(.horizontal, 16)

            if !user.bio.isEmpty {
                // Links, mentions and hashtags, as in a post; any Markdown punctuation stays as typed.
                TweetText(links: [:], text: user.bio, font: metrics.font(.body))
                    .lineSpacing(metrics.lineSpacing(for: .body))
                    .foregroundStyle(.twitterPrimary)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            ProfileDetails(user: user)
                .padding(.horizontal, 16)

            HStack(spacing: 16) {
                Button {
                    store.send(.followingButtonTapped)
                } label: {
                    ProfileCount(count: user.followingCount, label: "Following")
                }

                Button {
                    store.send(.followersButtonTapped)
                } label: {
                    ProfileCount(count: user.followersCount, label: "Followers")
                }
            }
            .buttonStyle(.plain)
            .font(metrics.font(.subtext1))
            .foregroundStyle(.twitterSecondary)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }
}

/// "**123** Following": the number bold in the primary colour.
private struct ProfileCount: View {
    let count: Int
    let label: LocalizedStringKey
    @Environment(\.tweetMetrics) private var metrics

    var body: some View {
        Text(
            "\(Text(count.compact).font(metrics.font(.subtext1, weight: .bold)).foregroundStyle(.twitterPrimary)) \(Text(label))"
        )
    }
}

/// 3:1 in portrait, 4:1 when the height is compact.
private struct Banner: View {
    let url: URL?
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        Rectangle()
            .fill(.tint.opacity(0.25))
            .overlay {
                if let url {
                    RemoteImage(url: url, pointSize: 800) {
                        Color.clear
                    }
                }
            }
            .aspectRatio(verticalSizeClass == .compact ? 4 : 3, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipped()
            .accessibilityHidden(true)
    }
}

private struct ProfileDetails: View {
    let user: User
    @Environment(\.tweetMetrics) private var metrics

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { ProfileDetailItems(user: user) }

            VStack(alignment: .leading, spacing: 4) { ProfileDetailItems(user: user) }
        }
        .font(metrics.font(.subtext1))
        .foregroundStyle(.twitterSecondary)
        .tint(.twitterBlue)
    }

}

private struct ProfileDetailItems: View {
    let user: User

    var body: some View {
        if !user.location.isEmpty {
            Label(user.location, twitterIcon: .locationStroke)
        }

        if let website = user.website, let url = user.websiteURL {
            Link(destination: url) {
                Label(website, twitterIcon: .link)
            }
        }

        if let joined = user.joined {
            Label("Joined \(joined.formatted(.dateTime.month(.wide).year()))", twitterIcon: .calendar)
        }
    }
}
