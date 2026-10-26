import Models
import SwiftUI

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
