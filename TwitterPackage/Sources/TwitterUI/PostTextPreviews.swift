import Models
import PostText
import Routing
import SwiftUI
import UIKit
import WebKit

extension Text {
    /// The typeset text, with each entity's run (a mention, hashtag, cashtag or link) tagged by an ``EntityRun``
    /// attribute so its glyphs can be found in the text's layout. Text without entities is a single attributed `Text`.
    init(entitiesTaggedIn typeset: TypesetPostText) {
        guard typeset.hasEntities else {
            self.init(typeset.attributedString)
            return
        }
        // A custom attribute belongs to a whole `Text`, so the string is joined from one `Text` per segment. The
        // format is nothing but placeholders ("%@%@…"), so the lookup finds no translation and adds no characters.
        var interpolation = LocalizedStringKey.StringInterpolation(
            literalCapacity: 0, interpolationCount: typeset.segments.count)
        for (index, segment) in typeset.segments.enumerated() {
            let text = Text(segment.text)
            interpolation.appendInterpolation(
                segment.entity == nil ? text : text.customAttribute(EntityRun(index: index)))
        }
        self.init(LocalizedStringKey(stringInterpolation: interpolation))
    }
}

/// Marks the glyph runs of one entity in a laid-out `Text`; `index` is its segment in ``TypesetPostText/segments``.
struct EntityRun: TextAttribute {
    let index: Int
}

extension EnvironmentValues {
    /// Off where text isn't interactive, such as inside a preview or a card that is one big button.
    @Entry package var postTextPreviewsEnabled = true
}

/// Long-pressing a mention, hashtag, cashtag or link in post text lifts it with a preview and menu, as Twitter's
/// status body does for its active ranges (`bodyTextView:previewConfigurationForActiveTextRange:`).
///
/// SwiftUI can't attach a context menu to part of a `Text`, so the entities' glyph rects are read from the text's
/// layout (`Text.LayoutKey`, matched through ``EntityRun``) and a transparent UIKit layer over the text claims
/// touches only inside them. Elsewhere touches fall through to the row underneath, including the row's own context
/// menu. Text without entities adds nothing.
struct PostTextPreviews: ViewModifier {
    let typeset: TypesetPostText
    @Environment(\.postTextPreviewsEnabled) private var isEnabled

    func body(content: Content) -> some View {
        if typeset.hasEntities, isEnabled {
            content.overlayPreferenceValue(Text.LayoutKey.self) { layouts in
                GeometryReader { proxy in
                    EntityInteractionLayer(targets: Self.targets(in: typeset, layouts: layouts, proxy: proxy))
                }
            }
        } else {
            content
        }
    }

    /// Each entity's rects, one per line it lands on, in the overlay's coordinates.
    @MainActor static func targets(
        in typeset: TypesetPostText, layouts: Text.LayoutKey.Value, proxy: GeometryProxy
    ) -> [EntityTarget] {
        var rects: [Int: [CGRect]] = [:]
        for anchored in layouts {
            let origin = proxy[anchored.origin]
            for line in anchored.layout {
                var lineRects: [Int: CGRect] = [:]
                for run in line {
                    guard let index = run[EntityRun.self]?.index else { continue }
                    let rect = run.typographicBounds.rect.offsetBy(dx: origin.x, dy: origin.y)
                    lineRects[index] = lineRects[index]?.union(rect) ?? rect
                }
                for (index, rect) in lineRects {
                    rects[index, default: []].append(rect)
                }
            }
        }
        return rects.sorted { $0.key < $1.key }.compactMap { index, rects in
            typeset.segments[index].entity.map { EntityTarget(index: index, entity: $0, rects: rects) }
        }
    }
}

struct EntityTarget: Equatable {
    /// Its segment, which tells apart two mentions of the same account.
    let index: Int
    let entity: PostEntity
    let rects: [CGRect]

    /// Where a tap goes.
    var url: URL? { entity.destination }

    /// The account it previews: a mention, or a link to a profile.
    var screenName: String? {
        switch entity {
        case .mention(let screenName):
            return screenName
        case .url(let url):
            if case .profileHandle(let screenName) = Route(url: url) { return screenName }
            return nil
        case .hashtag, .cashtag:
            return nil
        }
    }

