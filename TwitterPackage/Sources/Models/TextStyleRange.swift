/// Bold or italic styling over a range of a post's text, in Unicode-scalar offsets.
package struct TextStyleRange: Hashable, Codable, Sendable {
    package var range: Range<Int>
    package var isBold = false
    package var isItalic = false

    package init(range: Range<Int>, isBold: Bool = false, isItalic: Bool = false) {
        self.range = range
        self.isBold = isBold
        self.isItalic = isItalic
    }
}
