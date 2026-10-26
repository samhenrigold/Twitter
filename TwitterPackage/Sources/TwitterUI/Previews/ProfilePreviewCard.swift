import Models
import SwiftUI

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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.legibilityWeight) private var legibilityWeight

    /// A timeline's type at 15 pt, following Dynamic Type and Bold Text: a context menu preview is hosted on its own,
    /// outside any column's ``SwiftUI/View/tweetMetrics()``.
    private var metrics: TweetMetrics {
        TweetMetrics(
            bodySize: TweetMetrics.standard.bodySize + TweetMetrics.offset(for: dynamicTypeSize),
            isBoldText: legibilityWeight == .bold
        )
    }

    package var body: some View {
        let avatarSize = ProfilePreviewCard.avatarSize
        let metrics = metrics
        VStack(alignment: .leading, spacing: 0) {
            RemoteImage(url: user?.bannerURL, pointSize: ProfilePreviewCard.width) {
                Rectangle().fill(.twitterDivider)
            }
            .frame(width: ProfilePreviewCard.width, height: ProfilePreviewCard.bannerHeight)
            .clipped()

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .bottom) {
                    ProfilePreviewAvatar(user: user, size: avatarSize)
                        .padding(3)
                        .background(.background, in: .circle)

                    Spacer(minLength: 0)

                    if user?.followsViewer == true {
                        Text("Follows you")
                            .font(metrics.font(.subtext3))
                            .foregroundStyle(.twitterSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.fill.tertiary, in: .rect(cornerRadius: 4))
                            .padding(.bottom, 4)
                    }
                }
                .padding(.top, -(avatarSize / 2 + 3))

                ProfilePreviewIdentity(user: user, screenName: screenName)

                if let bio = user?.bio, !bio.isEmpty {
                    TweetText(links: [:], text: bio, font: metrics.font(.subtext1))
                        .lineLimit(3)
                        .environment(\.postTextPreviewsEnabled, false)
                }

                ProfilePreviewCounts(user: user)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(width: ProfilePreviewCard.width, alignment: .leading)
        .background(.background)
        .redacted(reason: user == nil ? .placeholder : [])
        .accessibilityElement(children: .combine)
        .environment(\.tweetMetrics, metrics)
    }
}

/// The avatar, or the placeholder while the profile loads.
private struct ProfilePreviewAvatar: View {
    let user: User?
    let size: CGFloat

    var body: some View {
        if let user {
            Avatar(user: user, size: size)
        } else {
            Image("AvatarPlaceholder", bundle: .module)
                .resizable()
                .frame(width: size, height: size)
                .clipShape(.circle)
        }
    }
}

/// Name and badges over the handle.
private struct ProfilePreviewIdentity: View {
    let user: User?
    let screenName: String
    @Environment(\.tweetMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
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
}

/// Following and follower counts.
private struct ProfilePreviewCounts: View {
    let user: User?
    @Environment(\.tweetMetrics) private var metrics

    var body: some View {
        let following = user?.followingCount ?? 0
        let followers = user?.followersCount ?? 0
        HStack(spacing: 16) {
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
