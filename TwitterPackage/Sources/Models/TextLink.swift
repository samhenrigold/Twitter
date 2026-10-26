import Foundation

/// A run of text that links out, in Unicode-scalar offsets of the text it belongs to (as ``TextStyleRange`` is):
/// where the API placed a link, so two links that show the same text stay apart and the same text elsewhere stays
/// plain.
package struct TextLink: Hashable, Codable, Sendable {
    package var range: Range<Int>
    package var url: URL

    package init(range: Range<Int>, url: URL) {
        self.range = range
        self.url = url
    }
}
