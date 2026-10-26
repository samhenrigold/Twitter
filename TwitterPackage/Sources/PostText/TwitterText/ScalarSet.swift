import RegexBuilder

/// A set of Unicode scalars, and a regex component that matches one of them.
///
/// twitter-text's classes are code-point ranges, many bounded by letters with canonical decompositions (`À`, `Ḁ`), and
/// Swift's `Regex` rejects those as range bounds: it compares characters canonically. A set of scalar values says
/// what twitter-text means, can be tested outside a pattern, and is `Sendable`, which `CharacterClass` isn't.
struct ScalarSet: CustomConsumingRegexComponent, Hashable, Sendable {
    typealias RegexOutput = Substring

    private var ranges: [ClosedRange<UInt32>]
    private var isInverted = false

    init(_ ranges: ClosedRange<Unicode.Scalar>...) {
        self.ranges = ranges.map { $0.lowerBound.value...$0.upperBound.value }
    }

    /// Each scalar of `scalars`, on its own (a string literal would join a mark onto the character before it).
    init(_ scalars: String) {
        ranges = scalars.unicodeScalars.map { $0.value...$0.value }
    }

    func contains(_ scalar: Unicode.Scalar) -> Bool {
        ranges.contains { $0.contains(scalar.value) } != isInverted
    }

    /// Scalars in either set. Neither may be inverted.
    func union(_ other: ScalarSet) -> ScalarSet {
        precondition(!isInverted && !other.isInverted, "A union of inverted sets isn't a list of ranges")
        var union = self
        union.ranges += other.ranges
        return union
    }

    /// Every scalar this set doesn't hold.
    var inverted: ScalarSet {
        var inverted = self
        inverted.isInverted.toggle()
        return inverted
    }

    func consuming(
        _ input: String, startingAt index: String.Index, in bounds: Range<String.Index>
    ) throws -> (upperBound: String.Index, output: Substring)? {
        guard index < bounds.upperBound, contains(input.unicodeScalars[index]) else { return nil }
        let next = input.unicodeScalars.index(after: index)
        return (next, input[index..<next])
    }
}
