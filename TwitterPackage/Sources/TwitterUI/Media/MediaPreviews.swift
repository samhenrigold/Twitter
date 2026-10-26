import CoreTransferable
import Dependencies
import ImagePipeline
import Models
import SwiftUI
import UIKit
import UniformTypeIdentifiers

extension View {
    /// Long-pressing this view (a photo, video or GIF) previews `media` on its own at its own shape, with Twitter's
    /// media actions: open, save, copy, share and copy link. `open` runs for the first action and for a tap on the
    /// preview; `link` is the media's address within its post, when it's in one.
    ///
    /// As the innermost context menu, it wins over the post row's own.
    package func mediaPreview(
        _ media: Media, link: URL?, openTitle: LocalizedStringKey? = nil, open: @escaping () -> Void
    ) -> some View {
        modifier(MediaPreviewMenu(media: media, link: link, openTitle: openTitle, open: open))
    }

    /// A tap opens `media` in the full-screen viewer, zooming out of this view, and a long press previews it with
    /// the media menu. For a lone image outside a post, such as a profile's avatar or banner; `nil` leaves the view
    /// as it is.
    package func opensInLightbox(_ media: Media?, cornerRadius: CGFloat, label: LocalizedStringKey) -> some View {
        modifier(LightboxSource(media: media, cornerRadius: cornerRadius, label: label))
    }
}

private struct MediaPreviewMenu: ViewModifier {
    let media: Media
    let link: URL?
    let openTitle: LocalizedStringKey?
    let open: () -> Void
    @Dependency(ImageLoader.self) private var loader
    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        content.contextMenu {
            Button(action: open) {
                switch media.kind {
                case .photo: Label(openTitle ?? "View Photo", twitterIcon: .mediaStroke)
                case .gif: Label(openTitle ?? "Play GIF", twitterIcon: .play)
                case .video: Label(openTitle ?? "Play Video", twitterIcon: .play)
                }
            }

            Divider()

            if MediaLibrary.canSave, media.kind == .photo || MediaLibrary.videoFile(of: media) != nil {
                Button {
                    Task { await MediaLibrary.save(media) }
                } label: {
                    Label(media.kind == .photo ? "Save Photo" : "Save Video", twitterIcon: .download)
                }
            }

            if media.kind == .photo {
                Button {
                    Task { await MediaLibrary.copy(media) }
                } label: {
                    Label("Copy Photo", twitterIcon: .copyStroke)
                }
                let photo = SharedPhoto(url: MediaLibrary.originalURL(of: media))
                let title = media.altText ?? String(localized: "Photo")
                if let preview = loader.cached(MediaPreviewImage.request(for: media, scale: displayScale)) {
                    ShareLink(item: photo, preview: SharePreview(title, image: Image(decorative: preview, scale: 1)))
                } else {
                    ShareLink(item: photo, preview: SharePreview(title))
                }
            } else if let url = link ?? media.videoURL {
                ShareLink(item: url)
            }

            if let link {
                Button {
                    UIPasteboard.general.url = link
                } label: {
                    Label(media.kind == .photo ? "Copy Link" : "Copy Video Link", twitterIcon: .link)
                }
            }
        } preview: {
            MediaPreviewImage(media: media)
        }
    }
}

/// The long-press preview: the whole photo (or video frame) at its own aspect ratio, uncropped by the grid it came
/// from. It opens on the bitmap the tile already drew and sharpens when the larger decode arrives; videos and GIFs
/// play muted on a loop over their poster frame.
struct MediaPreviewImage: View {
    let media: Media
    @Dependency(ImageLoader.self) private var loader
    @Environment(\.displayScale) private var displayScale
    @State private var loaded: (image: CGImage, request: ImageRequest)?

    /// The box the preview fits in; the system scales it down further where the screen is smaller.
    private static let maximumSize = CGSize(width: 400, height: 520)

    /// The decode for the preview, the same one the viewer prefetches for photos.
    static func request(for media: Media, scale: CGFloat) -> ImageRequest {
        ImageRequest(url: media.previewURL(variant: "orig"), pointSize: 680, scale: scale)
    }

    private var size: CGSize {
        let aspect = media.aspectRatio
        let box = Self.maximumSize
        return aspect >= box.width / box.height
            ? CGSize(width: box.width, height: box.width / aspect)
            : CGSize(width: box.height * aspect, height: box.height)
    }

    var body: some View {
        let request = Self.request(for: media, scale: displayScale)
        let image =
            (loaded?.request == request ? loaded?.image : nil) ?? loader.cached(request)
            ?? fallbackRequests.lazy.compactMap(loader.cached).first
        ZStack {
            if let image {
                Image(decorative: image, scale: displayScale)
                    .resizable()
            } else {
                ImagePlaceholder()
            }

            if media.kind != .photo, let url = media.inlineVideoURL ?? media.videoURL {
                InlineVideo(url: url, waitsForScrollVisibility: false)
            }
        }
        .frame(width: size.width, height: size.height)
        .task(id: request) {
            guard loader.cached(request) == nil, let image = await loader.image(request) else { return }
            loaded = (image, request)
        }
    }

    /// The tiles a timeline or profile grid drew, for the preview's first frame.
    private var fallbackRequests: [ImageRequest] {
        [FeedImages.mediaTile(media, count: 1), FeedImages.mediaTile(media, count: 2)].map {
            ImageRequest(url: $0.url, pointSize: $0.pointSize, scale: displayScale)
        } + [ImageRequest(url: media.previewURL(variant: "small"), pointSize: 200, scale: displayScale)]
    }
}

/// Opens a lone image in ``MediaViewer``, as ``MediaGrid`` does a post's.
private struct LightboxSource: ViewModifier {
    let media: Media?
    let cornerRadius: CGFloat
    let label: LocalizedStringKey
    @State private var isPresented = false
    @State private var selection: Media.ID?
    @Namespace private var zoomNamespace

    func body(content: Content) -> some View {
        if let media {
            let shape = RoundedRectangle(cornerRadius: cornerRadius)
            ZStack {
                content.contentShape(shape)
            }
            // A tap gesture rather than a `Button`, which would claim the touch as it lands and shut out the column
            // strip's swipe (see `MediaTile`).
            .onTapGesture(perform: open)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            // Inside the context menu, or the zoom finds no source view (see `MediaTile`).
            .matchedTransitionSource(id: media.id, in: zoomNamespace) { $0.clipShape(shape) }
            .contentShape(.contextMenuPreview, shape)
            .mediaPreview(media, link: nil, open: open)
            .fullScreenCover(isPresented: $isPresented) {
                MediaViewer(media: [media], selection: $selection, tweet: nil, zoomNamespace: zoomNamespace)
            }
            .accessibilityLabel(label)
            .accessibilityHint("Opens full screen")
        } else {
            content
        }
    }

    private func open() {
        selection = media?.id
        isPresented = true
    }
}

/// A photo for the share sheet as the image itself rather than a link to it, downloaded only once a destination
/// asks for it.
private struct SharedPhoto: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .jpeg) { photo in
            try await URLSession.images.data(from: photo.url).0
        }
    }
}
