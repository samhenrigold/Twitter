import Testing

extension Tag {
    /// Entity and Markdown parsing.
    @Tag static var parser: Self
    /// The attributed string the typesetter builds from parsed pieces.
    @Tag static var typesetting: Self
    /// Cases whose expected values come from Twitter's API rather than from us.
    @Tag static var apiOracle: Self
    /// twitter-text's conformance suite, whose expected values come from Twitter's own libraries.
    @Tag static var conformance: Self
}
