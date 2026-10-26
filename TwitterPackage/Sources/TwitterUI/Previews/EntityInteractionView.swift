import PostText
import Routing
import UIKit

/// Claims touches only over entities: a tap opens it, a long press shows its preview and menu.
final class EntityInteractionView: UIView, UIContextMenuInteractionDelegate {
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
                    String(localized: "Copy Username"), image: TwitterIcon.at.uiImage, string: "@\(screenName)"))
        case .hashtag(let tag):
            secondary.append(
                copyAction(String(localized: "Copy Hashtag"), image: TwitterIcon.hashStroke.uiImage, string: tag))
        case .cashtag(let tag):
            secondary.append(
                copyAction(String(localized: "Copy Cashtag"), image: UIImage(systemName: "dollarsign"), string: tag))
        case .url(let url):
            if case .web = target.route {
                primary.append(
                    UIAction(title: String(localized: "Open in Safari"), image: TwitterIcon.globe.uiImage) {
                        [weak self] _ in self?.window?.windowScene?.open(url, options: nil, completionHandler: nil)
                    })
            }
        }
        if let webURL = target.webURL {
            secondary.append(
                UIAction(title: String(localized: "Copy Link"), image: TwitterIcon.link.uiImage) { _ in
                    UIPasteboard.general.url = webURL
                })
            secondary.append(
                UIAction(title: String(localized: "Share…"), image: TwitterIcon.share.uiImage) {
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
