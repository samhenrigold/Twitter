import Models
import Routing
import SwiftUI

package struct QuoteCard: View {
    let tweet: Tweet
    let action: () -> Void
    @Environment(\.tweetMetrics) private var metrics

    package init(tweet: Tweet, action: @escaping () -> Void) {
        self.tweet = tweet
        self.action = action
    }

    package var body: some View {
        let unit = metrics.unit
        ZStack {
            VStack(alignment: .leading, spacing: 4 * unit) {
                HStack(spacing: 4 * unit) {
                    Avatar(user: tweet.author, size: metrics.quoteAvatarSize)

                    AuthorLine(user: tweet.author, date: tweet.createdAt)
                }

                if !tweet.text.isEmpty {
                    // `ios_ui_quoted_tweet_custom_max_text_lines`.
                    // The card is one button: its text is styled like a post's, but taps open the quoted post.
                    TweetText(tweet: tweet)
                        .lineLimit(5)
                        .environment(\.postTextPreviewsEnabled, false)
                        .allowsHitTesting(false)
                }

                if !tweet.media.isEmpty {
                    MediaGrid(media: tweet.media, maxHeight: 180, tweet: tweet)
                        .padding(.top, 4 * unit)
                }
            }
            // Quoted-post insets are 12u on three sides and 4u at the bottom; the extra 8u keeps text-only cards
            // from crowding their border.
            .padding(.top, 12 * unit)
            .padding(.horizontal, 12 * unit)
            .padding(.bottom, 4 * unit + 8 * unit)
            .background(.background, in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.twitterDivider)
            }
            .contentShape(.rect)
            // Lifted for a context menu as the card it is, not a square cut out of the row.
            .contentShape(.contextMenuPreview, .rect(cornerRadius: 12))
        }
        // A tap gesture rather than a `Button`, which would claim the touch as it lands and shut out the column strip's
        // swipe (see `MediaTile`).
        .onTapGesture(perform: action)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// A link's preview card. Long-pressing it lifts the card with Twitter's link menu (as `T1WebCardView` and
/// `T1XLinkViewController` do): open it, in a window of its own or in Safari, copy it or share it.
package struct LinkCardView: View {
    let card: LinkCard
    @Environment(\.openURL) private var openURL
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows

    package init(card: LinkCard) {
        self.card = card
    }

    package var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                if let imageURL = card.imageURL {
                    RemoteImage(url: imageURL, pointSize: 600)
                        .frame(maxWidth: .infinity)
                        .frame(height: 160)
                        .clipped()
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(card.domain)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(card.title)
                        .font(.subheadline)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .clipShape(.rect(cornerRadius: 12))
            .contentShape(.rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.twitterDivider)
            }
            .contentShape(.contextMenuPreview, .rect(cornerRadius: 12))
        }
        // A tap gesture rather than a `Link`, which would claim the touch as it lands and shut out the column strip's
        // swipe (see `MediaTile`).
        .onTapGesture { openURL(card.url) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isLink)
        .contextMenu {
            Button {
                openURL(card.url)
            } label: {
                Label("Open Link", twitterIcon: .externalLinkStroke)
            }

            if supportsMultipleWindows, let route = Route.forLink(card.url) {
                Button {
                    openWindow(value: route.window)
                } label: {
                    Label("Open in New Window", twitterIcon: .newWindow)
                }
            }

            Button {
                UIApplication.shared.open(card.url)
            } label: {
                Label("Open in Safari", twitterIcon: .globe)
            }

            Divider()

            Button {
                UIPasteboard.general.url = card.url
            } label: {
                Label("Copy Link", twitterIcon: .link)
            }

            ShareLink(item: card.url)
        }
    }
}
