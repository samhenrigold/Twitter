import Models
import PostText
import SwiftUI

/// Post text: links, mentions, hashtags, cashtags and Twitter's bold/italic, typeset by ``PostTextTypesetter``.
///
/// The first frame draws from the typesetter's cache, or typesets inline when the text is short; long text draws as
/// plain text in the same font (so the row doesn't change height) while it typesets off the main actor, then swaps in
/// without animation. Long-pressing a mention, tag or link previews it (see ``PostTextPreviews``).
package struct TweetText: View {
    let input: PostTextInput
    /// Overrides the metrics' type ramp; `nil` draws `style` in Chirp at Twitter's line height.
    var font: Font?
    var style: TwitterTextStyle = .body
    @State private var prepared: TypesetPostText?
    @Environment(\.tweetMetrics) private var metrics

    /// Free text with its links (community notes, bios), read like a post: Markdown punctuation stays literal.
    package init(links: [String: URL], text: String, font: Font? = nil) {
        input = PostTextInput(text: text, links: links)
        self.font = font
    }

    /// The input a timeline row typesets for a post (cut to the timeline limit when it's long), so a feed can prepare
    /// it off the main actor before the row appears.
    nonisolated package static func timelineInput(for tweet: Tweet) -> PostTextInput {
        let isTruncated = PostTextInput.needsTruncation(tweet.text, limit: timelineCharacterLimit)
        return PostTextInput(
            text: tweet.text,
            links: tweet.links,
            tags: tweet.hashtags + tweet.cashtags,
            styles: tweet.styles,
            characterLimit: isTruncated ? timelineCharacterLimit : nil
        )
    }

    /// A post's text with its bold/italic styling and recognized hashtags and cashtags, cut to `characterLimit` when
    /// given (see ``truncated(_:limit:)``).
    package init(
        tweet: Tweet, style: TwitterTextStyle = .body, font: Font? = nil, characterLimit: Int? = nil
    ) {
        input = PostTextInput(
            text: tweet.text,
            links: tweet.links,
            tags: tweet.hashtags + tweet.cashtags,
            styles: tweet.styles,
            characterLimit: characterLimit
        )
        self.font = font
        self.style = style
    }

    package var body: some View {
        let typeset = prepared?.input == input ? prepared : PostTextTypesetter.cachedOrInline(input)
        Group {
            if let typeset {
                Text(entitiesTaggedIn: typeset)
                    .modifier(PostTextPreviews(typeset: typeset))
            } else {
                Text(verbatim: input.placeholderText)
                    .task(id: input) {
                        let result = await PostTextTypesetter.prepare(input)
                        // A recycled row may have moved on to another post while this one typeset.
                        guard !Task.isCancelled, result.input == input else { return }
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) { prepared = result }
                    }
            }
        }
        .font(font ?? metrics.font(style))
        .lineSpacing(font == nil ? metrics.lineSpacing(for: style) : 0)
        .foregroundStyle(.twitterPrimary)
        .tint(.twitterBlue)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Timeline rows show this many characters of a long post before "Show more".
    nonisolated package static let timelineCharacterLimit = 280

    /// `text` cut at a word boundary near `limit` with an ellipsis, or `nil` when it already fits.
    package static func truncated(_ text: String, limit: Int) -> String? {
        PostTextInput.truncated(text, limit: limit)
    }
}
