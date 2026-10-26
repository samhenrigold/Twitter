import Dependencies
import ImagePipeline
import Models
import SwiftUI

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
    /// Every video's and GIF's player, made as its page first shows and kept while the viewer is open, so paging back
    /// resumes where it was.
    @State private var playbacks = ViewerPlaybacks()
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
                        playback: media.first { $0.id == selection }.flatMap(playbacks.playback(for:)),
                        showsChrome: showsChrome,
                        tweet: tweet
                    )
                }
                .overlayArrangementEdge(.trailing)
                .overlayArrangementEdge(.bottom)
            } secondary: {
                MediaPager(media: media, selection: $selection, isZoomed: $isZoomed, playbacks: playbacks) {
                    withAnimation(.snappy) { showsChrome.toggle() }
                }
                .overlayArrangementEdge(.trailing)
                .overlayArrangementEdge(.bottom)
            }
            .arrangementViewStyle(.overlay)
            .background(.mediaBackdrop, ignoresSafeAreaEdges: .all)
            .toolbarVisibility(showsChrome ? .automatic : .hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", twitterIcon: .close, role: .close) { dismiss() }
                }

                if let item = media.first(where: { $0.id == selection }) {
                    // A photo as itself; a video or GIF as its place in the Tweet, as Twitter shares them.
                    if let url = item.kind == .photo ? item.fullSizeURL : tweet?.mediaURL(of: item) ?? item.videoURL {
                        ToolbarItem(placement: .primaryAction) {
                            ShareLink(item: url)
                        }
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
        .toolbarVisibility(showsChrome ? .automatic : .hidden, for: .statusBar)
        .persistentSystemOverlays(showsChrome ? .automatic : .hidden)
        // A zoomed photo pans instead of starting the swipe-down dismissal.
        .interactiveDismissDisabled(isZoomed)
        // A plain ID, as the tiles mark themselves: an optional one never matches theirs, and the zoom falls back to
        // growing out of nowhere.
        .navigationTransition(.zoom(sourceID: zoomSourceID, in: zoomNamespace))
        .onChange(of: selection, initial: true) {
            if let selection { lastSelection = selection }
            // Only the page in view plays; the rest hold their place.
            playbacks.play(media.first { $0.id == selection })
        }
        .onDisappear { playbacks.stop() }
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
    let playbacks: ViewerPlaybacks
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
                        playback: playbacks.playback(for: item),
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

/// The post beside or over its media. Layered over the photo (z-index 1) it's a compact scrim that can hide; on its own
/// half of a folded display (z-index 0) it has room to show everything and stays put.
private struct MediaCaption: View {
    let media: [Media]
    let selection: Media.ID?
    /// The selected video's player, for its controls.
    let playback: VideoPlayback?
    let showsChrome: Bool
    let tweet: Tweet?
    @Environment(\.overlayArrangementZIndex) private var zIndex

    private var isLayered: Bool { zIndex > 0 }
    private var index: Int? { media.firstIndex { $0.id == selection } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let playback, let index, media[index].kind == .video {
                VideoControls(playback: playback)
            }

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
                    .fill(Color.mediaScrim.gradient)
                    .ignoresSafeArea()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isLayered ? .bottom : .center)
        .opacity(isLayered && !showsChrome ? 0 : 1)
        .allowsHitTesting(!isLayered || showsChrome)
    }
}
