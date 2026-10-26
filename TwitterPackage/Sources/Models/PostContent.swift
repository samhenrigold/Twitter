import Foundation

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

package struct Poll: Hashable, Codable, Sendable {
    package struct Choice: Hashable, Codable, Sendable {
        package var label: String
        package var count: Int

        package init(label: String, count: Int) {
            self.label = label
            self.count = count
        }
    }

    package var choices: [Choice]
    package var endsAt: Date?
    package var countsAreFinal = false
    /// Zero-based index of the viewer's vote.
    package var selectedChoiceIndex: Int?
    package var imageURL: URL?
    /// The poll card (`card://…`) and its kind (`poll2choice_text_only`), which a vote names.
    package var cardURI: String?
    package var cardName: String?

    package init(
        choices: [Choice],
        endsAt: Date? = nil,
        countsAreFinal: Bool = false,
        selectedChoiceIndex: Int? = nil,
        imageURL: URL? = nil
    ) {
        self.choices = choices
        self.endsAt = endsAt
        self.countsAreFinal = countsAreFinal
        self.selectedChoiceIndex = selectedChoiceIndex
        self.imageURL = imageURL
    }

    package var totalVotes: Int { choices.reduce(0) { $0 + $1.count } }

    package func isFinal(now: Date) -> Bool {
        countsAreFinal || (endsAt.map { $0 <= now } ?? false)
    }

    /// Open, not voted in yet, and identifiable to vote in.
    package func canVote(now: Date) -> Bool {
        !isFinal(now: now) && selectedChoiceIndex == nil && cardURI != nil && cardName != nil
    }

    package func fraction(of choice: Choice) -> Double {
        totalVotes > 0 ? Double(choice.count) / Double(totalVotes) : 0
    }

    /// The highest vote count; every choice with it is leading.
    package var highestCount: Int { choices.map(\.count).max() ?? 0 }
}

/// Who may reply to a post when its author limited replies.
package struct ReplyRestriction: Hashable, Codable, Sendable {
    package enum Policy: String, Hashable, Codable, Sendable {
        case mentioned
        case following
        case verified
        case subscribers
        case other
    }

    package var policy: Policy
    package var ownerScreenName: String?
    package var viewerCanReply: Bool
    /// Twitter's own wording, used for policies the app doesn't know.
    package var prompt: String?

    package init(policy: Policy, ownerScreenName: String? = nil, viewerCanReply: Bool, prompt: String? = nil) {
        self.policy = policy
        self.ownerScreenName = ownerScreenName
        self.viewerCanReply = viewerCanReply
        self.prompt = prompt
    }

    package var message: String {
        let owner = ownerScreenName.map { "@\($0)" }
        switch policy {
        case .mentioned:
            return owner.map { "People \($0) mentioned can reply" } ?? "Only people mentioned can reply"
        case .following:
            return owner.map { "Accounts \($0) follows can reply" } ?? "Only accounts the author follows can reply"
        case .verified:
            return "Only verified accounts can reply"
        case .subscribers:
            return owner.map { "Only \($0)'s subscribers can reply" } ?? "Only subscribers can reply"
        case .other:
            return prompt ?? "Replies to this Tweet are limited"
        }
    }
}

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

package enum VerificationBadge: Hashable, Sendable {
    case blue
    case business
    case government
}

extension User {
    package var verificationBadge: VerificationBadge? {
        switch verifiedType?.lowercased() {
        case "business": .business
        case "government": .government
        default: isVerified ? .blue : nil
        }
    }
}

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
