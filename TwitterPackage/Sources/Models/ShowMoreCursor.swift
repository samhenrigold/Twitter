/// A "Show more replies" row standing in for a page of a conversation that hasn't loaded yet.
package struct ShowMoreCursor: Identifiable, Hashable, Codable, Sendable {
    package var id: String
    package var cursor: String
    package var label: String

    package init(id: String, cursor: String, label: String = "Show more replies") {
        self.id = id
        self.cursor = cursor
        self.label = label
    }
}
