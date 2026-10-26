import Dependencies
import Models
import Routing
import SwiftUI
import Synchronization
import TwitterClient
import TwitterDatabase
import TwitterUI
import UIKit

extension View {
    /// Long-pressing this view (an avatar) previews `user`'s profile with a menu to open, copy or share it; `open`
    /// runs for "View Profile" and for a tap on the preview.
    package func profilePreview(for user: User, open: @escaping () -> Void) -> some View {
        modifier(ProfilePreviewMenu(user: user, open: open))
    }
}

private struct ProfilePreviewMenu: ViewModifier {
    let user: User
    let open: () -> Void
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows

    func body(content: Content) -> some View {
        content.contextMenu {
            Button(action: open) {
                Label("View Profile", twitterIcon: .personStroke)
            }

            if supportsMultipleWindows {
                Button {
                    openWindow(value: Route.profile(user).window)
                } label: {
                    Label("Open in New Window", twitterIcon: .newWindow)
                }
            }

            Divider()

            Button {
                UIPasteboard.general.string = "@\(user.screenName)"
            } label: {
                Label("Copy Username", twitterIcon: .at)
            }

            if let url = user.profileURL {
                ShareLink(item: url)
            }
        } preview: {
            ProfilePreviewCard(user: user, screenName: user.screenName)
        }
    }
}

/// A profile at a glance: banner, avatar, name and badges, handle, the start of the bio, and follow counts.
/// `user` is `nil` while it loads, which draws the same layout redacted so the preview doesn't jump.
package struct ProfilePreviewCard: View {
    let user: User?
    let screenName: String

    package static let width: CGFloat = 320
    private static let avatarSize: CGFloat = 64
    private static let bannerHeight: CGFloat = width / 3

    package init(user: User?, screenName: String) {
        self.user = user
        self.screenName = screenName
    }

    package var body: some View {
        let avatarSize = ProfilePreviewCard.avatarSize
        VStack(alignment: .leading, spacing: 0) {
            RemoteImage(url: user?.bannerURL, pointSize: ProfilePreviewCard.width) {
                Rectangle().fill(.twitterDivider)
            }
            .frame(width: ProfilePreviewCard.width, height: ProfilePreviewCard.bannerHeight)
            .clipped()

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .bottom) {
                    avatar
                        .padding(3)
                        .background(.background, in: avatarShape(size: avatarSize + 6))

                    Spacer(minLength: 0)

                    if user?.followsViewer == true {
                        Text("Follows you")
                            .font(TweetMetrics.standard.font(.subtext3))
                            .foregroundStyle(.twitterSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.fill.tertiary, in: .rect(cornerRadius: 4))
                            .padding(.bottom, 4)
                    }
                }
                .padding(.top, -(avatarSize / 2 + 3))

                identity

                if let bio = user?.bio, !bio.isEmpty {
                    TweetText(links: [:], text: bio, font: TweetMetrics.standard.font(.subtext1))
                        .lineLimit(3)
                        .environment(\.postTextPreviewsEnabled, false)
                }

                counts
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(width: ProfilePreviewCard.width, alignment: .leading)
        .background(.background)
        .redacted(reason: user == nil ? .placeholder : [])
        .accessibilityElement(children: .combine)
    }

    private func avatarShape(size: CGFloat) -> RoundedRectangle {
        RoundedRectangle(
            cornerRadius: Avatar.cornerRadius(size: size, isSquare: user?.hasSquareAvatar == true))
    }

    @ViewBuilder private var avatar: some View {
        if let user {
            Avatar(user: user, size: ProfilePreviewCard.avatarSize)
        } else {
            Image("AvatarPlaceholder", bundle: .module)
                .resizable()
                .frame(width: ProfilePreviewCard.avatarSize, height: ProfilePreviewCard.avatarSize)
                .clipShape(avatarShape(size: ProfilePreviewCard.avatarSize))
        }
    }

    private var identity: some View {
        let metrics = TweetMetrics.standard
        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Text(user?.name ?? screenName)
                    .font(metrics.font(.headline2, weight: .bold))
                    .foregroundStyle(.twitterPrimary)
                    .lineLimit(1)

                if let badge = user?.verificationBadge {
                    VerificationBadgeView(badge: badge)
                        .imageScale(.small)
                }

                if let affiliate = user?.affiliate {
                    AffiliateBadge(label: affiliate, size: 16)
                }

                if user?.isProtected == true {
                    TwitterIcon.lock.image
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                        .foregroundStyle(.twitterPrimary)
                        .accessibilityLabel("Protected")
                }
            }

            Text(verbatim: "@\(screenName)")
                .font(metrics.font(.body))
                .foregroundStyle(.twitterSecondary)
                .lineLimit(1)
        }
    }

    private var counts: some View {
        let metrics = TweetMetrics.standard
        let following = user?.followingCount ?? 0
        let followers = user?.followersCount ?? 0
        return HStack(spacing: 16) {
            Text(
                "\(Text(following.compact).font(metrics.font(.subtext1, weight: .bold)).foregroundStyle(.twitterPrimary)) Following"
            )

            Text(
                "\(Text(followers.compact).font(metrics.font(.subtext1, weight: .bold)).foregroundStyle(.twitterPrimary)) Followers"
            )
        }
        .font(metrics.font(.subtext1))
        .foregroundStyle(.twitterSecondary)
        .lineLimit(1)
    }
}

/// A preview for a profile known only by its handle, such as a mention: a placeholder card until the account is
/// found, from memory, the on-disk cache, then the network.
struct LoadingProfilePreview: View {
    let screenName: String
    @State private var user: User?

    var body: some View {
        ProfilePreviewCard(user: user ?? ProfileLookup.remembered(screenName), screenName: screenName)
            .task(id: screenName) {
                if user == nil, let stored = await ProfileLookup.stored(screenName) {
                    user = stored
                }
                if let fresh = await ProfileLookup.fetch(screenName) {
                    withAnimation(.snappy) { user = fresh }
                }
            }
    }
}

/// Hosts ``LoadingProfilePreview`` as a context menu preview, sized to the card as it loads.
final class ProfilePreviewController: UIHostingController<LoadingProfilePreview> {
    init(screenName: String) {
        super.init(rootView: LoadingProfilePreview(screenName: screenName))
        sizingOptions = .preferredContentSize
        view.backgroundColor = .systemBackground
    }

    @available(*, unavailable)
    @MainActor required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Profiles looked up by handle for previews. Remembered in memory for the session; the database's user cache and
/// the network fill it.
package enum ProfileLookup {
    private static let memory = Mutex<[String: User]>([:])

    package static func remembered(_ screenName: String) -> User? {
        memory.withLock { $0[screenName.lowercased()] }
    }

    package static func remember(_ user: User) {
        memory.withLock { memory in
            if memory.count > 500 { memory.removeAll(keepingCapacity: true) }
            memory[user.screenName.lowercased()] = user
        }
    }

    /// From memory or the on-disk cache, without touching the network.
    @concurrent package static func stored(_ screenName: String) async -> User? {
        if let user = remembered(screenName) { return user }
        @Dependency(TimelineCache.self) var cache
        guard let user = try? await cache.user(screenName) else { return nil }
        remember(user)
        return user
    }

    /// From the network, saved for next time.
    @concurrent package static func fetch(_ screenName: String) async -> User? {
        @Dependency(TwitterClient.self) var client
        @Dependency(TimelineCache.self) var cache
        guard let user = try? await client.user(screenName) else { return nil }
        remember(user)
        try? await cache.saveUser(user)
        return user
    }
}

extension User {
    var profileURL: URL? { URL(string: "https://x.com/\(screenName)") }
}
