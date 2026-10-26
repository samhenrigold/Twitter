import Foundation

/// A "Readers added context" note attached to a post.
package struct CommunityNote: Hashable, Codable, Sendable {
    package var id: String?
    package var title: String
    package var shortTitle: String?
    package var text: String
    /// Substring of `text` → destination, for the links inside the note.
    package var links: [String: URL] = [:]
    package var footer: String?
    package var destinationURL: URL?

    package init(
        id: String? = nil,
        title: String,
        shortTitle: String? = nil,
        text: String,
        links: [String: URL] = [:],
        footer: String? = nil,
        destinationURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.shortTitle = shortTitle
        self.text = text
        self.links = links
        self.footer = footer
        self.destinationURL = destinationURL
    }
}
