import Models
import SwiftUI

/// A muted stand-in for a post Twitter won't show.
package struct TombstoneView: View {
    let tombstone: Tombstone

    package init(tombstone: Tombstone) {
        self.tombstone = tombstone
    }

    package var body: some View {
        Text(tombstone.displayText)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.fill.quaternary, in: .rect(cornerRadius: 12))
    }
}

extension Tombstone {
    /// Twitter's own wording when it sent some, otherwise the app's wording for the reason.
    package var displayText: String {
        if let text { return text }
        switch reason {
        case .suspended: return "This Tweet is from a suspended account."
        case .protected: return "This Tweet is from an account that limits who can view their Tweets."
        case .sensitive: return "This Tweet may contain sensitive content."
        case .unavailable, nil: return "This Tweet is unavailable."
        }
    }
}
