import RegexBuilder

/// `validGTLD` and `validCCTLD`: one of ``TopLevelDomains``, not followed by a character that would make it part of a
/// longer word (an ASCII letter or digit, `@`, `+` or `-`). The longest that fits wins, as `com` beats `co` in the
/// original's reverse-alphabetical alternation.
///
/// A consuming component rather than a 1,500-way alternation, which a backtracking engine would try name by name at
/// every dot. It never backtracks into itself, and needn't: everything after a domain is optional.
struct TopLevelDomain: CustomConsumingRegexComponent {
    typealias RegexOutput = Substring

    func consuming(
        _ input: String, startingAt index: String.Index, in bounds: Range<String.Index>
    ) throws -> (upperBound: String.Index, output: Substring)? {
        let scalars = input.unicodeScalars
        var end = index
        var length = 0
        while end < bounds.upperBound, length < TopLevelDomains.longest,
            TwitterTextPatterns.URLPattern.domainCharacter.contains(scalars[end])
        {
            end = scalars.index(after: end)
            length += 1
        }
        while end > index {
            if !(end < bounds.upperBound && Self.wordContinuation.contains(scalars[end])),
                TopLevelDomains.contains(scalars[index..<end])
            {
                return (end, input[index..<end])
            }
            end = scalars.index(before: end)
        }
        return nil
    }

    private static let wordContinuation = TwitterTextPatterns.asciiAlphanumerics.union(ScalarSet("@+-"))
}
