/// A URL, mention, hashtag or cashtag twitter-text found, and where.
package struct TwitterTextEntity: Hashable, Sendable {
    package enum Kind: Hashable, Sendable {
        /// The URL as written, scheme or not.
        case url(String)
        /// A screen name without its `@`, and the list after it (`@name/slug`), without its `/`.
        case mention(screenName: String, listSlug: String?)
        /// The tag without its `#`.
        case hashtag(String)
        /// The symbol without its `$`.
        case cashtag(String)
    }

    package var kind: Kind
    /// Where it is in the text it came from, `@`, `#` or `$` included. The bounds fall on Unicode-scalar boundaries,
    /// which may be inside a character.
    package var range: Range<String.Index>

    package init(_ kind: Kind, range: Range<String.Index>) {
        self.kind = kind
        self.range = range
    }
}
