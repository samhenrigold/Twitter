import ComposableArchitecture
import SwiftUI
import TwitterUI

/// What's attached, as thumbnails to remove before posting.
struct AttachmentStrip: View {
    let attachments: IdentifiedArrayOf<ComposeFeature.Attachment>
    let remove: (ComposeFeature.Attachment.ID) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    AttachmentThumbnail(attachment: attachment)
                        .overlay(alignment: .topTrailing) {
                            Button("Remove", twitterIcon: .close) { remove(attachment.id) }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.glass)
                                .buttonBorderShape(.circle)
                                .controlSize(.small)
                                .padding(6)
                        }
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

private struct AttachmentThumbnail: View {
    private static let height: CGFloat = 120

    let attachment: ComposeFeature.Attachment
    /// Decoded once, at the size drawn, rather than from the full image on every keystroke.
    @State private var thumbnail: UIImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Group {
            if attachment.isVideo {
                Rectangle()
                    .fill(.fill.secondary)
                    .overlay {
                        TwitterIcon.play.image
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .foregroundStyle(.secondary)
                    }
            } else if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: attachment.isVideo ? 160 : Self.height, height: Self.height)
        .clipShape(.rect(cornerRadius: 12))
        .accessibilityLabel(attachment.isVideo ? "Video" : "Photo")
        .task(id: attachment.id) {
            guard !attachment.isVideo, let image = UIImage(data: attachment.upload.data) else { return }
            // Filling the square, so the shorter side is the one that has to cover it.
            let scale = min(Self.height * displayScale / min(image.size.width, image.size.height), 1)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            thumbnail = await image.byPreparingThumbnail(ofSize: size) ?? image
        }
    }
}
