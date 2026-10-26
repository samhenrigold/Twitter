import ComposableArchitecture
import Foundation
import Models

/// A Tweet kept to finish later: its text, and what it replies to or quotes. Attachments aren't kept.
package struct SavedDraft: Codable, Equatable, Identifiable, Sendable {
    package let id: UUID
    package var text: String
    package var replyingTo: Tweet?
    package var quoting: Tweet?
    package var savedAt: Date
}

extension SharedKey where Self == FileStorageKey<IdentifiedArrayOf<SavedDraft>>.Default {
    /// Drafts, kept on disk, newest first.
    package static var drafts: Self {
        Self[.fileStorage(.applicationSupportDirectory.appending(component: "drafts.json")), default: []]
    }
}
