import Dependencies
import ImagePipeline
import Models
import SwiftUI

/// A remote image decoded at the size it's drawn, from an in-memory cache when possible.
///
/// A row the lazy stack recycles reads its image synchronously on its first frame, so scrolling back never flashes a
/// placeholder. `pointSize` is the longest edge the image is drawn at; it decides how large to decode.
package struct RemoteImage<Placeholder: View>: View {
    let contentMode: ContentMode
    let placeholder: Placeholder
    let pointSize: CGFloat
    let url: URL?

    @Dependency(ImageLoader.self) private var loader
    @Environment(\.displayScale) private var displayScale
    @State private var loaded: LoadedImage?

    package init(
        url: URL?,
        pointSize: CGFloat,
        contentMode: ContentMode = .fill,
        @ContentBuilder placeholder: () -> Placeholder
    ) {
        self.contentMode = contentMode
        self.placeholder = placeholder()
        self.pointSize = pointSize
        self.url = url
    }

    private var request: ImageRequest? {
        url.map { ImageRequest(url: $0, pointSize: pointSize, scale: displayScale) }
    }

    package var body: some View {
        let request = request
        let image = loaded?.request == request ? loaded?.image : request.flatMap(loader.cached)
        ZStack {
            if let image {
                Image(decorative: image, scale: displayScale)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                placeholder
            }
        }
        .task(id: request) {
            guard let request, loader.cached(request) == nil else { return }
            let image = await loader.image(request)
            withAnimation(.easeOut(duration: 0.18)) {
                loaded = LoadedImage(image: image, request: request)
            }
        }
    }
}

extension RemoteImage where Placeholder == ImagePlaceholder {
    package init(url: URL?, pointSize: CGFloat, contentMode: ContentMode = .fill) {
        self.init(url: url, pointSize: pointSize, contentMode: contentMode) { ImagePlaceholder() }
    }
}

package struct ImagePlaceholder: View {
    package var body: some View {
        Rectangle().fill(.quaternary)
    }
}

private struct LoadedImage {
    let image: CGImage?
    let request: ImageRequest
}

extension Media {
    /// A server-side size variant of a photo (`small` is 680px, `medium` 1200px, `orig` the upload), so small tiles
    /// don't download a full-size image only to shrink it.
    package func previewURL(variant: String) -> URL {
        guard kind == .photo, var components = URLComponents(url: previewURL, resolvingAgainstBaseURL: false)
        else { return previewURL }
        var items = (components.queryItems ?? []).filter { $0.name != "name" }
        items.append(URLQueryItem(name: "name", value: variant))
        components.queryItems = items
        return components.url ?? previewURL
    }
}

/// How feed rows draw their images, shared with prefetching so a prefetched image is exactly the one a row asks for.
package enum FeedImages {
    package static let avatarSize: CGFloat = 44

    package static func mediaTile(_ media: Media, count: Int) -> (url: URL, pointSize: CGFloat) {
        count == 1
            ? (media.previewURL(variant: "medium"), 600)
            : (media.previewURL(variant: "small"), 320)
    }

    /// The images a post's row draws: its author's avatar and its media tiles.
    package static func requests(for tweet: Tweet, scale: CGFloat) -> [ImageRequest] {
        var requests: [ImageRequest] = []
        if let avatar = tweet.author.avatarURL(forSize: avatarSize) {
            requests.append(ImageRequest(url: avatar, pointSize: avatarSize, scale: scale))
        }
        for media in tweet.media {
            let tile = mediaTile(media, count: tweet.media.count)
            requests.append(ImageRequest(url: tile.url, pointSize: tile.pointSize, scale: scale))
        }
        return requests
    }
}
