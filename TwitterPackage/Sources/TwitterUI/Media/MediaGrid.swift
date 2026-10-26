import Models
import SwiftUI

package struct MediaGrid: View {
    let media: [Media]
    var maxHeight: CGFloat = 320
    let tweet: Tweet?

    package init(media: [Media], maxHeight: CGFloat = 320, tweet: Tweet? = nil) {
        self.media = media
        self.maxHeight = maxHeight
        self.tweet = tweet
    }

    /// Presented by a flag rather than by item: paging inside the viewer changes the selection, and a presentation
    /// keyed on it would dismiss and re-present.
    @State private var isViewerPresented = false
    @State private var viewerSelection: Media.ID?
    @Namespace private var zoomNamespace

    /// Twitter's photo and video radius.
    static let cornerRadius: CGFloat = 12
    /// `TTAAdaptiveMediaParameters.gutterWidth`.
    static let spacing: CGFloat = 4

    package var body: some View {
        Group {
            if media.count == 1, let item = media.first {
                let aspectRatio = max(item.aspectRatio, 0.75)
                // The full width of the row, as tall as the item at that width up to the cap; a taller item fills it
                // and is cropped, so the photo always reaches its border.
                Color.clear
                    .aspectRatio(aspectRatio, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: maxHeight * 1.4)
                    .overlay {
                        tile(item)
                    }
                    .modifier(MediaBorder())
            } else {
                Grid(horizontalSpacing: Self.spacing, verticalSpacing: Self.spacing) {
                    ForEach(rows, id: \.first?.id) { row in
                        GridRow {
                            ForEach(row) { item in
                                tile(item)
                            }
                        }
                    }
                }
                .frame(height: media.count > 2 ? maxHeight : maxHeight * 0.66)
                .modifier(MediaBorder())
            }
        }
        .fullScreenCover(isPresented: $isViewerPresented) {
            MediaViewer(media: media, selection: $viewerSelection, tweet: tweet, zoomNamespace: zoomNamespace)
        }
        #if DEBUG
            // `--open-media <Tweet ID>`: opens that Tweet's first item in the viewer, for capturing it without tapping.
            .task {
                let arguments = ProcessInfo.processInfo.arguments
                guard let index = arguments.firstIndex(of: "--open-media"), index + 1 < arguments.count,
                    let tweet, arguments[index + 1] == tweet.id, let first = media.first
                else { return }
                try? await Task.sleep(for: .seconds(1))
                viewerSelection = first.id
                isViewerPresented = true
            }
        #endif
    }

    /// Rows of two, each identified by its first item.
    private var rows: [ArraySlice<Media>] {
        stride(from: 0, to: media.count, by: 2).map { media[$0..<min($0 + 2, media.count)] }
    }

    private func tile(_ item: Media) -> MediaTile {
        MediaTile(
            item: item, count: media.count, link: tweet?.mediaURL(of: item), playsInline: !isViewerPresented,
            zoomNamespace: zoomNamespace
        ) {
            viewerSelection = item.id
            isViewerPresented = true
        }
    }
}

/// Twitter's rounded corners and hairline edge, around a lone tile or the whole grid.
private struct MediaBorder: ViewModifier {
    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        content
            .clipShape(.rect(cornerRadius: MediaGrid.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: MediaGrid.cornerRadius)
                    .strokeBorder(.twitterMediaBorder, lineWidth: 1 / displayScale)
            }
    }
}

/// One tappable tile of a `MediaGrid`, and the source the viewer zooms out of. Long-pressing it previews the item
/// alone with its menu (see ``View/mediaPreview(_:link:openTitle:open:)``).
///
/// Videos and GIFs show their play button. With autoplay on in Settings (off by default), they play muted on a loop
/// while they're in view, as Twitter's timeline autoplays them, unless video autoplay is off in Accessibility.
private struct MediaTile: View {
    let item: Media
    let count: Int
    let link: URL?
    /// Off while the viewer is showing it, so the two never play at once.
    let playsInline: Bool
    let zoomNamespace: Namespace.ID
    let open: () -> Void

    @AppStorage(MediaAutoplay.settingKey) private var autoplaysMedia = false

    private var autoplays: Bool { autoplaysMedia && UIAccessibility.isVideoAutoplayEnabled }

    var body: some View {
        Button(action: open) {
            Color.clear
                .overlay {
                    let tile = FeedImages.mediaTile(item, count: count)
                    RemoteImage(url: tile.url, pointSize: tile.pointSize)
                }
                .overlay {
                    if item.kind != .photo, let url = item.inlineVideoURL ?? item.videoURL {
                        InlineVideo(url: url, autoplays: autoplays && playsInline)
                    }
                }
                .overlay {
                    if item.kind != .photo, !autoplays {
                        TwitterIconView(.play, size: 28)
                            .foregroundStyle(.mediaGlyph)
                            .padding(14)
                            .glassEffect(.regular, in: .circle)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    MediaBadge(item: item)
                }
                .clipped()
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // The viewer zooms out of, and back into, the tile it's showing. Inside the context menu, which hosts what it
        // wraps in a view of its own: outside it, the zoom finds no source view and falls back to zooming from nowhere.
        .matchedTransitionSource(id: item.id, in: zoomNamespace) { source in
            source.clipShape(
                RoundedRectangle(cornerRadius: count == 1 ? MediaGrid.cornerRadius : 0)
            )
        }
        // Lifted as a rounded photo, as it's previewed, rather than as a square cut out of the grid.
        .contentShape(.contextMenuPreview, .rect(cornerRadius: MediaGrid.cornerRadius))
        .mediaPreview(item, link: link, open: open)
        .accessibilityLabel(item.altText ?? (item.kind == .photo ? "Image" : "Video"))
        .accessibilityHint("Opens full screen")
    }
}

/// What a video or GIF tile says in its corner: how long the video runs, or that it's a GIF.
private struct MediaBadge: View {
    let item: Media

    var body: some View {
        switch item.kind {
        case .photo:
            EmptyView()
        case .gif:
            TwitterIconView(.gif, size: 24)
                .foregroundStyle(.mediaGlyph)
                .padding(8)
                .accessibilityHidden(true)
        case .video:
            if let durationMillis = item.durationMillis {
                Text(VideoControls.format(Double(durationMillis) / 1000))
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.mediaGlyph)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.mediaScrim, in: .capsule)
                    .padding(8)
                    .accessibilityHidden(true)
            }
        }
    }
}
