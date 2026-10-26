import AVFoundation
import CoreTransferable
import Dependencies
import ImagePipeline
import Models
import Photos
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

            if MediaLibrary.canSave, media.kind == .photo || media.videoURL != nil {
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
                LoopingVideo(url: url)
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

/// A muted loop with no controls, for previews.
private struct LoopingVideo: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        let player = AVQueuePlayer()
        player.isMuted = true
        // The poster frame shows until the first video frame is ready.
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = player
        view.looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        player.play()
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {}

    static func dismantleUIView(_ view: PlayerView, coordinator: ()) {
        view.playerLayer.player?.pause()
    }

    final class PlayerView: UIView {
        var looper: AVPlayerLooper?
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
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
            Button(action: open) {
                content.contentShape(shape)
            }
            .buttonStyle(.plain)
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

/// Saving and copying media at full size.
enum MediaLibrary {
    /// Saving needs the app's add-only Photos usage description; without it the request would crash, so the action
    /// isn't offered.
    static let canSave = Bundle.main.object(forInfoDictionaryKey: "NSPhotoLibraryAddUsageDescription") != nil

    /// The upload as a JPEG, whatever it was uploaded as.
    static func originalURL(of media: Media) -> URL {
        guard var components = URLComponents(url: media.previewURL(variant: "orig"), resolvingAgainstBaseURL: false)
        else { return media.previewURL }
        var items = (components.queryItems ?? []).filter { $0.name != "format" }
        items.append(URLQueryItem(name: "format", value: "jpg"))
        components.queryItems = items
        return components.url ?? media.previewURL
    }

    /// Adds the photo, or the video (a GIF is one too), to the library, asking for add-only access the first time.
    @concurrent static func save(_ media: Media) async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return }
        do {
            switch media.kind {
            case .photo:
                let (data, _) = try await URLSession.images.data(from: originalURL(of: media))
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
                }
            case .gif, .video:
                guard let videoURL = media.videoURL else { return }
                let (download, _) = try await URLSession.shared.download(from: videoURL)
                // Photos reads the type from the extension.
                let file = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).mp4")
                try FileManager.default.moveItem(at: download, to: file)
                try await PHPhotoLibrary.shared().performChanges {
                    let options = PHAssetResourceCreationOptions()
                    options.shouldMoveFile = true
                    PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: file, options: options)
                }
            }
            await UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            await UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    @concurrent static func copy(_ media: Media) async {
        guard let (data, _) = try? await URLSession.images.data(from: originalURL(of: media)),
            let image = UIImage(data: data)
        else { return }
        await MainActor.run { UIPasteboard.general.image = image }
    }
}

extension Tweet {
    /// The address of one of this post's photos or videos, as Twitter links them: `…/status/1/photo/2`.
    package func mediaURL(of item: Media) -> URL? {
        guard let index = media.firstIndex(where: { $0.id == item.id }) else { return nil }
        return url.appending(path: "\(item.kind == .photo ? "photo" : "video")/\(index + 1)")
    }
}

extension User {
    /// The avatar as uploaded, without a size suffix, as a photo for the viewer.
    package var avatarMedia: Media? {
        guard let avatarURL,
            let original = URL(string: avatarURL.absoluteString.replacingOccurrences(of: "_normal.", with: "."))
        else { return nil }
        return Media(
            id: "avatar-\(id)", photoURL: original, width: 400, height: 400,
            altText: String(localized: "\(name)'s profile photo"))
    }

    /// The header photo at its largest size (1500×500), as a photo for the viewer.
    package var bannerMedia: Media? {
        bannerURL.map {
            Media(
                id: "banner-\(id)", photoURL: $0, width: 1500, height: 500,
                altText: String(localized: "\(name)'s header photo"))
        }
    }
}
