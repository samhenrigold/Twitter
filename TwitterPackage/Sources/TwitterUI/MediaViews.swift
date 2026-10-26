import AVKit
import Combine
import Dependencies
import ImagePipeline
import Models
import SwiftUI
import TwitterUI

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
    }

    /// Rows of two, each identified by its first item.
    private var rows: [ArraySlice<Media>] {
        stride(from: 0, to: media.count, by: 2).map { media[$0..<min($0 + 2, media.count)] }
    }

    private func tile(_ item: Media) -> MediaTile {
        MediaTile(item: item, count: media.count, link: tweet?.mediaURL(of: item), zoomNamespace: zoomNamespace) {
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
private struct MediaTile: View {
    let item: Media
    let count: Int
    let link: URL?
    let zoomNamespace: Namespace.ID
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            Color.clear
                .overlay {
                    let tile = FeedImages.mediaTile(item, count: count)
                    RemoteImage(url: tile.url, pointSize: tile.pointSize)
                }
                .overlay {
                    if item.kind != .photo {
                        Image(systemName: item.kind == .gif ? "play.circle" : "play.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                            .padding(14)
                            .glassEffect(.regular, in: .circle)
                    }
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

/// Full-screen media with the post alongside it.
///
/// It zooms out of the tapped tile and back into whichever tile matches the page it's on when closed, by button or by
/// swiping down. An overlay arrangement layers the caption over the media while the display is flat, and gives each
/// its own half when iPhone Duo is partially folded, so a photo never sits across the fold. Bars stay horizontal here:
/// this is an immersive viewer with a single close button, the case the system's vertical bars step aside for.
package struct MediaViewer: View {
    let media: [Media]
    @Binding var selection: Media.ID?
    let tweet: Tweet?
    let zoomNamespace: Namespace.ID

    @State private var isZoomed = false
    /// Where to zoom back to if the selection clears before the dismissal finishes animating.
    @State private var lastSelection: Media.ID?
    @State private var showsChrome = true
    @Environment(\.dismiss) private var dismiss
    /// The timeline's link handling, inherited from the post this viewer was opened from.
    @Environment(\.openURL) private var openURL

    private var zoomSourceID: Media.ID {
        selection ?? lastSelection ?? media.first?.id ?? ""
    }

    package init(media: [Media], selection: Binding<Media.ID?>, tweet: Tweet?, zoomNamespace: Namespace.ID) {
        self.media = media
        _selection = selection
        self.tweet = tweet
        self.zoomNamespace = zoomNamespace
    }

    package var body: some View {
        NavigationStack {
            ArrangementView {
                ZStack {
                    MediaCaption(
                        media: media,
                        selection: selection,
                        showsChrome: showsChrome,
                        tweet: tweet
                    )
                }
                .overlayArrangementEdge(.trailing)
                .overlayArrangementEdge(.bottom)
            } secondary: {
                MediaPager(media: media, selection: $selection, isZoomed: $isZoomed) {
                    withAnimation(.snappy) { showsChrome.toggle() }
                }
                .overlayArrangementEdge(.trailing)
                .overlayArrangementEdge(.bottom)
            }
            .arrangementViewStyle(.overlay)
            .background(.black, ignoresSafeAreaEdges: .all)
            .toolbarVisibility(showsChrome ? .automatic : .hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", twitterIcon: .close, role: .close) { dismiss() }
                }

                if let item = media.first(where: { $0.id == selection }), item.kind == .photo {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: item.fullSizeURL)
                    }
                }
            }
        }
        .toolbarVerticalBehavior(.disabled)
        // A mention or link in the caption opens where the post is (a column, a pushed profile), so the viewer gets
        // out of the way first rather than opening it behind itself.
        .environment(
            \.openURL,
            OpenURLAction { url in
                dismiss()
                openURL(url)
                return .handled
            }
        )
        .colorScheme(.dark)
        .statusBarHidden(!showsChrome)
        .persistentSystemOverlays(showsChrome ? .automatic : .hidden)
        // A zoomed photo pans instead of starting the swipe-down dismissal.
        .interactiveDismissDisabled(isZoomed)
        // A plain ID, as the tiles mark themselves: an optional one never matches theirs, and the zoom falls back to
        // growing out of nowhere.
        .navigationTransition(.zoom(sourceID: zoomSourceID, in: zoomNamespace))
        .onChange(of: selection, initial: true) {
            if let selection { lastSelection = selection }
        }
        .onChange(of: isZoomed) {
            if isZoomed { withAnimation(.snappy) { showsChrome = false } }
        }
        .accessibilityAction(.escape) { dismiss() }
    }
}

private struct MediaPager: View {
    let media: [Media]
    @Binding var selection: Media.ID?
    @Binding var isZoomed: Bool
    let toggleChrome: () -> Void

    @Dependency(ImageLoader.self) private var loader
    @Environment(\.displayScale) private var displayScale
    /// Driven by hand rather than bound to the selection: a lazy pager ignores a starting ID before it has laid out its
    /// pages, and would open on the first while the caption counts the one tapped.
    @State private var position = ScrollPosition(idType: Media.ID.self)

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(media) { item in
                    MediaPage(
                        item: item,
                        isSelected: item.id == selection,
                        thumbnail: FeedImages.mediaTile(item, count: media.count),
                        isZoomed: $isZoomed,
                        toggleChrome: toggleChrome
                    )
                    .containerRelativeFrame([.horizontal, .vertical])
                    .accessibilityAction(named: "Toggle Controls", toggleChrome)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition($position)
        .scrollIndicators(.hidden)
        .ignoresSafeArea()
        .onAppear {
            if let selection { position.scrollTo(id: selection) }
        }
        .onChange(of: position.viewID(type: Media.ID.self)) { _, id in
            if let id, id != selection { selection = id }
        }
        .onChange(of: selection) { isZoomed = false }
        .task {
            loader.prefetch(
                media.filter { $0.kind == .photo }.map { ViewerImages.request(for: $0, scale: displayScale) })
        }
    }
}

/// The decode size for photos in the viewer: sharp full screen on either display, with headroom for zooming, but not
/// the full original (a 4096px original decodes to 64 MB, crowding the feed's thumbnails out of memory).
private enum ViewerImages {
    static func request(for media: Media, scale: CGFloat) -> ImageRequest {
        ImageRequest(url: media.previewURL(variant: "orig"), pointSize: 680, scale: scale)
    }
}

/// The post beside or over its media. Layered over the photo (z-index 1) it's a compact scrim that can hide; on its own
/// half of a folded display (z-index 0) it has room to show everything and stays put.
private struct MediaCaption: View {
    let media: [Media]
    let selection: Media.ID?
    let showsChrome: Bool
    let tweet: Tweet?
    @Environment(\.overlayArrangementZIndex) private var zIndex

    private var isLayered: Bool { zIndex > 0 }
    private var index: Int? { media.firstIndex { $0.id == selection } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let tweet {
                HStack(spacing: 10) {
                    Avatar(user: tweet.author, size: 36)

                    AuthorLine(user: tweet.author, date: tweet.createdAt)
                }

                if !tweet.text.isEmpty {
                    TweetText(tweet: tweet, font: isLayered ? .subheadline : .body)
                        .lineLimit(isLayered ? 4 : nil)
                }
            }

            if let index, let altText = media[index].altText, !altText.isEmpty {
                Label {
                    Text(altText).lineLimit(isLayered ? 2 : nil)
                } icon: {
                    Text("ALT").font(.caption2.weight(.heavy))
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            if media.count > 1, let index {
                Text("\(index + 1) of \(media.count)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: isLayered ? 680 : .infinity, alignment: .leading)
        .background {
            if isLayered {
                Rectangle()
                    .fill(.black.opacity(0.55).gradient)
                    .ignoresSafeArea()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isLayered ? .bottom : .center)
        .opacity(isLayered && !showsChrome ? 0 : 1)
        .allowsHitTesting(!isLayered || showsChrome)
    }
}

private struct MediaPage: View {
    let item: Media
    let isSelected: Bool
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
                if let url = item.videoURL {
                    VideoPage(url: url, loops: item.kind == .gif, isSelected: isSelected, thumbnail: thumbnail)
                } else {
                    ContentUnavailableView("Video unavailable", twitterIcon: .videoOff)
                }
            }
            .contentShape(.rect)
            .onTapGesture(perform: toggleChrome)
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

private struct VideoPage: View {
    let url: URL
    let loops: Bool
    let isSelected: Bool
    let thumbnail: (url: URL, pointSize: CGFloat)
    @State private var isPlaying = false
    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?

    var body: some View {
        ZStack {
            VideoPlayer(player: player)

            // The tile's frame until the first video frame, so the zoom transition never lands on black.
            RemoteImage(url: thumbnail.url, pointSize: thumbnail.pointSize, contentMode: .fit) {
                Color.clear
            }
            .opacity(isPlaying ? 0 : 1)
            .allowsHitTesting(false)
        }
        .task {
            let player = AVQueuePlayer()
            if loops {
                looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            } else {
                player.insert(AVPlayerItem(url: url), after: nil)
            }
            self.player = player
            if isSelected { player.play() }
            for await status in player.publisher(for: \.timeControlStatus).values {
                if status == .playing {
                    withAnimation(.easeOut(duration: 0.2)) { isPlaying = true }
                    break
                }
            }
        }
        // The pager realizes neighbouring pages early; only the page in view plays.
        .onChange(of: isSelected) {
            if isSelected { player?.play() } else { player?.pause() }
        }
        .onDisappear { player?.pause() }
    }
}

extension Array {
    package subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