    /// Its page on Twitter, to copy or share.
    var webURL: URL? {
        switch entity {
        case .mention(let screenName):
            return URL(string: "https://x.com/\(screenName)")
        case .hashtag(let tag):
            var components = URLComponents(string: "https://x.com/hashtag")
            components?.path += "/\(tag.trimmingPrefix("#"))"
            return components?.url
        case .cashtag(let tag):
            var components = URLComponents(string: "https://x.com/search")
            components?.queryItems = [URLQueryItem(name: "q", value: tag)]
            return components?.url
        case .url(let url):
            return url
        }
    }

    /// In-app destinations open in a window of their own; web links open in a web panel window.
    var route: Route? { url.flatMap(Route.forLink) }
}

private struct EntityInteractionLayer: UIViewRepresentable {
    let targets: [EntityTarget]
    @Environment(\.openURL) private var openURL
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows

    func makeUIView(context: Context) -> EntityInteractionView {
        EntityInteractionView()
    }

    func updateUIView(_ view: EntityInteractionView, context: Context) {
        view.targets = targets
        let openURL = openURL
        view.open = { openURL($0) }
        let openWindow = openWindow
        view.openWindow = supportsMultipleWindows ? { openWindow(value: $0.window) } : nil
    }
}

/// Claims touches only over entities: a tap opens it, a long press shows its preview and menu.
private final class EntityInteractionView: UIView, UIContextMenuInteractionDelegate {
    var targets: [EntityTarget] = []
    var open: ((URL) -> Void)?
    var openWindow: ((Route) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        // VoiceOver reaches entities through the text's own links.
        accessibilityElementsHidden = true
        addInteraction(UIContextMenuInteraction(delegate: self))
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        target(at: point) != nil
    }

    private func target(at point: CGPoint) -> EntityTarget? {
        targets.first { target in
            target.rects.contains { $0.insetBy(dx: -2, dy: -2).contains(point) }
        }
    }

