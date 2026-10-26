import Dependencies
import ImagePipeline
import Models
import SwiftUI

struct MediaPage: View {
    let item: Media
    let isSelected: Bool
    let playback: VideoPlayback?
    let thumbnail: (url: URL, pointSize: CGFloat)
    @Binding var isZoomed: Bool
    let toggleChrome: () -> Void

    var body: some View {
        switch item.kind {
        case .photo:
            PhotoPage(
                item: item,
                isSelected: isSelected,
                thumbnail: thumbnail,
                isZoomed: $isZoomed,
                onSingleTap: toggleChrome
            )
        case .gif, .video:
            Group {
                if let playback, !playback.failed {
                    VideoPage(playback: playback, isGIF: item.kind == .gif, thumbnail: thumbnail)
                } else {
                    ContentUnavailableView("Video unavailable", twitterIcon: .videoOff)
                }
            }
            .contentShape(.rect)
            .onTapGesture(perform: toggleChrome)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(item.altText ?? (item.kind == .gif ? "GIF" : "Video"))
        }
    }
}

/// A photo that's never blank: its first frame is the exact bitmap the tapped tile drew, so the zoom transition lands
/// on the same pixels, and it sharpens in place when the larger decode arrives.
private struct PhotoPage: View {
    let item: Media
    let isSelected: Bool
    let thumbnail: (url: URL, pointSize: CGFloat)
    @Binding var isZoomed: Bool
    let onSingleTap: () -> Void

    @Dependency(ImageLoader.self) private var loader
    @Environment(\.displayScale) private var displayScale
    /// Keyed to its request, so a decode for a previous display scale never shows for the current one.
    @State private var full: (image: CGImage, request: ImageRequest)?

    private var fullRequest: ImageRequest { ViewerImages.request(for: item, scale: displayScale) }
    private var thumbnailRequest: ImageRequest {
        ImageRequest(url: thumbnail.url, pointSize: thumbnail.pointSize, scale: displayScale)
    }

    var body: some View {
        let image =
            (full?.request == fullRequest ? full?.image : nil) ?? loader.cached(fullRequest)
            ?? loader.cached(thumbnailRequest)
        ZStack {
            if let image {
                ZoomableImage(image: image, isSelected: isSelected, isZoomed: $isZoomed, onSingleTap: onSingleTap)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(.rect)
                    .onTapGesture(perform: onSingleTap)
            }
        }
        .task(id: fullRequest) {
            let request = fullRequest
            guard let image = await loader.image(request), !Task.isCancelled else { return }
            full = (image, request)
        }
        .accessibilityElement()
        .accessibilityLabel(item.altText ?? "Image")
        .accessibilityAddTraits(.isImage)
    }
}

/// A video or GIF over its poster: the tile's frame shows until the first video frame is ready, so the zoom
/// transition never lands on black. A paused video shows Twitter's play button in the middle.
private struct VideoPage: View {
    let playback: VideoPlayback
    let isGIF: Bool
    let thumbnail: (url: URL, pointSize: CGFloat)

    var body: some View {
        ZStack {
            RemoteImage(url: thumbnail.url, pointSize: thumbnail.pointSize, contentMode: .fit) {
                Color.clear
            }
            .opacity(playback.isReadyForDisplay ? 0 : 1)

            VideoSurface(playback)
                .opacity(playback.isReadyForDisplay ? 1 : 0)

            if playback.isBuffering {
                ProgressView()
                    .tint(.mediaGlyph)
            } else if !isGIF, !playback.isPlaying {
                Button {
                    playback.play()
                } label: {
                    TwitterIconView(.play, size: 32)
                        .foregroundStyle(.mediaGlyph)
                        .padding(20)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play")
            }
        }
    }
}

/// The decode size for photos in the viewer: sharp full screen on either display, with headroom for zooming, but not
/// the full original (a 4096px original decodes to 64 MB, crowding the feed's thumbnails out of memory).
enum ViewerImages {
    static func request(for media: Media, scale: CGFloat) -> ImageRequest {
        ImageRequest(url: media.previewURL(variant: "orig"), pointSize: 680, scale: scale)
    }
}
