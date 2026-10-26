import Foundation

/// The small organization badge shown next to an affiliated account's name.
package struct AffiliateLabel: Hashable, Codable, Sendable {
    package var description: String
    package var badgeURL: URL?
    package var url: URL?

    package init(description: String, badgeURL: URL? = nil, url: URL? = nil) {
        self.description = description
        self.badgeURL = badgeURL
        self.url = url
    }
}