    private func target(for configuration: UIContextMenuConfiguration) -> EntityTarget? {
        guard let index = configuration.identifier as? NSNumber else { return nil }
        return targets.first { $0.index == index.intValue }
    }

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        guard let url = target(at: recognizer.location(in: self))?.url else { return }
        open?(url)
    }

    // MARK: UIContextMenuInteractionDelegate

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let target = target(at: location) else { return nil }
        return UIContextMenuConfiguration(
            identifier: target.index as NSNumber,
            previewProvider: { Self.preview(for: target) },
            actionProvider: { [weak self] _ in self?.menu(for: target) }
        )
    }

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configuration: UIContextMenuConfiguration,
        highlightPreviewForItemWithIdentifier identifier: any NSCopying
    ) -> UITargetedPreview? {
        target(for: configuration).flatMap(liftedPreview(of:))
    }

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configuration: UIContextMenuConfiguration,
        dismissalPreviewForItemWithIdentifier identifier: any NSCopying
    ) -> UITargetedPreview? {
        target(for: configuration).flatMap(liftedPreview(of:))
    }

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration,
        animator: any UIContextMenuInteractionCommitAnimating
    ) {
        guard let url = target(for: configuration)?.url else { return }
        animator.addCompletion { [weak self] in self?.open?(url) }
    }

    // MARK: Menu and preview

    /// A profile for an account, the page itself for a web link; tags lift on their own, with no preview.
    private static func preview(for target: EntityTarget) -> UIViewController? {
        if let screenName = target.screenName {
            return ProfilePreviewController(screenName: screenName)
        }
        if case .url(let url) = target.entity, case .web = target.route {
            return WebPreviewController(url: url)
        }
        return nil
    }

    private func menu(for target: EntityTarget) -> UIMenu {
        var primary: [UIMenuElement] = []
        var secondary: [UIMenuElement] = []
        if let url = target.url {
            primary.append(
                UIAction(title: openTitle(for: target), image: openImage(for: target)) {
                    [weak self] _ in self?.open?(url)
                })
        }
        if let openWindow, let route = target.route {
            primary.append(
                UIAction(
                    title: String(localized: "Open in New Window"), image: TwitterIcon.newWindow.uiImage
                ) { _ in openWindow(route) })
        }
        switch target.entity {
        case .mention(let screenName):
            secondary.append(
                copyAction(
                    String(localized: "Copy Username"), image: UIImage(systemName: "at"), string: "@\(screenName)"))
        case .hashtag(let tag):
            secondary.append(
                copyAction(String(localized: "Copy Hashtag"), image: UIImage(systemName: "number"), string: tag))
        case .cashtag(let tag):
            secondary.append(
                copyAction(String(localized: "Copy Cashtag"), image: UIImage(systemName: "dollarsign"), string: tag))
        case .url(let url):
            if case .web = target.route {
                primary.append(
                    UIAction(title: String(localized: "Open in Safari"), image: TwitterIcon.globe.uiImage) { _ in
                        UIApplication.shared.open(url)
                    })
            }
        }
        if let webURL = target.webURL {
            secondary.append(
                UIAction(title: String(localized: "Copy Link"), image: TwitterIcon.link.uiImage) { _ in
                    UIPasteboard.general.url = webURL
                })
            secondary.append(
                UIAction(title: String(localized: "Share…"), image: TwitterIcon.shareStroke.uiImage) {
                    [weak self] _ in self?.share(webURL, from: target)
                })
        }
        return UIMenu(children: [
            UIMenu(options: .displayInline, children: primary),
            UIMenu(options: .displayInline, children: secondary)
        ])
    }

    private func openTitle(for target: EntityTarget) -> String {
        switch target.entity {
        case .mention: String(localized: "View Profile")
        case .hashtag(let tag), .cashtag(let tag): String(localized: "Search \(tag)")
        case .url: target.screenName == nil ? String(localized: "Open Link") : String(localized: "View Profile")
        }
    }

    private func openImage(for target: EntityTarget) -> UIImage? {
        switch target.entity {
        case .mention: TwitterIcon.personStroke.uiImage
        case .hashtag, .cashtag: TwitterIcon.searchStroke.uiImage
        case .url: (target.screenName == nil ? TwitterIcon.externalLinkStroke : .personStroke).uiImage
        }
    }

    private func copyAction(_ title: String, image: UIImage?, string: String) -> UIAction {
        UIAction(title: title, image: image) { _ in
            UIPasteboard.general.string = string
        }
    }

    /// The share sheet, from whichever controller hosts this text, pointing at the entity.
    private func share(_ url: URL, from target: EntityTarget) {
        let host = sequence(first: self as UIResponder, next: \.next).lazy.compactMap { $0 as? UIViewController }
            .first
        guard let host else { return }
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = self
        if let first = target.rects.first {
            sheet.popoverPresentationController?.sourceRect = target.rects.dropFirst().reduce(first) { $0.union($1) }
        }
        host.present(sheet, animated: true)
    }

    /// The entity's glyphs as they're drawn: a snapshot of the screen under its rects, shaped to its lines.
    private func liftedPreview(of target: EntityTarget) -> UITargetedPreview? {
        guard let window, let first = target.rects.first else { return nil }
        let bounds = target.rects.dropFirst().reduce(first) { $0.union($1) }.insetBy(dx: -3, dy: -2)
        guard
            let snapshot = window.resizableSnapshotView(
                from: convert(bounds, to: window), afterScreenUpdates: false, withCapInsets: .zero)
        else { return nil }
        snapshot.frame = CGRect(origin: .zero, size: bounds.size)
        let lines = target.rects.map {
            NSValue(cgRect: $0.offsetBy(dx: -bounds.minX, dy: -bounds.minY).insetBy(dx: -3, dy: -2))
        }
        let parameters = UIPreviewParameters(textLineRects: lines)
        return UITargetedPreview(
            view: snapshot, parameters: parameters,
            target: UIPreviewTarget(container: self, center: CGPoint(x: bounds.midX, y: bounds.midY)))
    }
}

/// A web link's page, loading as the preview opens, as Safari previews a link. Not interactive: a tap on it opens
/// the link where links open.
private final class WebPreviewController: UIViewController {
    private let url: URL

    init(url: URL) {
        self.url = url
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let webView = WKWebView()
        webView.isUserInteractionEnabled = false
        webView.load(URLRequest(url: url))
        view = webView
    }
}
