import ComposableArchitecture
import Models
import SwiftUI
import TwitterUI

struct ProfileHeader: View {
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
                    // The ring is a background circle around a smaller avatar, so no
                    // stroke sits over the clipped image's antialiased edge.
                    Avatar(user: user, size: avatarSize - 8)
                        .opensInLightbox(
                            user.avatarMedia,
                            cornerRadius: (avatarSize - 8) / 2,
                            label: "Profile photo"
                        )
                        .padding(4)
                        .background(
                            .background,
                            in: .circle
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
                                    size: user.name == user.screenName
                                        ? metrics.size(.headline2) : metrics.bodySize + 7, weight: .bold)
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
            .fill(.twitterBlue.tertiary)
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
