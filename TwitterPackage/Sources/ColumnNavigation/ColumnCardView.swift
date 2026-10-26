// Hosts a leading (non-top) column's view. The view controller stays a child of the
// navigation controller; only its view lives here until it becomes the top again.
// The column's header is managed by the navigation controller and sits above the view.
//

import UIKit

final class ColumnCardView: UIView {
    private(set) weak var viewController: UIViewController?
    /// Extra rounding while the column is lifted by a swipe-down or shown in the overview.
    var cornerRadius: CGFloat = 0 {
        didSet { if cornerRadius != oldValue { setNeedsLayout() } }
    }
    /// Darkens a column as newer columns cover it (Tweetie's leftColumnDimmer).
    let dimmer = UIView()
    /// How much shadow the card casts (0…1): only as much as its leading edge actually shows, so a pile of cards
    /// doesn't stack shadow on shadow.
    var shadowStrength: CGFloat = 1 {
        didSet { if shadowStrength != oldValue { setNeedsLayout() } }
    }
    /// Clips the column and its dimmer to the card's corners, together (so their rounded edges can't fringe
    /// against each other), leaving the card itself unclipped to cast its shadow.
    private let content = UIView()

    init(viewController: UIViewController) {
        self.viewController = viewController
        super.init(frame: .zero)
        addSubview(content)
        dimmer.backgroundColor = UIColor(resource: .columnDimmer)
        dimmer.alpha = 0
        dimmer.isUserInteractionEnabled = false
        content.addSubview(dimmer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The card's shape: as cards, the top corners take the card radius and the bottom ones stay square, running
    /// off the bottom edge; `radius` (lifted or browsed) rounds every corner at least that much.
    private static func cornerRadii(_ radius: CGFloat) -> (top: CGFloat, bottom: CGFloat) {
        let settings = ColumnSettings.shared
        return settings.cardStyle ? (max(radius, settings.cardCornerRadius), radius) : (radius, radius)
    }

    /// Rounds and clips a column (a card's content, or the top column's view) to the card shape.
    static func applyCorners(_ radius: CGFloat, to view: UIView) {
        let radii = cornerRadii(radius)
        view.cornerConfiguration = .uniformTopRadius(
            .fixed(radii.top), bottomLeftRadius: .fixed(radii.bottom), bottomRightRadius: .fixed(radii.bottom))
        view.clipsToBounds = ColumnSettings.shared.cardStyle || radius > 0
    }

    /// Square, unclipped: a column's view inside its card (the card's content view clips it).
    static func clearCorners(of view: UIView) {
        view.cornerConfiguration = .corners(radius: .fixed(0))
        view.clipsToBounds = false
    }

    /// Gives `view` a card's drop shadow, shaped like a card occupying `rect` in its coordinates (the view itself
    /// may be bigger, like a wrapper the column moves inside). Cards only; edge to edge, Tweetie's strips are used.
    static func applyShadow(to view: UIView, around rect: CGRect, radius: CGFloat = 0, strength: CGFloat = 1) {
        guard ColumnSettings.shared.cardStyle, !rect.isEmpty else {
            view.layer.shadowOpacity = 0
            return
        }
        let layer = view.layer
        layer.shadowOpacity = Float(0.55 * min(max(strength, 0), 1))
        // The path only changes with the card's shape (not every time it moves or its shadow fades).
        let shape = [rect.minX, rect.minY, rect.width, rect.height, radius, ColumnSettings.shared.cardCornerRadius]
        guard layer.value(forKey: Self.shadowShapeKey) as? [CGFloat] != shape else { return }
        layer.setValue(shape, forKey: Self.shadowShapeKey)
        let radii = cornerRadii(radius)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY - radii.bottom))
        path.addArc(
            withCenter: CGPoint(x: rect.minX + radii.top, y: rect.minY + radii.top), radius: radii.top, startAngle: .pi,
            endAngle: .pi * 1.5, clockwise: true)
        path.addArc(
            withCenter: CGPoint(x: rect.maxX - radii.top, y: rect.minY + radii.top), radius: radii.top,
            startAngle: .pi * 1.5, endAngle: 0, clockwise: true)
        path.addArc(
            withCenter: CGPoint(x: rect.maxX - radii.bottom, y: rect.maxY - radii.bottom), radius: radii.bottom,
            startAngle: 0, endAngle: .pi / 2, clockwise: true)
        path.addArc(
            withCenter: CGPoint(x: rect.minX + radii.bottom, y: rect.maxY - radii.bottom), radius: radii.bottom,
            startAngle: .pi / 2, endAngle: .pi, clockwise: true)
        path.close()
        layer.shadowColor = UIColor(resource: .columnShadow).cgColor
        layer.shadowRadius = 14
        layer.shadowOffset = .zero
        layer.shadowPath = path.cgPath
    }

