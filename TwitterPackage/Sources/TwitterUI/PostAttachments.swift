import Dependencies
import ImagePipeline
import Models
import SwiftUI

/// The check next to a verified name: blue for subscribers, gold for businesses, gray for governments.
package struct VerificationBadgeView: View {
    let badge: VerificationBadge

    package init(badge: VerificationBadge) {
        self.badge = badge
    }

    package var body: some View {
        // Twitter's badge, in the account's color, sized to the name it follows.
        TwitterIcon.verified.image
            .resizable()
            .scaledToFit()
            .frame(width: 16, height: 16)
            .foregroundStyle(color)
            .accessibilityLabel(label)
    }

    private var color: AnyShapeStyle {
        switch badge {
        case .blue: AnyShapeStyle(Color.twitterBlue)
        case .business: AnyShapeStyle(Color(.badgeBusiness))
        case .government: AnyShapeStyle(Color(.badgeGovernment))
        }
    }

    private var label: Text {
        switch badge {
        case .blue: Text("Verified")
        case .business: Text("Verified organization")
        case .government: Text("Verified government account")
        }
    }
}

/// The small avatar of the organization an account is affiliated with.
package struct AffiliateBadge: View {
    let label: AffiliateLabel
    let size: CGFloat

    package init(label: AffiliateLabel, size: CGFloat) {
        self.label = label
        self.size = size
    }

    @Dependency(ImageLoader.self) private var loader
    @Environment(\.displayScale) private var displayScale
    @State private var loaded: CGImage?

    package var body: some View {
        let request = label.badgeURL.map { ImageRequest(url: $0, pointSize: size, scale: displayScale) }
        // Nothing, at no width, until the badge loads: an empty placeholder next to a name reads as a broken image,
        // and a reserved slot leaves a gap when the badge never arrives.
        if let image = loaded ?? request.flatMap(loader.cached) {
            Image(decorative: image, scale: displayScale)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size / 5))
                .accessibilityElement()
                .accessibilityLabel("Affiliated with \(label.description)")
        } else {
            Color.clear
                .frame(width: 0, height: size)
                .accessibilityHidden(true)
                .task(id: request) {
                    guard let request else { return }
                    loaded = await loader.image(request)
                }
        }
    }
}

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

/// "Readers added context" under a post.
package struct CommunityNoteCard: View {
    let note: CommunityNote

    package init(note: CommunityNote) {
        self.note = note
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let shortTitle = note.shortTitle {
                    Label(shortTitle, twitterIcon: .communities)
                } else {
                    Label("Readers added context", twitterIcon: .communities)
                }
            }
            .font(.subheadline.weight(.semibold))

            TweetText(links: note.links, text: note.text, font: .subheadline)

            if let footer = note.footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let url = note.destinationURL {
                Link("Rate this note", destination: url)
                    .font(.caption.weight(.semibold))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.quaternary)
        }
        .accessibilityElement(children: .combine)
    }
}

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
