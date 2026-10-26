import Foundation

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
