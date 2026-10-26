import Models
import SwiftUI

/// A poll: its choices to vote for while it's open and you haven't, its current or final results otherwise.
package struct PollView: View {
    let poll: Poll
    let vote: ((Int) -> Void)?

    package init(poll: Poll, vote: ((Int) -> Void)? = nil) {
        self.poll = poll
        self.vote = vote
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let imageURL = poll.imageURL {
                RemoteImage(url: imageURL, pointSize: 600)
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
                    .clipShape(.rect(cornerRadius: 12))
                    .allowsHitTesting(false)
            }

            // X rejects duplicate choices, so the label is a stable identity.
            ForEach(poll.choices.enumerated(), id: \.element.label) { index, choice in
                if let vote, poll.canVote(now: .now) {
                    // Twitter's outlined choices, before you've voted.
                    Button {
                        vote(index)
                    } label: {
                        Text(choice.label)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(.accentColor)
                } else {
                    PollChoiceRow(
                        choice: choice,
                        fraction: poll.fraction(of: choice),
                        hasMostVotes: choice.count > 0 && choice.count == poll.highestCount,
                        isSelected: poll.selectedChoiceIndex == index
                    )
                }
            }

            PollSummary(poll: poll)
        }
    }
}

private struct PollChoiceRow: View {
    let choice: Poll.Choice
    let fraction: Double
    let hasMostVotes: Bool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Text(choice.label)
                    .fontWeight(hasMostVotes ? .semibold : .regular)
                    .lineLimit(2)

                if isSelected {
                    TwitterIcon.checkmarkCircle.image
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Your vote")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                .fontWeight(hasMostVotes ? .semibold : .regular)
                .monospacedDigit()
        }
        .font(.subheadline)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(alignment: .leading) {
            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 8)
                    .fill(hasMostVotes ? AnyShapeStyle(.tint.opacity(0.3)) : AnyShapeStyle(.fill.tertiary))
                    .frame(width: max(proxy.size.width * fraction, 4))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PollSummary: View {
    let poll: Poll

    var body: some View {
        Text(summary)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private var summary: String {
        let votes = poll.totalVotes == 1 ? "1 vote" : "\(poll.totalVotes.formatted()) votes"
        let now = Date.now
        if poll.isFinal(now: now) { return "\(votes) · Final results" }
        guard let endsAt = poll.endsAt else { return votes }
        let remaining = Duration.seconds(max(endsAt.timeIntervalSince(now), 60))
        let left = remaining.formatted(.units(allowed: [.days, .hours, .minutes], width: .wide, maximumUnitCount: 1))
        return "\(votes) · \(left) left"
    }
}