    private static let shadowShapeKey = "columnShadowShape"

    /// Takes the view controller's view (no-op if already hosted).
    func adoptView() {
        guard let view = viewController?.view, view.superview !== content else { return }
        view.transform = .identity
        view.layer.shadowOpacity = 0
        Self.clearCorners(of: view)
        content.insertSubview(view, at: 0)
        view.frame = content.bounds
    }

    var hostsView: Bool { viewController?.viewIfLoaded?.superview === content }

    override func layoutSubviews() {
        super.layoutSubviews()
        if content.frame != bounds { content.frame = bounds }
        if hostsView, let view = viewController?.view, view.frame != bounds {
            view.frame = bounds
        }
        Self.applyCorners(cornerRadius, to: content)
        Self.applyShadow(to: self, around: bounds, radius: cornerRadius, strength: shadowStrength)
        dimmer.frame = bounds
        content.bringSubviewToFront(dimmer)
    }
}

/// Tweetie's column edge shadows: shadow-left.png (23pt, alpha 0.5) and shadow-left-fat.png (227pt, alpha 0.7),
/// hanging off a column's leading edge onto whatever it covers.
final class ColumnEdgeShadow: UIView {
    static let reach: CGFloat = 227

    private let fine = UIImageView(image: UIImage(named: "shadow-left", in: .module, with: nil))
    private let fat = UIImageView(image: UIImage(named: "shadow-left-fat", in: .module, with: nil))

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        fat.alpha = 0.7
        fine.alpha = 0.5
        addSubview(fat)
        addSubview(fine)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The images are 1pt tall strips; stretch them down the column.
        fat.frame = CGRect(x: bounds.maxX - 227, y: 0, width: 227, height: bounds.height)
        fine.frame = CGRect(x: bounds.maxX - 23, y: 0, width: 23, height: bounds.height)
    }
}

/// Tweetie's throwaway feedback while pulling past the root: two outlined "pages"; the top one tilts away
/// once letting go would clear everything back to the root.
final class ColumnThrowawayIndicator: UIView {
    private let back = CALayer()
    private let front = CALayer()
    private(set) var isArmed = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        alpha = 0
        for page in [back, front] {
            page.borderColor = UIColor(resource: .throwawayPageBorder).cgColor
            page.borderWidth = 2
            page.backgroundColor = UIColor(resource: .throwawayPageFill).cgColor
            page.cornerRadius = 4
            page.cornerCurve = .continuous
            layer.addSublayer(page)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize { CGSize(width: 64, height: 80) }

    func setArmed(_ armed: Bool, animated: Bool) {
        guard armed != isArmed else { return }
        isArmed = armed
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(0.2)
        front.setAffineTransform(armed ? CGAffineTransform(translationX: 10, y: -8).rotated(by: 0.2) : .identity)
        front.opacity = armed ? 0.5 : 1
        CATransaction.commit()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let page = CGRect(x: 0, y: 0, width: 46, height: 60)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        back.bounds = page
        front.bounds = page
        back.position = CGPoint(x: bounds.midX - 4, y: bounds.midY + 4)
        front.position = CGPoint(x: bounds.midX + 4, y: bounds.midY - 4)
        CATransaction.commit()
    }
}
