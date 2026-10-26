/// A post Twitter won't show: deleted, withheld, from a suspended or protected account.
package struct Tombstone: Identifiable, Hashable, Codable, Sendable {
    /// Why Twitter withheld a post when it gave a reason code instead of its own wording.
    package enum Reason: String, Hashable, Codable, Sendable {
        case suspended
        case protected
        case sensitive
        case unavailable
    }

    package var id: String
    /// Twitter's own wording, tidied up. `nil` when Twitter sent only a ``reason``.
    package var text: String?
    /// Set when Twitter sent a reason code (or nothing) rather than text; the view layer words it.
    package var reason: Reason?

    package init(id: String, text: String) {
        self.id = id
        self.text = text
        self.reason = nil
    }

    package init(id: String, reason: Reason) {
        self.id = id
        self.text = nil
        self.reason = reason
    }
}
