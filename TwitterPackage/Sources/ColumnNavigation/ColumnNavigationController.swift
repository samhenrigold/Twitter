// A real UINavigationController whose stack becomes Tweetie's stacked columns when
// horizontally regular. Compact width is untouched UINavigationController behavior.
//
// The navigation controller keeps owning the stack, the top view controller's wrapper,
// and push/pop bookkeeping. In regular width we (a) place the top wrapper in its column via
// private frame hooks, (b) keep older view controllers' views on screen in ColumnCardViews,
// and (c) run a port of Tweetie's ABSwipeColumnViewController / ABSwipeColumnScrollView:
// pile layout, snap points, throw physics, reveal, throwaway, and synchronous push/remove
// followed by a reveal. As in Tweetie, columns draw their own chrome: the system bar is
// hidden while columnar (the tab bar stays, in the iPhone Duo vertical bar).
//
// Beyond Tweetie: fold paging on iPhone Duo, swipe-down dismiss, and a leading-edge back swipe.
//

import UIKit

package final class ColumnNavigationController: UINavigationController, UINavigationControllerDelegate,
    UIGestureRecognizerDelegate, UIScrollViewDelegate
{
    enum TransitionStyle {
        /// Tweetie: the strip eases to reveal the new last column (a new column enters from off the trailing
        /// edge; removed columns leave toward it).
        case strip
        /// Back swipe: the top column continues off toward trailing.
        case slide
        /// Swipe-down: columns continue downward.
        case dismissDown
    }

    private enum DragMode {
        /// Scrolling the strip (Tweetie's swipe view).
        case scroll
        /// Dragging the top column off by its leading edge (back swipe).
        case back
        /// Dragging on the root (or the strip past it): everything after the root slides away, the history under it
        /// fanning out. Released partway, the overview opens; far enough, the stack clears back to the root.
        case clear
        /// Dragging the root where it has nowhere to go: it gives a little, with heavy resistance, and springs back.
        case nudgeRoot
    }

    static let defaultColumnWidth: CGFloat = 360
    /// Width of the zone at the top column's leading edge (and the screen's) where a rightward drag is "back".
    private static let backSwipeZone: CGFloat = 36
    /// Narrowest piled strip worth drawing.
    private static let minimumStrip: CGFloat = 24
    /// Height of the band at the top of a column (its title bar) where a downward drag lifts it.
    private static let dismissZone: CGFloat = 76
    /// Corner radius of a browsed column, before its scale (about the card radius once scaled down).
    private static let browseCornerRadius: CGFloat = 18

    /// Hosts leading columns. Sits below the navigation transition view, so the top column is always frontmost.
    private let columnHost = UIView()
    private var cards: [ObjectIdentifier: ColumnCardView] = [:]
    private var edgeShadows: [ObjectIdentifier: ColumnEdgeShadow] = [:]
    /// Per column: its scroll view pulled past the top carries the column down (swipe-down dismissal), as in a sheet.
    private var scrollHandoffs: [ObjectIdentifier: ScrollDismissHandoff] = [:]
    /// Tweetie's iPad-sidebar-shadow: the stack's edge cast onto the pinned root, deeper as more columns pile up.
    private let rootShadow = UIImageView()
    private var rootShadowName: String?
    /// A subtle grip on the first column's edge hinting the stack can be pulled away (Tweetie used a pull tab image).
    private let grabber = UIView()
    private let throwawayIndicator = ColumnThrowawayIndicator()
    private let throwawayFeedback = UIImpactFeedbackGenerator(style: .light)
    private let clearDisarmFeedback = UISelectionFeedbackGenerator()
    /// The finger has the clear armed (its haptic played).
    private var clearHapticArmed = false

    /// Scroll position of the column strip (0 = root at the leading edge; negative = pulled past the root).
    private(set) var offset: CGFloat = 0
    /// While true, layout changes keep the newest column flush against the trailing edge.
    private var isPinnedToNewest = true
    /// The hinge moved during a transition; the strip re-pages when it finishes.
    private var needsFoldSettle = false
    /// Column mode has set things up (cards, a hidden bar) that compact needs torn down.
    private var hasColumnState = false
    private var lastLayoutSize: CGSize = .zero
    /// UIKit's container for the top column, made to pass touches through to the columns under it.
    private weak var navigationTransitionView: UIView?
    /// Tweetie's lastSnapOffset: a throw advances at least one stop past it.
    private var lastStop: CGFloat = 0
    /// The column at the leading spot when the strip last came to rest; folding or unfolding keeps it there.
    private var leadingColumn = 0
    /// The column being worked in: the newest after a push or pop, or one revealed (tapped, scrolled, picked). If
    /// the strip leaves it out of view, the newest column fully in view. Its bar buttons go to the vertical bar.
    private var focusedColumn = 0
    /// Whose bar buttons are in the vertical bar, and the view controller whose toolbar items carry them.
    private weak var verticalBarSource: UIViewController?
    private weak var verticalBarHost: UIViewController?
    /// UIKit's wrapper for the top column, while the column is borrowed into a card for the overview.
    private weak var parkedWrapper: UIView?
    /// The column whose toolbar is showing another (focused) column's buttons instead of its own.
    private weak var borrowingToolbarHost: UIViewController?
    /// The toolbar is showing because the vertical bar hosts column buttons (so it's ours to hide again).
    private var showsToolbarForVerticalBar = false
    /// Back swipe in progress: the top column slides toward trailing by this much.
    private var backDrag: CGFloat = 0
    /// The column whose leading seam a back swipe grabbed: it and every column after it go together.
    private var backSwipeFrom = 0
    /// Drag on the root in progress: every column after the root slides toward trailing by this much.
    private var clearDrag: CGFloat = 0
    /// The root card's horizontal give (rubber-banded), from a drag on it.
    private var rootDrag: CGFloat = 0
    /// The root revealed in full by sliding everything after it aside as one block (still piled), rather than
    /// scrolling the strip back and peeling every column off the pile. A resting state.
    private var rootReveal: CGFloat = 0
    /// The current strip drag began with the strip at its start, so pulling past it is a root pull.
    private var scrollCanPullRoot = false
    /// Root reveal when the current strip drag began.
    private var rootRevealBase: CGFloat = 0
    /// Swipe-down in progress: columns at `index` and newer move down by `translation`.
    private var dismissal: (index: Int, translation: CGFloat)?
    /// How far the columns are carried from the strip into the history browser (0 = the strip, 1 = browsing).
    private var browseOpenness: CGFloat = 0
    /// The browser is open and resting (taps pick a column, flicks up close columns).
    private var isBrowserOpen = false
    /// The browser is on screen at all (opening, open, or closing).
    private var isBrowsing = false
    /// Scrolls the open overview's filmstrip (a real scroll view, for native deceleration and rubber-banding). Its
    /// content offset is the filmstrip position, from the first column's middle.
    private let browseScrollView = UIScrollView()
    private lazy var browseTap = UITapGestureRecognizer(target: self, action: #selector(handleBrowseTap(_:)))
    /// Configuring the scroll view from a layout pass (its offset changes shouldn't lay out again).
    private var isSyncingBrowseScroll = false
    /// Flicking browsed columns up: the one at `index` and newer ones move up by `translation`.
    private var browseLift: (index: Int, translation: CGFloat)?
    /// Darkens the backdrop behind the browser.
    private let browseBackdrop = UIView()
    /// Covers the columns while the browser is open, so touches pick columns rather than reaching their content.
    private let browseShield = UIView()
    private lazy var browseLiftPan = UIPanGestureRecognizer(target: self, action: #selector(handleBrowseLift(_:)))
    private var pendingTransitionStyle: TransitionStyle = .strip
    /// Release velocity (points per second, along the leaving direction) for a gesture-driven pop to carry on with.
    private var pendingReleaseVelocity: CGFloat = 0
    package private(set) var isRunningColumnTransition = false

    private let scroller = ColumnScroller()
    private lazy var swipe = ColumnSwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
    private lazy var dismissPan = UIPanGestureRecognizer(target: self, action: #selector(handleDismissPan(_:)))
    private var dragMode: DragMode?
    /// Offset when the current touch went down (Tweetie's originalBounds).
    private var touchDownOffset: CGFloat = 0
    private var touchDownColumn: Int?
    /// The current touch scrolled a column's content, which already revealed it: lifting shouldn't reveal again.
    private var revealedOnScroll = false
    /// The touch caught the top column springing back from a back swipe: dragging it continues the back swipe.
    private var caughtBackSwipe = false
    /// The touch caught something in motion (the strip, a root pull, a back swipe): it's a drag from the start,
    /// so it can't also tap content, and lifting in place settles what it caught.
    private var caughtMotion = false
    /// Where the dragged value was when the current drag caught it (drags continue from there, 1:1).
    private var dragBase: CGFloat = 0
    private var browseLiftBase: CGFloat = 0
    /// Columns from this index on were flicked off in the overview and leave the stack once they're gone.
    private var pendingBrowseRemoval: Int?

    /// Every gesture-driven value lives on a spring stepped by one display link; each frame lays everything out from
    /// the values at once, so shadows, dimmers and masks can't drift from their columns, and a touch catches a
    /// moving column exactly where it is.
    private lazy var driver = FluidDriver { [weak self] in
        guard let self, !isRunningColumnTransition else { return }
        UIView.performWithoutAnimation { self.applyColumnLayout() }
    }
    private lazy var backSpring = spring { $0.backDrag = $1 }
    /// The root's own give: it never goes anywhere, but it moves (rubber-banded) under a finger instead of feeling stuck.
    private lazy var rootSpring = spring { $0.rootDrag = $1 }
    /// Settles the strip after a release: critically damped, carrying the release velocity, so it lands on its stop
    /// without overshooting (Tweetie's integrator bounced). Taps and reveals still ease with Tweetie's scroller.
    private lazy var stripSpring = spring(restThreshold: 0.5) { $0.offset = $1 }

    private var isStripMoving: Bool { scroller.isAnimating || stripSpring.isAnimating }

    private func stopStrip() {
        scroller.stop()
        stripSpring.stop()
    }
    private lazy var rootRevealSpring = spring { $0.rootReveal = $1 }
    private lazy var clearSpring = spring { $0.clearDrag = $1 }
    private lazy var dismissSpring = spring { controller, value in
        if let index = controller.dismissal?.index { controller.dismissal = (index, value) }
    }
    private lazy var browseOpenSpring = spring(restThreshold: 0.001) { controller, value in
        controller.browseOpenness = value
        controller.landBrowserIfNeeded()
    }
    /// SpringBoard's widget drop insertion spring (SBHWidgetSettings: dampingRatio 0.7, response 0.36): the overview
    /// lands with a little plop.
    private static let browseSpringResponse: CGFloat = 0.36
    private static let browseSpringDamping: CGFloat = 0.7
    /// SpringBoard's folder open/close (SBHFolderOpenSettings: critically damped, response 0.34).
    private static let browseSettleResponse: CGFloat = 0.34
    private let browseHaptic = SoftLandingHaptic()
    /// The overview is springing open or closed and hasn't landed (the moment its haptic fires) yet.
    private var browseLanding: (opening: Bool, landed: Bool)?
    private lazy var browseLiftSpring = spring { controller, value in
        if let index = controller.browseLift?.index { controller.browseLift = (index, value) }
    }
    /// A column transition's progress, 0 → 1.
    private lazy var transitionSpring = spring(restThreshold: 0.0005) { _, _ in }

    /// Puts every gesture value back at rest, through its spring (so the spring's own value stays in sync and a
    /// later drag or release doesn't start from a stale one).
    private func resetGestureSprings() {
        for spring in [
            backSpring, clearSpring, rootSpring, rootRevealSpring, dismissSpring, browseOpenSpring, browseLiftSpring
        ] {
            spring.set(0)
        }
        dismissal = nil
        browseLift = nil
    }

    private func spring(restThreshold: CGFloat = 0.05, _ apply: @escaping (ColumnNavigationController, CGFloat) -> Void)
        -> FluidSpring
    {
        let spring = FluidSpring(restThreshold: restThreshold)
        spring.onChange = { [weak self] value in
            if let self { apply(self, value) }
        }
        return spring
    }
    /// The stack most recently passed to setViewControllers by a truncating push.
    private var requestedStack: [UIViewController]?
    /// Where each column's view (and edge shadow) appeared when the current transition was requested. UIKit lays
    /// the incoming column out (possibly in the outgoing column's wrapper) before our animator runs, so the
    /// animator starts from these rather than from what it finds.
    private var framesAtRequest: [ObjectIdentifier: CGRect] = [:]
    private var overlay: ColumnDebugOverlay?
    #if DEBUG
        fileprivate(set) var debugFold: ClosedRange<CGFloat>?
    #endif

    private var settings: ColumnSettings { .shared }

    package var isColumnar: Bool {
        traitCollection.horizontalSizeClass == .regular
    }

    // MARK: Lifecycle

    package override init(rootViewController: UIViewController) {
        NavigationControllerHooks.installIfNeeded()
        super.init(rootViewController: rootViewController)
    }

    package override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        NavigationControllerHooks.installIfNeeded()
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    package required init?(coder: NSCoder) {
        NavigationControllerHooks.installIfNeeded()
        super.init(coder: coder)
    }

    package override func viewDidLoad() {
        super.viewDidLoad()
        view.insertSubview(columnHost, at: 0)
        // Columns sit on a dark hatched void (tiled).
        let void = UIImage(named: "hash-background", in: .module, with: nil).map(UIColor.init(patternImage:)) ?? .black
        view.backgroundColor = void
        columnHost.backgroundColor = void
        browseBackdrop.backgroundColor = .black
        browseBackdrop.alpha = 0
        browseBackdrop.isUserInteractionEnabled = false
        columnHost.addSubview(browseBackdrop)
        browseShield.isHidden = true
        browseLiftPan.delegate = self
        browseShield.addGestureRecognizer(browseLiftPan)
        browseShield.addGestureRecognizer(browseTap)
        browseScrollView.delegate = self
        browseScrollView.showsHorizontalScrollIndicator = false
        browseScrollView.showsVerticalScrollIndicator = false
        browseScrollView.alwaysBounceHorizontal = true
        browseScrollView.contentInsetAdjustmentBehavior = .never
        // A vertical swipe (dismissing columns) wins over scrolling the filmstrip.
        browseScrollView.panGestureRecognizer.require(toFail: browseLiftPan)
        browseShield.addSubview(browseScrollView)
        view.addSubview(browseShield)
        rootShadow.isUserInteractionEnabled = false
        grabber.isUserInteractionEnabled = false
        grabber.backgroundColor = .tertiaryLabel
        grabber.layer.cornerRadius = 2.5
        grabber.layer.cornerCurve = .continuous

        swipe.delegate = self
        swipe.onTouchDown = { [weak self] point in self?.touchDown(at: point) }
        swipe.beginsOnTouchDown = { [weak self] in self?.caughtMotion ?? false }
        swipe.onTouchEndedWithoutDrag = { [weak self] _, isTap in self?.touchEndedWithoutDrag(isTap: isTap) }
        dismissPan.delegate = self
        #if DEBUG
            let installsGestures = ProcessInfo.processInfo.environment["COLUMNNAV_DISABLE_PANS"] != "1"
        #else
            let installsGestures = true
        #endif
        if installsGestures {
            view.addGestureRecognizer(swipe)
            view.addGestureRecognizer(dismissPan)
        }

        scroller.onUpdate = { [weak self] value in
            self?.offset = value
            self?.applyColumnLayout()
        }

        view.addInteraction(
            UIHingeInteraction { [weak self] _, _ in
                self?.foldDidChange()
            })

        registerForTraitChanges([UITraitHorizontalSizeClass.self]) { (self: Self, _) in
            // A gesture under way belongs to the other mode: cancel it (its release then does nothing).
            for recognizer in [self.swipe, self.dismissPan, self.browseLiftPan] where recognizer.state != .possible {
                recognizer.isEnabled = false
                recognizer.isEnabled = true
            }
            self.dragMode = nil
            self.pendingTransitionStyle = .strip
            self.pendingReleaseVelocity = 0
            // Entering or leaving columns (unfolding the Duo from its outer display, say): the column you were on in
            // the plain stack, the newest, stays in view and focused.
            self.isPinnedToNewest = true
            self.focusedColumn = max(self.viewControllers.count - 1, 0)
            self.view.setNeedsLayout()
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsDidChange), name: ColumnSettings.didChange, object: nil)
        settingsDidChange()
    }

    package override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyColumnLayout()
    }

    package override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // UIKit only forwards to the top column; leading columns leave the screen with us.
        viewControllers.dropLast().forEach { setAppeared($0, false) }
    }

    package override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        columnHost.frame = view.bounds
        browseBackdrop.frame = columnHost.bounds
        browseShield.frame = view.bounds
        overlay?.frame = view.bounds
        if navigationTransitionView == nil, responds(to: NSSelectorFromString("navigationTransitionView")),
            let transitionView = value(forKey: "navigationTransitionView") as? UIView
        {
            NavigationControllerHooks.makeTouchTransparent(transitionView)
            navigationTransitionView = transitionView
        }
        if view.bounds.size != lastLayoutSize {
            lastLayoutSize = view.bounds.size
            reanchorStrip()
        }
        if !isRunningColumnTransition, !isStripMoving, dragMode == nil {
            if driver.isAnimating || isBrowsing {
                // The springs own the motion: a layout pass inside someone else's animation (the tab bar showing,
                // say) mustn't turn their per-frame placements into a competing Core Animation animation.
                UIView.performWithoutAnimation { applyColumnLayout() }
            } else {
                applyColumnLayout()
            }
        }
        if !isRunningColumnTransition {
            focusedColumn = min(focusedColumn, viewControllers.count - 1)
            updateVerticalBarItems()
        }
    }

    @objc private func settingsDidChange() {
        scroller.throwFriction = settings.throwFriction
        if settings.showsOverlay, overlay == nil {
            let overlay = ColumnDebugOverlay()
            view.addSubview(overlay)
            self.overlay = overlay
        } else if !settings.showsOverlay {
            overlay?.removeFromSuperview()
            overlay = nil
        }
        view.setNeedsLayout()
    }

    /// The hinge moved: re-page around the fold (or back to preferred widths).
    private func foldDidChange() {
        guard isColumnar else { return }
        guard !isRunningColumnTransition else {
            // Once the transition lands.
            needsFoldSettle = true
            return
        }
        stopStrip()
        rootRevealSpring.set(0)
        // Stay on the same spot: the column that was at the leading spot (just after the root's peek, or on the
        // left page) stays there in the new layout.
        let anchor = leadingColumn
        func settle() {
            let layout = makeLayout()
            let previous = offset
            offset = layout.leadingOffset(for: anchor)
            // A drag under way carries on from the new place.
            touchDownOffset += offset - previous
            lastStop = offset
            isPinnedToNewest = abs(offset - layout.maxOffset) < 0.5
            leadingColumn = anchor
            Fluid.animate(Fluid.criticallyDamped) {
                self.applyColumnLayout()
                self.view.layoutIfNeeded()
            }
        }
        settle()
        // The division region can update a beat after the hinge; settle again once it has.
        DispatchQueue.main.async { [weak self] in
            guard let self, !isRunningColumnTransition else { return }
            settle()
        }
    }

    package override func preferredContentSizeDidChange(forChildContentContainer container: any UIContentContainer) {
        super.preferredContentSizeDidChange(forChildContentContainer: container)
        guard isColumnar, !isRunningColumnTransition else { return }
        reanchorStrip()
        // Tweetie: viewControllerNeedsToUpdateWidth: relays out.
        UIView.animate(springDuration: 0.45, bounce: 0) {
            self.applyColumnLayout()
            self.view.layoutIfNeeded()
        }
    }

    // MARK: Pushing from a leading column

    /// Tweetie's pushViewController:afterViewController: — showing from a leading column replaces every column after it.
    package override func show(_ viewController: UIViewController, sender: Any?) {
        // One transition at a time: a second tap mid-flight would start from frames that are still moving.
        if isColumnar, isRunningColumnTransition || transitionCoordinator != nil { return }
        guard isColumnar,
            let source = sender as? UIViewController,
            let index = viewControllers.firstIndex(where: { column in
                sequence(first: source, next: \.parent).contains { $0 === column }
            }),
            index < viewControllers.count - 1
        else {
            super.show(viewController, sender: sender)
            return
        }
        let stack = Array(viewControllers.prefix(through: index)) + [viewController]
        requestedStack = stack
        recordFramesAtRequest()
        setViewControllers(stack, animated: true)
    }

    /// Replaces the stack with `stack`, as a push from a leading column does: the columns after the one it shares with
    /// the current stack are replaced, and the strip reveals the new last column.
    package func setColumns(_ stack: [UIViewController], animated: Bool) {
        requestedStack = stack
        recordFramesAtRequest()
        setViewControllers(stack, animated: animated)
        if !animated { requestedStack = nil }
    }

    /// The stack a transition ends with. During setViewControllers(_:animated:) UIKit asks for the animation
    /// before `viewControllers` reflects the new stack, so prefer what we requested, else trim to the incoming VC.
    private func destinationStack(endingIn toVC: UIViewController) -> [UIViewController] {
        if let requestedStack, requestedStack.last === toVC { return requestedStack }
        let current = viewControllers
        if let index = current.firstIndex(of: toVC) { return Array(current.prefix(through: index)) }
        return current + [toVC]
    }

    // MARK: Layout

    /// The window's safe area wherever this view overlaps it. Hosted in SwiftUI, the view's own safe area is zero even
    /// under the window's bars (SwiftUI keeps the safe area to itself), so it goes by the window's.
    private var safeAreaInsets: UIEdgeInsets {
        var insets = view.safeAreaInsets
        guard let window = view.window else { return insets }
        let frame = view.convert(view.bounds, to: window)
        let windowInsets = window.safeAreaInsets
        insets.top = max(insets.top, windowInsets.top - frame.minY)
        insets.left = max(insets.left, windowInsets.left - frame.minX)
        insets.bottom = max(insets.bottom, frame.maxY - (window.bounds.height - windowInsets.bottom))
        insets.right = max(insets.right, frame.maxX - (window.bounds.width - windowInsets.right))
        return insets
    }

    private func preferredWidth(of viewController: UIViewController) -> CGFloat {
        let width = viewController.preferredContentSize.width
        return width > 0 ? width : Self.defaultColumnWidth
    }

    /// The hinge's division region while partially folded, if it splits the view left/right.
    private var activeFold: ClosedRange<CGFloat>? {
        #if DEBUG
            // COLUMNNAV_FAKE_FOLD="455.5-495.5" stands in for the hinge's division region (simulator posture can't be scripted).
            if let fake = ProcessInfo.processInfo.environment["COLUMNNAV_FAKE_FOLD"]?.split(separator: "-").compactMap({
                Double($0)
            }), fake.count == 2 {
                return CGFloat(fake[0])...CGFloat(fake[1])
            }
            if let debugFold { return debugFold }
        #endif
        guard
            let region = view.reservedRegions(kind: .division).first(where: {
                $0.isActive && $0.frame.height > $0.frame.width
            })
        else { return nil }
        return region.frame.minX...region.frame.maxX
    }

    private func makeLayout(for stack: [UIViewController]? = nil) -> ColumnLayout {
        let widths = (stack ?? viewControllers).map(preferredWidth(of:))
        guard isCardStyle else {
            let trailingInset = safeAreaInsets.right
            return ColumnLayout(
                widths: widths,
                availableWidth: view.bounds.width - trailingInset,
                trailingInset: trailingInset,
                height: view.bounds.height,
                stackInset: settings.effectiveStackInset,
                fold: activeFold
            )
        }
        // Cards sit within the layout margins (the system minimum plus the safe area, so clear of the Duo's
        // vertical bar), a gap apart. The layout runs edge to edge between the margins, widened by the gap that the
        // outermost cards give back.
        var margins = view.layoutMargins
        margins.left += settings.cardInset
        // Trailing, just clear of the safe area (the vertical bar): the layout margin on top of it is too much.
        margins.right = safeAreaInsets.right + settings.cardInset
        margins.top += settings.cardInset
        if view.bounds.width > view.bounds.height {
            // Landscape (the Duo unfolded on its side, a big phone turned): the cards mirror the safe area across the
            // display, as far from the leading edge as the trailing safe area (the vertical bar) and as far from the
            // top as the bottom safe area (the home indicator), so they sit balanced.
            let safeArea = safeAreaInsets
            margins.left = max(margins.left, safeArea.right)
            margins.top = max(margins.top, safeArea.top + safeArea.bottom)
        }
        let gap = settings.cardGap
        let origin = margins.left - gap / 2
        let fold = activeFold.map { ($0.lowerBound - origin)...($0.upperBound - origin) }
        return ColumnLayout(
            widths: widths,
            availableWidth: view.bounds.width - margins.left - margins.right + gap,
            trailingInset: 0,
            height: view.bounds.height,
            stackInset: settings.effectiveStackInset,
            fold: fold,
            cardLeading: margins.left,
            cardTop: max(margins.top, gap),
            cardGap: gap
        )
    }

    private func currentFrames(_ layout: ColumnLayout) -> [CGRect] {
        var frames =
            clearDrag != 0
            ? layout.frames(offset: offset, detach: clearDrag, detachFrom: 1)
            : layout.frames(
                offset: offset, detach: backDrag,
                detachFrom: backDrag != 0 ? min(backSwipeFrom, layout.widths.count - 1) : nil)
        if clearDrag > 0, frames.count > 2 {
            // Pulling the stack off the root fans out the history under it: the newest column follows the finger and
            // each older one lags a little more (the oldest at half speed), so the piled columns slide apart and
            // peek out from under each other, showing how much is about to be cleared.
            let deepest = CGFloat(frames.count - 2)
            for index in 1..<(frames.count - 1) {
                let depth = CGFloat(frames.count - 1 - index) / deepest
                frames[index].origin.x -= clearDrag * Self.clearFanLag * depth
            }
        }
        if rootReveal != 0 {
            for index in frames.indices.dropFirst() { frames[index].origin.x += rootReveal }
        }
        if rootDrag != 0, !frames.isEmpty { frames[0].origin.x += rootDrag }
        return frames
    }

    /// At rest, the strip keeps to the layout it's in: pinned to the newest column, or (after the stack or the
    /// geometry changed under it) back within its range, with the root's reveal at its new extent.
    private func settleStripIntoLayout(_ layout: ColumnLayout) {
        if !isPinnedToNewest, offset >= layout.maxOffset - 0.5 { isPinnedToNewest = true }
        if isPinnedToNewest {
            offset = layout.maxOffset
            lastStop = offset
            // Kept current, so a fold or unfold that follows keeps this place rather than an older one.
            leadingColumn = layout.leadingColumn(offset: offset)
        } else if offset < 0 {
            offset = 0
            lastStop = 0
        }
        if rootReveal > 0, !rootRevealSpring.isAnimating {
            let extent = rootRevealExtent(layout)
            if abs(extent - rootReveal) > 0.5 { rootRevealSpring.set(extent) }
        }
    }

    /// Widths or bounds changed: the column at the leading spot stays there (as folding does).
    private func reanchorStrip() {
        guard isColumnar, !isPinnedToNewest, dragMode == nil, !isRunningColumnTransition else { return }
        stopStrip()
        offset = makeLayout().leadingOffset(for: leadingColumn)
        lastStop = offset
    }

    /// How far everything after the root slides aside to show the root in full (0 if it already is).
    private func rootRevealExtent(_ layout: ColumnLayout) -> CGFloat {
        let frames = layout.frames(offset: offset)
        guard frames.count > 1 else { return 0 }
        return max(0, frames[0].maxX - frames[1].minX)
    }

    /// Slides the block of columns after the root to `target` (0, or the full reveal).
    private func setRootReveal(_ target: CGFloat, velocity: CGFloat? = nil) {
        driver.animate(
            rootRevealSpring, to: target, velocity: velocity, response: Self.rootRevealResponse, dampingRatio: 1)
    }

    private static let rootRevealResponse: CGFloat = 0.42

    /// How much the oldest column lags the finger while the stack is pulled off the root (newer ones, less).
    private static let clearFanLag: CGFloat = 0.5

    /// How far a card's leading edge must stand out from the one under it before it casts its full shadow.
    private static let shadowRevealDistance: CGFloat = 40

    /// How far the root gives: rubber-banded finger travel, never more than this.
    private static let rootGive: CGFloat = 90

    /// Visual displacement for column `index` while swiping down. Newer columns trail the grabbed one a
    /// little more each, so the lifted stack reads as separate cards rather than one slab.
    private func dismissalTransform(for index: Int) -> CGAffineTransform {
        guard let dismissal, index >= dismissal.index else { return .identity }
        let lag = pow(0.86, CGFloat(index - dismissal.index))
        return CGAffineTransform(translationX: 0, y: dismissal.translation * lag)
    }

    /// How far a back swipe has committed the top column to leaving (0…1). The column shrinks, fades and blurs
    /// with it, so it's clear that letting go pops it.
    private var backSwipeProgress: CGFloat {
        min(max(backDrag, 0) / (settings.popDistance * 2), 1)
    }

    /// The frontmost column (after the root) whose leading seam `point` is on, if its seam isn't covered by the
    /// next column.
    private func seamColumn(at point: CGPoint, in frames: [CGRect]) -> Int? {
        frames.indices.dropFirst().last { index in
            let nextMinX = index + 1 < frames.count ? frames[index + 1].minX : .greatestFiniteMagnitude
            guard nextMinX - frames[index].minX > Self.backSwipeZone else { return false }
            return point.x >= frames[index].minX - 8 && point.x < frames[index].minX + Self.backSwipeZone
        }
    }

    private static func backSwipeScale(_ progress: CGFloat) -> CGFloat { 1 - 0.08 * progress }
    private static func backSwipeAlpha(_ progress: CGFloat) -> CGFloat { 1 - 0.45 * progress }
    private static let backSwipeBlur: CGFloat = 10

    /// A Gaussian blur of `radius` on a view's layer (Core Animation's private CAFilter; 0 removes it).
    private static func setBlur(_ radius: CGFloat, on view: UIView) {
        let layer = view.layer
        guard radius > 0.05 else {
            if layer.filters != nil { layer.filters = nil }
            return
        }
        if (layer.filters ?? []).isEmpty {
            guard let filterType = NSClassFromString("CAFilter") as? NSObject.Type,
                let filter = filterType.perform(NSSelectorFromString("filterWithType:"), with: "gaussianBlur")?
                    .takeUnretainedValue() as? NSObject
            else { return }
            filter.setValue("gaussianBlur", forKey: "name")
            layer.filters = [filter]
        }
        layer.setValue(radius, forKeyPath: "filters.gaussianBlur.inputRadius")
    }

    /// Extra rounding of a column beyond its card corners: only in the overview (a swipe-down keeps its shape).
    private func columnCornerRadius(for index: Int) -> CGFloat {
        Self.browseCornerRadius * min(max(browseOpenness, 0), 1)
    }

    private func browseLayout(frames: [CGRect]) -> ColumnBrowseLayout {
        var layout = ColumnBrowseLayout(
            bounds: view.bounds,
            trailingInset: safeAreaInsets.right,
            widths: frames.map(\.width),
            position: 0
        )
        layout.position = layout.positions.lowerBound + browseScrollView.contentOffset.x
        return layout
    }

    /// Sizes the overview's scroll view to the filmstrip (content beyond the screen by its scrollable range).
    private func syncBrowseScrollView(_ layout: ColumnBrowseLayout) {
        isSyncingBrowseScroll = true
        defer { isSyncingBrowseScroll = false }
        if browseScrollView.frame != browseShield.bounds { browseScrollView.frame = browseShield.bounds }
        let size = CGSize(
            width: browseShield.bounds.width + layout.positions.upperBound - layout.positions.lowerBound,
            height: browseShield.bounds.height)
        if browseScrollView.contentSize != size { browseScrollView.contentSize = size }
    }

    /// Scrolls the overview so column `index` is in the middle.
    private func scrollBrowser(toColumn index: Int, animated: Bool) {
        let layout = browseLayout(frames: currentFrames(makeLayout()))
        guard layout.widths.indices.contains(index) else { return }
        syncBrowseScrollView(layout)
        let target = CGPoint(x: layout.mid(at: index) - layout.positions.lowerBound, y: 0)
        if animated {
            browseScrollView.setContentOffset(target, animated: true)
        } else {
            isSyncingBrowseScroll = true
            browseScrollView.contentOffset = target
            isSyncingBrowseScroll = false
        }
    }

    package func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === browseScrollView, !isSyncingBrowseScroll, isBrowsing else { return }
        applyColumnLayout()
    }

    @objc private func handleBrowseTap(_ tap: UITapGestureRecognizer) {
        guard isBrowserOpen else { return }
        // A tap picks a column (or, off the columns, just closes the overview).
        closeBrowser(revealing: browseColumn(at: tap.location(in: view)))
    }

    private func columnTransform(for index: Int, frames: [CGRect]) -> CGAffineTransform {
        isBrowsing ? browseTransform(for: index, frames: frames) : dismissalTransform(for: index)
    }

    /// Carries a column from its strip frame toward its browser pose as `browseOpenness` goes 0 → 1. At 1 the pose
    /// doesn't depend on the strip's scroll offset, so the strip can change under an open browser without moving it.
    private func browseTransform(for index: Int, frames: [CGRect]) -> CGAffineTransform {
        let pose = browseLayout(frames: frames).pose(at: index)
        // Unclamped: the overview's springs overshoot, and the columns follow (the plop).
        let progress = browseOpenness
        let frame = frames[index]
        let scale = 1 + (pose.scale - 1) * progress
        var lift: CGFloat = 0
        if let browseLift, index >= browseLift.index {
            lift = browseLift.translation * pow(0.92, CGFloat(index - browseLift.index))
        }
        return CGAffineTransform(
            translationX: (pose.center.x - frame.midX) * progress, y: (pose.center.y - frame.midY) * progress + lift
        )
        .scaledBy(x: scale, y: scale)
    }

    /// The browsed column under `point` (they don't overlap in the browser).
    private func browseColumn(at point: CGPoint) -> Int? {
        let stack = viewControllers
        return stack.indices.last { index in
            let host: UIView? =
                cards[ObjectIdentifier(stack[index])] ?? (index == stack.count - 1 ? topWrapperView : nil)
            guard let host, host.alpha > 0.05 else { return false }
            return host.bounds.contains(host.convert(point, from: view))
        }
    }

    /// Hook target: the top column's wrapper frame, or nil to defer to UIKit. While a column transition runs, the
    /// transition owns the geometry, so UIKit's layout passes get the wrapper's current frame back (a no-op).
    func columnFrameForTopWrapper(of viewController: UIViewController) -> CGRect? {
        guard isColumnar, view.bounds.width > 0 else { return nil }
        if isRunningColumnTransition, let wrapper = viewController.viewIfLoaded?.superview, Self.isWrapper(wrapper) {
            return wrapper.frame
        }
        guard viewController === topViewController else { return nil }
        return currentFrames(makeLayout()).last
    }

    /// Hook target: the top view controller's view frame inside its wrapper (wrapper coordinates).
    func columnFrameForTopView(of viewController: UIViewController) -> CGRect? {
        guard isColumnar, view.bounds.width > 0 else { return nil }
        // Includes the outgoing column once we've lifted it into our own holder: UIKit still lays it out as if it
        // were in its wrapper, which would snap it to the holder's origin.
        if isRunningColumnTransition, let columnView = viewController.viewIfLoaded, columnView.superview != nil {
            return columnView.frame
        }
        return columnFrameForTopWrapper(of: viewController).map { CGRect(origin: .zero, size: $0.size) }
    }

    private var topWrapperView: UIView? {
        guard let superview = topViewController?.viewIfLoaded?.superview, Self.isWrapper(superview) else { return nil }
        return superview
    }

    static func isWrapper(_ view: UIView?) -> Bool {
        guard let view else { return false }
        return NSStringFromClass(type(of: view)) == "UIViewControllerWrapperView"
    }

    /// Tweetie's _updateLayout:. Lays out every column for the current offset / back drag / dismissal.
    func applyColumnLayout() {
        interactivePopGestureRecognizer?.isEnabled = !isColumnar
        // Only act as our own delegate while columnar. UIKit's swipe-back stops driving pops when the delegate
        // implements animationControllerFor: at all (even returning nil), so compact must have no delegate.
        if !isRunningColumnTransition {
            if isColumnar, delegate == nil {
                delegate = self
            } else if !isColumnar, delegate === self {
                delegate = nil
            }
        }
        guard isColumnar, view.bounds.width > 0 else {
            // Once, on the way out: compact is a plain navigation stack, left to UIKit (and the app) from then on.
            if hasColumnState { tearDownColumns() }
            return
        }
        let stack = viewControllers
        guard !stack.isEmpty else { return }
        hasColumnState = true
        // Columns draw their own chrome, as in Tweetie.
        if !isNavigationBarHidden {
            setNavigationBarHidden(true, animated: false)
            columnModeDidChange()
        }

        let layout = makeLayout()
        if dragMode == nil, !isStripMoving, !isRunningColumnTransition {
            settleStripIntoLayout(layout)
        }
        let frames = currentFrames(layout)

        if isBrowsing { syncBrowseScrollView(browseLayout(frames: frames)) }
        // While the overview is up, the top column moves into a card like the others: UIKit keeps laying out its
        // wrapper (when the toolbar or tab bar come and go), which would fight the overview's motion. It goes back
        // once the overview has closed, where card and wrapper sit in the same place.
        if let top = stack.last, !isRunningColumnTransition {
            if isBrowsing, let wrapper = top.viewIfLoaded?.superview, Self.isWrapper(wrapper) {
                parkedWrapper = wrapper
                wrapper.layer.shadowOpacity = 0
                Self.setBlur(0, on: wrapper)
            } else if !isBrowsing, let wrapper = parkedWrapper {
                if let card = cards[ObjectIdentifier(top)], card.hostsView {
                    wrapper.addSubview(top.view)
                }
                parkedWrapper = nil
            }
        }
        let carded = isBrowsing && !isRunningColumnTransition ? stack.count : stack.count - 1
        for (index, viewController) in stack.enumerated().prefix(carded) {
            let card = card(for: viewController)
            card.adoptView()
            let backSwiped = backDrag > 0 && index >= backSwipeFrom
            let shrink = backSwiped ? Self.backSwipeScale(backSwipeProgress) : 1
            card.place(
                in: frames[index], transform: columnTransform(for: index, frames: frames).scaledBy(x: shrink, y: shrink)
            )
            Self.setBlur(backSwiped ? Self.backSwipeBlur * backSwipeProgress : 0, on: card)
            card.cornerRadius = columnCornerRadius(for: index)
            columnHost.bringSubviewToFront(card)
            attachEdgeShadow(for: viewController, index: index)
            // A column showing only a sliver (the pinned root's peek, a piled strip) keeps touches away from its
            // content, so a stray tap can't select a row and replace everything after it. The touch lands on the
            // card instead, where a tap reveals the column and a drag still scrolls or browses.
            let visibleWidth =
                index + 1 < frames.count ? frames[index + 1].minX - frames[index].minX : frames[index].width
            viewController.view.isUserInteractionEnabled = !isBrowsing && visibleWidth >= frames[index].width / 2
        }
        // The top too, while it's in the overview (opening, open or closing): taps there pick it.
        stack.last?.viewIfLoaded?.isUserInteractionEnabled = !isBrowsing || isRunningColumnTransition
        stack.forEach(attachScrollHandoff(to:))

        if !isRunningColumnTransition {
            let leading = Set(stack.prefix(carded).map(ObjectIdentifier.init))
            let live = Set(stack.map(ObjectIdentifier.init))
            for (key, card) in cards where !leading.contains(key) {
                if !live.contains(key), let removed = card.viewController {
                    // Left the stack without a transition (a non-animated pop or setViewControllers): it leaves the
                    // screen, and goes back to being a plain view controller.
                    setAppeared(removed, false)
                    removed.viewIfLoaded?.isUserInteractionEnabled = true
                    if let removedView = removed.viewIfLoaded { ColumnCardView.clearCorners(of: removedView) }
                }
                card.removeFromSuperview()
                cards[key] = nil
            }
            for (key, shadow) in edgeShadows where !live.contains(key) {
                shadow.removeFromSuperview()
                edgeShadows[key] = nil
            }
            for (key, handoff) in scrollHandoffs where !live.contains(key) {
                handoff.detach()
                scrollHandoffs[key] = nil
            }
        }

        if let top = stack.last, !isRunningColumnTransition, let wrapper = topWrapperView {
            // A back swipe shrinks the column a little as it goes (with fading and blur, in the decorations).
            let shrink = Self.backSwipeScale(backSwipeProgress)
            wrapper.place(
                in: frames[frames.count - 1],
                transform: columnTransform(for: stack.count - 1, frames: frames).scaledBy(x: shrink, y: shrink))
            if top.view.frame != wrapper.bounds { top.view.frame = wrapper.bounds }
            // On the (unclipped) wrapper, so the blur falls off past the column's rounded, clipped edges.
            Self.setBlur(Self.backSwipeBlur * backSwipeProgress, on: wrapper)
            // The wrapper casts the card's shadow (the column's view clips to its corners).
            ColumnCardView.applyShadow(
                to: wrapper, around: wrapper.bounds, radius: columnCornerRadius(for: stack.count - 1))
            ColumnCardView.applyCorners(columnCornerRadius(for: stack.count - 1), to: top.view)
            attachEdgeShadow(for: top, index: stack.count - 1)
        }
        applyDecorations(stack: stack, layout: layout, frames: frames)
        if !isRunningColumnTransition, isAppeared(self) {
            // Leading columns are on screen, so they stay appeared even though UIKit disappeared them when they stopped being top.
            stack.dropLast().forEach { setAppeared($0, true) }
        }
        overlay?.update(
            frames: frames, stopMarkers: layout.stopOffsets.compactMap { layout.frames(offset: $0).last?.minX },
            in: view)
    }

    /// Hook target (after UIKit positions its bar): keep the (hidden) system bar over the top column.
    func positionNavigationBarOverTopColumn() {
        guard isColumnar, let top = topViewController, let frame = columnFrameForTopWrapper(of: top) else { return }
        navigationBar.bounds.size.width = frame.width
        navigationBar.center.x = frame.midX
    }

    private func card(for viewController: UIViewController) -> ColumnCardView {
        let key = ObjectIdentifier(viewController)
        if let card = cards[key] { return card }
        let card = ColumnCardView(viewController: viewController)
        columnHost.addSubview(card)
        cards[key] = card
        return card
    }

    /// Tweetie's leftColumnDimmer: a column darkens (up to ~0.4) as newer columns cover it.
    private func coverageDim(at index: Int, in frames: [CGRect]) -> CGFloat {
        guard index + 1 < frames.count else { return 0 }
        let frame = frames[index]
        let visible = max(0, min(frames[index + 1].minX, view.bounds.maxX) - frame.minX)
        return min(max(0.5 * (1 - (visible + 100) / frame.width), 0), 1)
    }

    /// Lets column `viewController`'s main scroll view hand a downward pull at its top over to dismissing the column.
    private func attachScrollHandoff(to viewController: UIViewController) {
        guard let columnView = viewController.viewIfLoaded,
            let scrollView = viewController.contentScrollView(for: .top) ?? Self.firstScrollView(in: columnView)
        else { return }
        let key = ObjectIdentifier(viewController)
        if scrollHandoffs[key]?.scrollView === scrollView { return }
        scrollHandoffs[key]?.detach()
        let handoff = ScrollDismissHandoff(scrollView: scrollView)
        handoff.shouldBegin = { [weak self, weak viewController] in
            guard let self, let viewController, isColumnar, !isRunningColumnTransition, !isBrowsing, dragMode == nil,
                let index = viewControllers.firstIndex(of: viewController),
                dismissal == nil || dismissal?.index == index
            else { return false }
            beginDismissal(of: index)
            return true
        }
        handoff.scrollBegan = { [weak self, weak viewController] in
            // Scrolling a column focuses it right away (rather than when the finger lifts, which would reveal it anyway).
            guard let self, let viewController, isColumnar, !isRunningColumnTransition, !isBrowsing,
                let index = viewControllers.firstIndex(of: viewController)
            else { return }
            // Only if it isn't fully in view already (then it's only being read, not worked in).
            guard !isColumnInView(index, in: currentFrames(makeLayout())) else { return }
            revealedOnScroll = true
            reveal(columnAt: index)
        }
        handoff.changed = { [weak self] distance in
            guard self?.dismissal != nil else { return }
            self?.updateDismissal(translation: distance)
        }
        handoff.ended = { [weak self] velocity in self?.endDismissal(velocity: velocity) }
        handoff.cancelled = { [weak self] in self?.endDismissal(velocity: 0, cancelled: true) }
        scrollHandoffs[key] = handoff
    }

    private static func firstScrollView(in view: UIView) -> UIScrollView? {
        var queue = [view]
        while !queue.isEmpty {
            let next = queue.removeFirst()
            if let scrollView = next as? UIScrollView { return scrollView }
            queue.append(contentsOf: next.subviews)
        }
        return nil
    }

    /// Hangs Tweetie's edge shadow off a column's leading edge, beside its view in the same superview.
    private func attachEdgeShadow(for viewController: UIViewController, index: Int) {
        guard !isCardStyle else {
            // Cards on the void are separated by dimming; Tweetie's straight shadow strips don't suit rounded cards.
            edgeShadows.removeValue(forKey: ObjectIdentifier(viewController))?.removeFromSuperview()
            return
        }
        guard index > 0, let columnView = viewController.viewIfLoaded, let host = columnView.superview else { return }
        let key = ObjectIdentifier(viewController)
        let shadow = edgeShadows[key] ?? ColumnEdgeShadow()
        edgeShadows[key] = shadow
        if shadow.superview !== host { host.insertSubview(shadow, belowSubview: columnView) }
        layoutEdgeShadow(shadow, beside: columnView)
    }

    private func layoutEdgeShadow(_ shadow: UIView, beside columnView: UIView) {
        let column = columnView.frame
        shadow.frame = CGRect(
            x: column.minX - ColumnEdgeShadow.reach, y: column.minY, width: ColumnEdgeShadow.reach,
            height: column.height)
    }

    /// Columns are inset cards (rather than Tweetie's edge-to-edge panels).
    private var isCardStyle: Bool { settings.cardStyle }

    /// Everything about the columns besides their frames: which piled columns show, dimming, edge shadows, the
    /// root's stack shadow, the grabber, and the throwaway indicator. Values are continuous in the frames, so the
    /// same call inside a transition's animation (with the end state) animates them rather than snapping at the end.
    private func applyDecorations(stack: [UIViewController], layout: ColumnLayout, frames: [CGRect]) {
        // Tweetie draws only the newest of the columns piled at the stack position (and the root's peek, if pinned).
        let stacked = layout.stackedIndices(in: frames)
        let pinnedRootPeeks = layout.minimumX(at: 1) > 0
        let liftedFrom = dismissal?.index ?? stack.count
        let liftProgress = min(1, max(0, dismissal?.translation ?? 0) / settings.popDistance)
        let openness = min(max(browseOpenness, 0), 1)

        let poses = isBrowsing ? browseLayout(frames: frames).pose : nil
        // The top column (in UIKit's wrapper, or a card during the overview) only changes visibility in the overview,
        // far off screen.
        let topAlpha =
            (1 + ((poses?(stack.count - 1).alpha ?? 1) - 1) * openness) * Self.backSwipeAlpha(backSwipeProgress)
        topWrapperView?.alpha = topAlpha
        if let top = stack.last, let card = cards[ObjectIdentifier(top)] {
            card.alpha = topAlpha
            card.dimmer.alpha = 0
            card.shadowStrength = 1
        }
        for (index, viewController) in stack.enumerated().dropLast() {
            guard let card = cards[ObjectIdentifier(viewController)] else { continue }
            // A piled card's shadow would only darken the pile further: a card casts in proportion to how much of its
            // leading edge shows beside the one under it, and fully in the overview. Continuous in the frames (and
            // the overview's openness), so pushes, pops and the overview fade it rather than switch it.
            let exposedEdge = index > 0 ? frames[index].minX - frames[index - 1].minX : 0
            let exposure = min(max(exposedEdge / Self.shadowRevealDistance, 0), 1)
            card.shadowStrength = exposure + (1 - exposure) * openness
            let isLifted = index >= liftedFrom
            // While swiping down, the column that will become the top shows behind the lifted ones (it starts
            // fully covered, so this doesn't visibly change anything); the rest stay put until release.
            let becomesTop = index == liftedFrom - 1
            let isRootPeek = index == 0 && pinnedRootPeeks
            let visibleStrip = frames[index + 1].minX - frames[index].minX
            if isCardStyle || isLifted || becomesTop || isRootPeek {
                // Cards stay opaque: a covered card is hidden by the one on top of it anyway, and fading one shows
                // the cards behind through it.
                card.alpha = backDrag > 0 && index >= backSwipeFrom ? Self.backSwipeAlpha(backSwipeProgress) : 1
            } else if stacked.contains(index), index != stacked.last {
                card.alpha = 0
            } else {
                // A piled strip only a few points wide reads as a glitch (our widths don't line stops up with the
                // pile the way Tweetie's 476pt columns did); fade it out as it narrows instead of popping it.
                card.alpha = min(max((visibleStrip - 4) / (Self.minimumStrip - 4), 0), 1)
            }
            let dim = isRootPeek ? 0 : coverageDim(at: index, in: frames)
            // Lifted columns brighten as they come up, so the stack reads as separate cards.
            if let pose = poses?(index) {
                card.dimmer.alpha = dim * (1 - openness)
                // Opaque while moving between the strip and the browser: piled columns converge exactly under the
                // one that stays visible, so they need no fading (fading them shows them through each other).
                card.alpha = 1 + (pose.alpha - 1) * openness
            } else {
                card.dimmer.alpha = isLifted ? dim * (1 - liftProgress) : dim
            }
        }
        for (index, viewController) in stack.enumerated().dropFirst() {
            // Rectangular shadows don't suit a lifted or browsed, rounded column; fade them as the corners round.
            edgeShadows[ObjectIdentifier(viewController)]?.alpha = 1 - min(1, columnCornerRadius(for: index) / 12)
        }
        browseBackdrop.alpha = 0.35 * openness
        columnHost.sendSubviewToBack(browseBackdrop)

        let rootCard = stack.first.flatMap { cards[ObjectIdentifier($0)] }
        let hasStack = frames.count > 1

        // Root shadow: Tweetie picks iPad-sidebar-shadow, -1, or -2 by how many columns are piled up.
        if hasStack, settings.pinsRoot, !isCardStyle, let rootCard {
            let depth = stacked.filter { $0 > 0 }.count
            let name =
                depth <= 1 ? "iPad-sidebar-shadow" : depth == 2 ? "iPad-sidebar-shadow-1" : "iPad-sidebar-shadow-2"
            if name != rootShadowName {
                if rootShadowName != nil {
                    let fade = CATransition()
                    fade.type = .fade
                    fade.duration = 0.2
                    rootShadow.layer.add(fade, forKey: "contents")
                }
                rootShadowName = name
                rootShadow.image = UIImage(named: name, in: .module, with: nil)?.resizableImage(
                    withCapInsets: UIEdgeInsets(top: 41, left: 0, bottom: 40, right: 0), resizingMode: .stretch)
            }
            // Tweetie's image is light page edges drawn for its dark sidebar: right where columns pile against the
            // root's peek it reads as the stack's edge, but over the root's own content it's a pale slab. So it only
            // shows against the pile, fading out as column 1 moves away from it.
            let target = CGRect(x: frames[1].minX - 36, y: frames[1].minY, width: 41, height: frames[1].height)
            if rootShadow.superview == nil {
                UIView.performWithoutAnimation {
                    rootShadow.alpha = 0
                    rootShadow.place(in: target, transform: dismissalTransform(for: 1))
                }
            }
            columnHost.insertSubview(rootShadow, aboveSubview: rootCard)
            rootShadow.place(in: target, transform: dismissalTransform(for: 1))
            let distanceFromPile = frames[1].minX - layout.pileX(at: 1)
            rootShadow.alpha = min(max(1 - distanceFromPile / 40, 0), 1) * max(0, 1 - openness * 4)
        } else {
            rootShadow.removeFromSuperview()
            rootShadowName = nil
        }

        // Grabber on the leading edge of the first visible column after the root, when pulling the stack away
        // would clear something. It moves with that column's card (beside it: a card clips its contents).
        let firstVisible = stack.indices.dropFirst().dropLast()
            .first {
                frames[$0 + 1].minX - frames[$0].minX > 1 && (cards[ObjectIdentifier(stack[$0])]?.alpha ?? 0) > 0.5
            }
            .flatMap { cards[ObjectIdentifier(stack[$0])] }
        if hasStack, frames.count > 2, let card = firstVisible {
            if grabber.superview !== columnHost { columnHost.addSubview(grabber) }
            columnHost.insertSubview(grabber, aboveSubview: card)
            grabber.bounds.size = CGSize(width: 5, height: 40)
            grabber.center = CGPoint(x: card.frame.minX - 8.5, y: card.frame.midY)
            grabber.alpha = max(0, 1 - openness * 3)
        } else {
            grabber.removeFromSuperview()
        }

        guard !isRunningColumnTransition else { return }
        // Throwaway (Tweetie's _setThrowawayState:): pulling the stack away from the root — past it with the
        // strip, or directly by dragging on the root — shows the pages; past throwawayDistance they're armed.
        let pull = clearDrag > 0 ? clearDrag : -offset
        if pull > 0, frames.count > 1, let rootCard {
            columnHost.insertSubview(throwawayIndicator, aboveSubview: rootCard)
            let gapEnd = frames.dropFirst().map(\.minX).min() ?? frames[0].maxX
            let gap = CGRect(x: gapEnd - pull, y: 0, width: pull, height: frames[0].height)
            throwawayIndicator.bounds.size = throwawayIndicator.intrinsicContentSize
            throwawayIndicator.center = CGPoint(x: gap.midX, y: gap.midY)
            throwawayIndicator.alpha = min(1, pull / 40) * 0.6
            let armed = isThrowawayArmed
            if armed != throwawayIndicator.isArmed {
                throwawayIndicator.setArmed(armed, animated: true)
            }
            updateClearHaptic()
        } else if throwawayIndicator.superview != nil {
            throwawayIndicator.alpha = 0
            throwawayIndicator.setArmed(false, animated: false)
            throwawayIndicator.removeFromSuperview()
        }
    }

    /// The clear's haptic, from the finger only (never an animation crossing the line): a light impact arming it,
    /// a lighter tick backing out, with hysteresis so it can't chatter at the line (as UIKit's edge feedback).
    private func updateClearHaptic() {
        let fingerPulling = dragMode == .clear || (dragMode == .scroll && clearDrag > 0)
        guard fingerPulling, viewControllers.count > 1 else {
            if clearDrag <= 0 { clearHapticArmed = false }
            return
        }
        if !clearHapticArmed, clearDrag > settings.throwawayDistance {
            clearHapticArmed = true
            throwawayFeedback.impactOccurred(intensity: 0.7)
        } else if clearHapticArmed, clearDrag < settings.throwawayDistance - Self.clearHapticHysteresis {
            clearHapticArmed = false
            clearDisarmFeedback.selectionChanged()
        }
    }

    private static let clearHapticHysteresis: CGFloat = 16

    private var isThrowawayArmed: Bool {
        viewControllers.count > 1 && clearDrag > settings.throwawayDistance
    }

    /// Entering or leaving columns (unfolding, folding, rotating a big phone): columns lay their content out again,
    /// for their own header and margins (card) or the system's (a plain navigation stack).
    private func columnModeDidChange() {
        for viewController in viewControllers {
            viewController.viewIfLoaded?.setNeedsLayout()
        }
    }

    private func tearDownColumns() {
        hasColumnState = false
        if isBrowsing {
            tabBarController?.setTabBarHidden(false, animated: false)
            browseLanding = nil
        }
        for handoff in scrollHandoffs.values { handoff.detach() }
        scrollHandoffs.removeAll()
        if let top = viewControllers.last, let wrapper = parkedWrapper, top.viewIfLoaded?.superview !== wrapper {
            wrapper.addSubview(top.view)
        }
        parkedWrapper = nil
        // Compact width is a plain navigation stack: no card corners, no disabled content.
        for viewController in viewControllers {
            viewController.viewIfLoaded?.isUserInteractionEnabled = true
            if let columnView = viewController.viewIfLoaded { ColumnCardView.clearCorners(of: columnView) }
        }
        // Leaving columnar mode: only the top view controller stays on screen.
        if !cards.isEmpty { viewControllers.dropLast().forEach { setAppeared($0, false) } }
        if let index = pendingBrowseRemoval {
            // Columns flicked off in the overview were on their way out.
            pendingBrowseRemoval = nil
            setViewControllers(Array(viewControllers.prefix(index)), animated: false)
        }
        for card in cards.values {
            if card.hostsView { card.viewController?.view.removeFromSuperview() }
            card.removeFromSuperview()
        }
        cards.removeAll()
        edgeShadows.values.forEach { $0.removeFromSuperview() }
        edgeShadows.removeAll()
        rootShadow.removeFromSuperview()
        grabber.removeFromSuperview()
        throwawayIndicator.removeFromSuperview()
        topWrapperView?.transform = .identity
        if isNavigationBarHidden {
            setNavigationBarHidden(false, animated: false)
            columnModeDidChange()
        }
        offset = max(offset, 0)
        resetGestureSprings()
        topWrapperView?.alpha = 1
        topWrapperView?.layer.shadowOpacity = 0
        if let wrapper = topWrapperView { Self.setBlur(0, on: wrapper) }
        isBrowsing = false
        isBrowserOpen = false
        browseShield.isHidden = true
        browseBackdrop.alpha = 0
    }

    // MARK: Appearance

    /// UIViewController's private appearance state: 0 disappeared, 1 appearing, 2 appeared, 3 disappearing.
    private func isAppeared(_ viewController: UIViewController) -> Bool {
        guard viewController.responds(to: NSSelectorFromString("_appearState")),
            let state = (viewController.value(forKey: "_appearState") as? NSNumber)?.intValue
        else { return false }
        return state == 1 || state == 2
    }

    private func setAppeared(_ viewController: UIViewController, _ appeared: Bool) {
        guard isAppeared(viewController) != appeared else { return }
        viewController.beginAppearanceTransition(appeared, animated: false)
        viewController.endAppearanceTransition()
    }

    /// A pop's destination is already on screen as a leading column. Mark it disappeared first so UIKit's
    /// appearance callbacks for the pop stay balanced.
    private func prepareAppearance(forPopTo destination: UIViewController?) {
        recordFramesAtRequest()
        guard isColumnar, let destination, destination !== topViewController else { return }
        setAppeared(destination, false)
    }

    private func recordFramesAtRequest() {
        framesAtRequest = [:]
        guard isColumnar else { return }
        for viewController in viewControllers {
            for piece in [viewController.viewIfLoaded, edgeShadows[ObjectIdentifier(viewController)]].compactMap({ $0 })
            where piece.window != nil {
                framesAtRequest[ObjectIdentifier(piece)] = view.convert(piece.bounds, from: piece)
            }
        }
    }

    @discardableResult
    package override func popViewController(animated: Bool) -> UIViewController? {
        if viewControllers.count > 1 { prepareAppearance(forPopTo: viewControllers[viewControllers.count - 2]) }
        return super.popViewController(animated: animated)
    }

    @discardableResult
    package override func popToViewController(_ viewController: UIViewController, animated: Bool) -> [UIViewController]?
    {
        prepareAppearance(forPopTo: viewController)
        return super.popToViewController(viewController, animated: animated)
    }

    @discardableResult
    package override func popToRootViewController(animated: Bool) -> [UIViewController]? {
        prepareAppearance(forPopTo: viewControllers.first)
        return super.popToRootViewController(animated: animated)
    }

    // MARK: Transitions

    package func navigationController(
        _ navigationController: UINavigationController,
        animationControllerFor operation: UINavigationController.Operation, from fromVC: UIViewController,
        to toVC: UIViewController
    ) -> (any UIViewControllerAnimatedTransitioning)? {
        isColumnar ? ColumnTransitionAnimator(controller: self) : nil
    }

    package func navigationController(
        _ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool
    ) {
        // A gesture's pending style is for the transition it started, never a later one.
        pendingTransitionStyle = .strip
        pendingReleaseVelocity = 0
        // UIKit unwraps the disappearing view at the end of a transition; re-adopt it into its card.
        if isColumnar { applyColumnLayout() }
    }

    /// Drives a push or pop in columnar mode. Called by ColumnTransitionAnimator.
    ///
    /// Tweetie (`_insertViewController:atIndex:animated:`, `_removeViewForViewController:animated:`) inserts the
    /// column at its natural strip position and `_reveal:`s it, so the strip carries the motion. Tweetie's fixed
    /// widths always put that position off-screen; our top column flexes to fill, so a new column starts just
    /// past the trailing edge instead, and the whole strip animates to the revealed offset on Tweetie's ease.
    /// The back swipe and swipe-down finish their gesture's motion the same way.
    func runColumnTransition(_ context: any UIViewControllerContextTransitioning) {
        guard let fromVC = context.viewController(forKey: .from), let toVC = context.viewController(forKey: .to) else {
            context.completeTransition(true)
            return
        }
        isRunningColumnTransition = true
        // Leading columns can't start another transition over this one.
        columnHost.isUserInteractionEnabled = false
        stopStrip()
        let container = context.containerView
        let stack = destinationStack(endingIn: toVC)
        requestedStack = nil
        defer { framesAtRequest = [:] }
        let style = pendingTransitionStyle
        pendingTransitionStyle = .strip
        let isPush = stack.contains(fromVC)

        let fromView = context.view(forKey: .from) ?? fromVC.view!
        let fromOuter = Self.isWrapper(fromView.superview) ? fromView.superview! : fromView
        let fromStart = view.convert(fromView.bounds, from: fromView)

        // A back swipe's shrink and fade carry on with the leaving column.
        let leavingProgress = style == .slide ? backSwipeProgress : 0
        // End where Tweetie's reveal of the new last column would come to rest. Gestures end their own displacement.
        backSpring.set(0)
        clearSpring.set(0)
        rootSpring.set(0)
        rootRevealSpring.set(0)
        dismissSpring.set(0)
        dismissal = nil
        let layout = makeLayout(for: stack)
        let startOffset = offset
        offset = layout.revealOffset(for: stack.count - 1, from: min(max(offset, 0), layout.maxOffset))
        let endFrames = layout.frames(offset: offset)
        let topEnd = endFrames[endFrames.count - 1]

        // The incoming top column: from its card (pop), or from its natural strip position — but no nearer than
        // the trailing edge — so it travels in with the strip (push).
        let toView = context.view(forKey: .to) ?? toVC.view!
        let toStart: CGRect
        if let card = cards[ObjectIdentifier(toVC)], card.hostsView {
            toStart = framesAtRequest[ObjectIdentifier(toView)] ?? view.convert(card.bounds, from: card)
        } else {
            let natural = layout.frames(offset: max(startOffset, 0)).last ?? topEnd
            toStart = CGRect(
                x: max(natural.minX, view.bounds.maxX), y: topEnd.minY, width: topEnd.width, height: topEnd.height)
        }
        // Where the outgoing column (and its shadow) appear right now, before UIKit's layout pass below can move
        // the wrapper they live in (on pop it may reuse that wrapper for the incoming column, at its end frame).
        let leavingPieces: [(view: UIView, frame: CGRect)] =
            isPush
            ? []
            : [edgeShadows[ObjectIdentifier(fromVC)], fromView].compactMap { $0 }
                .filter { $0.window != nil }
                .map { ($0, framesAtRequest[ObjectIdentifier($0)] ?? view.convert($0.bounds, from: $0)) }
        #if DEBUG
            if ProcessInfo.processInfo.environment["COLUMNNAV_TRACE"] == "1" {
                print(
                    "TRACE start requested=\(framesAtRequest.count) container=\(container.frame) leaving=\(leavingPieces.map { "\(type(of: $0.view)) \($0.frame) now=\(view.convert($0.view.bounds, from: $0.view))" })"
                )
            }
        #endif
        if !toView.isDescendant(of: container) {
            if fromOuter.superview === container {
                container.insertSubview(toView, belowSubview: fromOuter)
            } else {
                container.addSubview(toView)
            }
        }
        // A leading column becoming the top leaves its card; carry its dimming over so it fades rather than snaps.
        let carriedDim = cards[ObjectIdentifier(toVC)]?.dimmer.alpha ?? 0
        if let card = cards.removeValue(forKey: ObjectIdentifier(toVC)) {
            card.removeFromSuperview()
        }
        // UIKit re-parents the incoming view into a wrapper during layout (on pop, possibly the outgoing view's
        // wrapper). Let that happen now.
        view.layoutIfNeeded()
        toView.transform = .identity
        toView.layer.shadowOpacity = 0
        let toWrapper = Self.isWrapper(toView.superview) ? toView.superview : nil

        // If UIKit put it in the outgoing column's wrapper, lift the outgoing view (and its shadow) out into a holder
        // of ours, exactly where it appears, so the wrapper can carry the incoming column on its own. Otherwise the
        // wrapper lays its child out to its own (lifted, narrow) bounds and the incoming column jumps.
        // Pops always do this, so the leaving column falls from exactly where it was. The holder lives in our own
        // view, not the container: UIKit moves the container itself (it starts a pop where the old top was).
        var leavingHolder: UIView?
        if !isPush {
            let holder = UIView(frame: view.bounds)
            holder.isUserInteractionEnabled = false
            view.insertSubview(holder, belowSubview: browseShield)
            for (piece, visible) in leavingPieces {
                holder.addSubview(piece)
                piece.transform = .identity
                if piece === fromView, leavingProgress > 0 {
                    // Keep it shrunk as the back swipe left it (its visible frame is the scaled one).
                    let shrink = Self.backSwipeScale(leavingProgress)
                    piece.bounds.size = CGSize(width: visible.width / shrink, height: visible.height / shrink)
                    piece.center = CGPoint(x: visible.midX, y: visible.midY)
                    piece.transform = CGAffineTransform(scaleX: shrink, y: shrink)
                } else {
                    piece.frame = visible
                }
            }
            holder.alpha = Self.backSwipeAlpha(leavingProgress)
            // The blur goes with it, off the wrapper (which may carry the incoming column now) onto the holder.
            Self.setBlur(Self.backSwipeBlur * leavingProgress, on: holder)
            Self.setBlur(0, on: fromOuter)
            if let toWrapper { Self.setBlur(0, on: toWrapper) }
            leavingHolder = holder
            // The leaving column keeps its card shadow on the way out.
            ColumnCardView.applyShadow(to: holder, around: fromView.frame)
            if fromOuter !== fromView, fromOuter !== toWrapper { fromOuter.layer.shadowOpacity = 0 }
        }

        // Pin the incoming wrapper to the whole container, untransformed (the frozen hooks keep UIKit from moving it),
        // and animate the column's view inside it in container coordinates.
        let toOuter: UIView = toWrapper ?? toView
        if let toWrapper {
            toWrapper.transform = .identity
            toWrapper.frame = container.bounds
        }
        if isPush {
            container.bringSubviewToFront(toOuter)
        } else if leavingHolder != nil {
            // Already above the container.
        } else if fromOuter.superview === container, toOuter.superview === container {
            container.insertSubview(toOuter, belowSubview: fromOuter)
        }
        if let toHost = toView.superview { toView.frame = toHost.convert(toStart, from: view) }
        // Out of its card, the incoming column rounds itself.
        ColumnCardView.applyCorners(0, to: toView)
        toView.layoutIfNeeded()
        let toDimmer = UIView()
        toDimmer.backgroundColor = .black
        toDimmer.isUserInteractionEnabled = false
        toDimmer.alpha = carriedDim
        if carriedDim > 0, let toHost = toView.superview {
            toHost.insertSubview(toDimmer, aboveSubview: toView)
            toDimmer.frame = toView.frame
        }
        attachEdgeShadow(for: toVC, index: stack.count - 1)

        // The outgoing top column: becomes a leading card (push) or leaves (pop).
        var leaving: [UIView] = []
        if isPush {
            let card = card(for: fromVC)
            card.place(in: fromStart, transform: .identity)
            card.adoptView()
            card.layoutIfNeeded()
            fromOuter.transform = .identity
            // The emptied wrapper lingers until UIKit removes it at the end.
            if fromOuter !== fromView { fromOuter.layer.shadowOpacity = 0 }
            if let index = stack.firstIndex(of: fromVC) { attachEdgeShadow(for: fromVC, index: index) }
        } else {
            let leaver = leavingHolder ?? fromOuter
            leaving.append(leaver)
            if let shadow = edgeShadows[ObjectIdentifier(fromVC)], !shadow.isDescendant(of: leaver) {
                leaving.append(shadow)
            }
        }
        let live = Set(stack.dropLast().map(ObjectIdentifier.init))
        for (key, card) in cards where !live.contains(key) {
            leaving.append(card)
        }
        // Columns this transition removes; held strongly so they can get their disappearance callbacks.
        let removedColumns = cards.values.compactMap(\.viewController).filter { !stack.contains($0) && $0 !== fromVC }

        // Every moving piece is interpolated from one progress spring and laid out together each frame, so the
        // shadows, dimmers and rounded masks stay locked to their columns (separately animated Core Animation
        // properties drift apart mid-flight).
        typealias Placement = (center: CGPoint, size: CGSize, transform: CGAffineTransform, cornerRadius: CGFloat)
        func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
        func lerp(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
            CGRect(
                x: lerp(a.minX, b.minX, t), y: lerp(a.minY, b.minY, t), width: lerp(a.width, b.width, t),
                height: lerp(a.height, b.height, t))
        }
        func lerp(_ a: CGAffineTransform, _ b: CGAffineTransform, _ t: CGFloat) -> CGAffineTransform {
            CGAffineTransform(
                a: lerp(a.a, b.a, t), b: lerp(a.b, b.b, t), c: lerp(a.c, b.c, t), d: lerp(a.d, b.d, t),
                tx: lerp(a.tx, b.tx, t), ty: lerp(a.ty, b.ty, t))
        }
        let leadingColumns = Array(stack.dropLast())
        let cardStarts: [Placement] = leadingColumns.map { viewController in
            let card = card(for: viewController)
            card.adoptView()
            return (card.center, card.bounds.size, card.transform, card.cornerRadius)
        }
        let startFrames =
            cardStarts.map {
                CGRect(
                    x: $0.center.x - $0.size.width / 2, y: $0.center.y - $0.size.height / 2, width: $0.size.width,
                    height: $0.size.height)
            } + [toStart]
        let leavingStarts = leaving.map(\.transform)
        let leavingEnds: [CGAffineTransform] = leaving.map { piece in
            let t = piece.transform
            switch style {
            case .slide, .strip:
                let distance = view.bounds.maxX - view.convert(piece.bounds, from: piece).minX + 40
                var end = t
                end.tx += distance
                return end
            case .dismissDown:
                var end = t
                end.ty = view.bounds.height + 40
                return end
            }
        }
        let indicatorStart = throwawayIndicator.superview == nil ? 0 : throwawayIndicator.alpha

        let applyProgress = { [self] (progress: CGFloat) in
            var frames: [CGRect] = []
            for (index, viewController) in leadingColumns.enumerated() {
                let card = card(for: viewController)
                let start = cardStarts[index]
                let frame = lerp(startFrames[index], endFrames[index], progress)
                card.place(in: frame, transform: lerp(start.transform, .identity, progress))
                card.cornerRadius = lerp(start.cornerRadius, 0, progress)
                // The column's content (table cells) resizes with it.
                card.layoutIfNeeded()
                frames.append(frame)
            }
            var topFrame = lerp(toStart, topEnd, progress)
            if !isPush, !isCardStyle {
                // Edge to edge, the column becoming the top reaches its final trailing edge from the start, so no
                // background shows between it and the column leaving past it (the new width starts under that
                // column). Cards on the void just grow into place.
                topFrame.size.width = max(topFrame.width, topEnd.maxX - topFrame.minX)
            }
            frames.append(topFrame)
            if let toHost = toView.superview {
                toView.frame = toHost.convert(topFrame, from: view)
                // Its wrapper (pinned to the container while the column moves inside it) casts the card's shadow.
                if let toWrapper { ColumnCardView.applyShadow(to: toWrapper, around: toView.frame) }
            }
            toView.layoutIfNeeded()
            toDimmer.frame = toView.frame
            toDimmer.alpha = carriedDim * max(0, 1 - progress)
            if let shadow = edgeShadows[ObjectIdentifier(toVC)] { layoutEdgeShadow(shadow, beside: toView) }
            // Dimming, piled-column visibility, shadows and the grabber follow the same frames.
            applyDecorations(stack: stack, layout: layout, frames: frames)
            for (index, piece) in leaving.enumerated() {
                piece.transform = lerp(leavingStarts[index], leavingEnds[index], progress)
            }
            if leavingProgress > 0 {
                // Back-swiped columns keep fading as they go.
                let alpha = Self.backSwipeAlpha(leavingProgress) * max(0, 1 - progress)
                leavingHolder?.alpha = alpha
                for piece in leaving where piece is ColumnCardView { piece.alpha = alpha }
            }
            throwawayIndicator.alpha = indicatorStart * max(0, 1 - progress * 3)
        }
        let finish = { [self] in
            for view in leaving {
                view.transform = .identity
                Self.setBlur(0, on: view)
                if let card = view as? ColumnCardView {
                    card.cornerRadius = 0
                    if card.hostsView { card.viewController?.view.removeFromSuperview() }
                    card.removeFromSuperview()
                    cards = cards.filter { $0.value !== card }
                }
            }
            transitionSpring.onChange = nil
            fromView.cornerConfiguration = .corners(radius: .fixed(0))
            fromView.transform = .identity
            toDimmer.removeFromSuperview()
            removedColumns.forEach { setAppeared($0, false) }
            isRunningColumnTransition = false
            context.completeTransition(!context.transitionWasCancelled)
            if let leavingHolder {
                fromView.removeFromSuperview()
                leavingHolder.removeFromSuperview()
            }
            focusedColumn = stack.count - 1
            columnHost.isUserInteractionEnabled = true
            didComeToRest(at: offset)
            applyColumnLayout()
            if needsFoldSettle {
                needsFoldSettle = false
                foldDidChange()
            }
        }

        // Tweetie's reveal is a geometric ease-out (each 60 Hz frame covers 20% of what's left), which a critically
        // damped spring matches. Gesture-driven pops carry the release velocity on, relative to the leaving column's
        // remaining travel, with a touch of overshoot.
        let releaseVelocity = pendingReleaseVelocity
        pendingReleaseVelocity = 0
        let leavingStart = leavingPieces.last?.frame ?? fromStart
        let remaining =
            style == .dismissDown
            ? view.bounds.height + 40
            : view.bounds.maxX - leavingStart.minX + 40
        transitionSpring.onChange = { applyProgress($0) }
        transitionSpring.set(0)
        if style == .strip {
            driver.animate(transitionSpring, to: 1, velocity: 0, response: 0.42, dampingRatio: 1, completion: finish)
        } else {
            // UIKit's sheet rule (UISheetInteraction): a fast flick (over 1000 pt/s) settles with a little bounce,
            // anything slower critically damped; quick either way.
            let velocity = remaining > 0 ? max(0, releaseVelocity) / remaining : 0
            let flicked = abs(releaseVelocity) >= 1000
            driver.animate(
                transitionSpring, to: 1, velocity: velocity, response: 0.344, dampingRatio: flicked ? 0.8 : 1,
                completion: finish)
        }
        #if DEBUG
            TransitionTrace.start(["to": toView, "from": fromView], in: view)
        #endif
    }

    // MARK: Reveal

    /// Tweetie's _reveal:animated:: the smallest scroll that shows the column fully (eased, landing exactly). One
    /// already in full view just takes the focus (Tweetie re-snapped to the nearest stop, which could move it out
    /// again).
    private func reveal(columnAt index: Int) {
        guard isColumnar else { return }
        let layout = makeLayout()
        guard layout.stripOrigins.indices.contains(index) else { return }
        focusedColumn = index
        updateVerticalBarItems()
        if index == 0, viewControllers.count > 1 {
            // The root: everything after it slides aside together, as one block, instead of the strip scrolling back
            // (which peels each column off the pile at its own pace).
            let extent = rootRevealExtent(layout)
            if extent > 0.5 { setRootReveal(extent) }
            return
        }
        // Anything else: the block comes back (if the root was revealed), and the strip reveals the column.
        if rootReveal != 0 { setRootReveal(0) }
        let target = layout.revealOffset(for: index, from: offset)
        guard abs(target - offset) >= 0.5 else {
            didComeToRest(at: offset)
            return
        }
        isPinnedToNewest = false
        lastStop = target
        scroller.onRest = { [weak self] in self?.didComeToRest(at: target) }
        stripSpring.stop()
        scroller.easeTo(target, from: offset)
    }

    private func didComeToRest(at stop: CGFloat) {
        let layout = makeLayout()
        lastStop = stop
        isPinnedToNewest = abs(stop - layout.maxOffset) < 0.5
        leadingColumn = layout.leadingColumn(offset: stop)
        // Scrolled out of view, the focus moves to the newest column fully in view.
        let frames = layout.frames(offset: stop)
        if rootReveal == 0, !isColumnInView(focusedColumn, in: frames) {
            focusedColumn = frames.indices.last { isColumnInView($0, in: frames) } ?? leadingColumn
        }
        updateVerticalBarItems()
    }

    /// Whether column `index` is entirely on screen and not covered by the next one.
    private func isColumnInView(_ index: Int, in frames: [CGRect]) -> Bool {
        guard frames.indices.contains(index) else { return false }
        let uncovered = index == frames.count - 1 || frames[index + 1].minX >= frames[index].maxX - 1
        return uncovered && frames[index].minX >= -1 && frames[index].maxX <= view.bounds.maxX + 1
    }

    // MARK: Vertical bar

    /// Hands the focused column's bar buttons to the Duo's vertical bar: they go in our toolbar (as the top
    /// column's toolbar items, which the toolbar shows), preferring the vertical axis, and the column's own bar
    /// drops them meanwhile. Only while columnar with a vertical bar present.
    private func updateVerticalBarItems() {
        let stack = viewControllers
        let hosts = hostsColumnBarItemsInVerticalBar
        let source =
            hosts && stack.indices.contains(focusedColumn) ? stack[focusedColumn] as? ColumnBarItemProviding : nil
        let host = source == nil ? nil : stack.last
        // Columns never show buttons in their own bars while the vertical bar hosts them (not only the focused one).
        for viewController in stack {
            (viewController as? ColumnBarItemProviding)?.setColumnBarItemsShown(!hosts)
        }
        // Like a standard navigation stack, every column carries its own toolbar items (and the toolbar shows the top
        // column's), so pushes and pops morph matching buttons instead of removing and reinserting them.
        stack.forEach(prepareToolbarItems(for:))
        if source !== verticalBarSource || host !== verticalBarHost {
            // A column that was showing another column's buttons (as the top) goes back to its own once it isn't
            // doing that anymore.
            if let borrower = borrowingToolbarHost, borrower !== host || host === source,
                let own = borrower as? ColumnBarItemProviding
            {
                setToolbarItems(verticalBarItems(of: own), on: borrower, animated: borrower === host)
                borrowingToolbarHost = nil
            }
            // The top column's toolbar shows the focused column's buttons; when the top is the focused one, its own
            // are already there.
            if let source, let host, host !== source {
                setToolbarItems(verticalBarItems(of: source), on: host, animated: true)
                borrowingToolbarHost = host
            }
            verticalBarSource = source
            verticalBarHost = host
        }
        // The overview hides them along with the tab bar. Only a toolbar shown for them is ours to hide (in compact
        // it's the app's).
        let hidesToolbar = source == nil || isBrowserOpen
        if !hidesToolbar, isToolbarHidden {
            setToolbarHidden(false, animated: true)
            showsToolbarForVerticalBar = true
        } else if hidesToolbar, showsToolbarForVerticalBar {
            setToolbarHidden(true, animated: source != nil)
            showsToolbarForVerticalBar = false
        }
    }

    /// The vertical bar's buttons for `column`'s set: stand-ins with the same look and identifier whose taps go to
    /// whichever column is focused at the time. Any two columns with the same buttons have interchangeable items,
    /// so moving between them changes nothing in the bar.
    private func verticalBarItems(of column: ColumnBarItemProviding) -> [UIBarButtonItem] {
        column.makeColumnBarItems().map { template in
            let identifier = template.identifier ?? ""
            let item = UIBarButtonItem(
                title: template.title, image: template.image,
                primaryAction: UIAction { [weak self] _ in
                    guard let self, viewControllers.indices.contains(focusedColumn),
                        let focused = viewControllers[focusedColumn] as? ColumnBarItemProviding
                    else { return }
                    focused.performColumnBarAction(identifier)
                })
            item.identifier = template.identifier
            item.accessibilityLabel = template.title
            item.axisBehavior = .verticalPreferred
            return item
        }
    }

    /// Sets a column's toolbar items, unless it already has the same buttons (then the bar has nothing to change).
    private func setToolbarItems(_ items: [UIBarButtonItem], on viewController: UIViewController, animated: Bool) {
        guard (viewController.toolbarItems ?? []).map(\.identifier) != items.map(\.identifier) else { return }
        viewController.setToolbarItems(items, animated: animated)
    }

    /// Gives a column its own toolbar items if it has none yet (before it's pushed, so the push carries them).
    private func prepareToolbarItems(for viewController: UIViewController) {
        guard viewController.toolbarItems == nil, let column = viewController as? ColumnBarItemProviding else { return }
        viewController.toolbarItems = verticalBarItems(of: column)
    }

    package override func pushViewController(_ viewController: UIViewController, animated: Bool) {
        prepareToolbarItems(for: viewController)
        super.pushViewController(viewController, animated: animated)
    }

    package override func setViewControllers(_ viewControllers: [UIViewController], animated: Bool) {
        viewControllers.forEach(prepareToolbarItems(for:))
        // A leading column becoming the top is already on screen: as for a pop to it.
        if let newTop = viewControllers.last, self.viewControllers.contains(newTop) {
            prepareAppearance(forPopTo: newTop)
        }
        super.setViewControllers(viewControllers, animated: animated)
    }

    /// Whether the Duo's vertical bar carries the focused column's bar buttons (so columns' own bars show none).
    package var hostsColumnBarItemsInVerticalBar: Bool {
        isColumnar && settings.verticalBarItems && traitCollection.verticalBarEdge != .unspecified
    }

    // MARK: Gestures

    /// The newest column under `location` (newer columns are on top).
    private func column(at location: CGPoint, in frames: [CGRect]) -> Int? {
        frames.indices.last { frames[$0].minX <= location.x && location.x < frames[$0].maxX }
    }

    /// Tweetie's swipeView:willBeginTouches:withEvent: — a touch catches a moving stack.
    private func touchDown(at point: CGPoint) {
        revealedOnScroll = false
        // Catch anything moving (the strip, a released back swipe or root pull, the root's block sliding aside): it
        // stops under the finger, and the drag that follows picks it up from there.
        let springs = [backSpring, clearSpring, rootSpring, rootRevealSpring].filter(\.isAnimating)
        caughtMotion = isStripMoving || !springs.isEmpty
        caughtBackSwipe = backSpring.isAnimating
        stopStrip()
        springs.forEach { $0.stop() }
        touchDownOffset = offset
        touchDownColumn = column(at: point, in: currentFrames(makeLayout()))
    }

    /// Tweetie's _didReset → swipeView:shouldRevealItem: — a tap that didn't scroll reveals its column. The touch
    /// also reached the content; if that started a push or pop, let it drive instead.
    private func touchEndedWithoutDrag(isTap: Bool) {
        let index = touchDownColumn
        settleCaughtSprings()
        guard isTap, !revealedOnScroll else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let index, isColumnar, transitionCoordinator == nil, !isRunningColumnTransition,
                !isBrowsing,
                dismissal == nil
            else { return }
            reveal(columnAt: index)
        }
    }

    package func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard isColumnar, !isRunningColumnTransition else {
            return gestureRecognizer === interactivePopGestureRecognizer ? !isColumnar : false
        }
        if gestureRecognizer === swipe {
            // Even a lone root can be nudged.
            return true
        }
        if gestureRecognizer === browseLiftPan {
            let velocity = browseLiftPan.velocity(in: view)
            guard isBrowserOpen, abs(velocity.y) > abs(velocity.x) else { return false }
            // Columns still flying off from an earlier flick go now, so this one starts from the stack as it'll be.
            commitBrowseRemoval()
            guard isBrowserOpen,
                let index = browseColumn(at: browseLiftPan.location(in: view)), index > 0
            else { return false }
            // Catch a card that's still springing back from an earlier flick.
            browseLiftBase = browseLift?.index == index ? browseLiftSpring.stop() : 0
            if browseLift?.index != index { browseLiftSpring.set(0) }
            browseLift = (index, browseLiftBase)
            return true
        }
        if gestureRecognizer === dismissPan {
            guard browseOpenness == 0 else { return false }
            let velocity = dismissPan.velocity(in: view)
            let location = dismissPan.location(in: view)
            guard velocity.y > abs(velocity.x) else { return false }
            let frames = currentFrames(makeLayout())
            // Within the header band at the column's own top (it's a card, inset from the screen's top).
            guard let index = column(at: location, in: frames), location.y < frames[index].minY + Self.dismissZone,
                dismissal == nil || dismissal?.index == index
            else { return false }
            beginDismissal(of: index)
            return true
        }
        return gestureRecognizer === interactivePopGestureRecognizer ? !isColumnar : true
    }

    package func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        switch gestureRecognizer {
        case swipe:
            // The overview (open or on its way) handles its own touches: the filmstrip scrolls, taps pick.
            return isColumnar && !isRunningColumnTransition && !isBrowsing
        case browseTap:
            // A touch that stops the filmstrip coasting only stops it (as in any scroll view), rather than picking.
            return !browseScrollView.isDecelerating
        default:
            return true
        }
    }

    /// Content scroll views wait for our gestures to decide (they fail fast on the wrong axis).
    package func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        (gestureRecognizer === swipe || gestureRecognizer === dismissPan) && otherGestureRecognizer.view is UIScrollView
    }

    /// Springs everything a touch caught (but didn't start dragging) back to rest.
    private func settleCaughtSprings(except mode: DragMode? = nil) {
        if mode != .back, backDrag != 0 { driver.animate(backSpring, to: 0) }
        if mode != .clear, clearDrag != 0 { driver.animate(clearSpring, to: 0) }
        if mode != .clear, mode != .nudgeRoot, rootDrag != 0 { driver.animate(rootSpring, to: 0) }
        if mode != .scroll, mode != .clear, rootReveal != 0 {
            // Caught partway: finish whichever way is nearer.
            let extent = rootRevealExtent(makeLayout())
            if rootReveal != extent { setRootReveal(rootReveal > extent / 2 ? extent : 0) }
        }
        if caughtMotion, mode == nil, !isStripMoving {
            settle(velocity: 0, layout: makeLayout())
        }
    }

    @objc private func handleSwipe(_ swipe: ColumnSwipeGestureRecognizer) {
        let layout = makeLayout()
        let translation = swipe.translationX

        switch swipe.state {
        case .began, .changed:
            if swipe.state == .began {
                isPinnedToNewest = false
                // Rightward on the root: pull everything after it away (released partway, that opens the overview;
                // far enough, it clears them). Rightward from the top column's leading edge (the fold, when folded) or
                // the screen's leading edge: back swipe. Anything else scrolls the strip (and past the root, pulls).
                let start = swipe.firstLocation
                let backSwipes = !isCardStyle || settings.cardBackSwipeEnabled
                let seam = backSwipes ? seamColumn(at: start, in: currentFrames(layout)) : nil
                if touchDownColumn == 0, viewControllers.count == 1 {
                    // A lone root has nowhere to go but gives a little; under a stack, drags move the stack.
                    dragMode = .nudgeRoot
                    dragBase = Fluid.invertRubberBand(rootSpring.stop(), dimension: Self.rootGive)
                } else if translation > 0, let seam, viewControllers.count > 1 {
                    // A column's leading seam: it and everything after it swipe away together.
                    dragMode = .back
                    backSwipeFrom = seam
                    dragBase = backSpring.stop()
                } else if clearDrag > 0 || (translation > 0 && touchDownColumn == 0) {
                    // On the root, or catching a released root pull (from anywhere): it carries on from where it is.
                    dragMode = .clear
                    dragBase = clearSpring.stop()
                    throwawayFeedback.prepare()
                    clearDisarmFeedback.prepare()
                    rootSpring.stop()
                } else if backSwipes, caughtBackSwipe, let column = touchDownColumn, column >= backSwipeFrom {
                    dragMode = .back
                    dragBase = backSpring.stop()
                } else if backSwipes, translation > 0, start.x < Self.backSwipeZone, viewControllers.count > 1 {
                    dragMode = .back
                    backSwipeFrom = viewControllers.count - 1
                    dragBase = backSpring.stop()
                } else {
                    dragMode = .scroll
                    rootRevealBase = rootRevealSpring.stop()
                    // Only a drag that starts with the strip at its start can become a root pull; paging back that
                    // runs into the start just rubber-bands there.
                    scrollCanPullRoot = offset < 0.5
                }
                settleCaughtSprings(except: dragMode)
            }
            // Drags follow the finger exactly; springs only take over on release.
            switch dragMode {
            case .back:
                let raw = dragBase + translation
                backSpring.set(raw > 0 ? raw : Fluid.rubberBand(raw, dimension: view.bounds.width))
            case .clear:
                let raw = dragBase + translation
                setClearDrag(raw > 0 ? raw : Fluid.rubberBand(raw, dimension: view.bounds.width))
            case .nudgeRoot:
                rootSpring.set(Fluid.rubberBand(dragBase + translation, dimension: Self.rootGive))
            case .scroll:
                // Tweetie's _didScroll:: follow the finger; past the end, movement is halved. Past the root it becomes
                // the root pull (fanning the history out, then the overview or a clear), the same as dragging the root.
                var translation = translation
                if rootRevealBase > 0 {
                    // The block of columns aside from the root moves first; past it, the strip scrolls.
                    let reveal = rootRevealBase + translation
                    let extent = rootRevealExtent(layout)
                    if reveal > 0 {
                        rootRevealSpring.set(
                            reveal > extent
                                ? extent + Fluid.rubberBand(reveal - extent, dimension: view.bounds.width) : reveal)
                        offset = touchDownOffset
                        break
                    }
                    if rootReveal != 0 { rootRevealSpring.set(0) }
                    translation = reveal
                }
                let raw = touchDownOffset - translation
                if raw < 0, viewControllers.count > 1, scrollCanPullRoot {
                    offset = 0
                    setClearDrag(-raw)
                } else if raw < 0 {
                    offset = rubberBand(raw)
                } else if raw > layout.maxOffset {
                    if clearDrag != 0 { setClearDrag(0) }
                    offset = layout.maxOffset + rubberBand(raw - layout.maxOffset)
                } else {
                    if clearDrag != 0 { setClearDrag(0) }
                    offset = raw
                }
            case nil:
                break
            }
            applyColumnLayout()

        case .ended, .cancelled:
            let mode = dragMode
            dragMode = nil
            // Size class changed under the finger: compact has nothing to finish (teardown resets it all).
            guard isColumnar else { return }
            // Points per second along the finger's direction.
            let velocity = swipe.state == .ended ? swipe.releaseVelocity * 60 : 0
            // Only a drag that went somewhere commits anything; catching a motion and letting go settles it.
            let committed = swipe.state == .ended && abs(translation) > 10
            switch mode {
            case .back:
                let from = max(min(backSwipeFrom, viewControllers.count - 1), 1)
                if !(committed && backDrag + Fluid.project(velocity) > settings.popDistance
                    && popColumns(after: from - 1, style: .slide, velocity: velocity))
                {
                    driver.animate(backSpring, to: 0, velocity: velocity)
                }
            case .clear:
                releaseClearDrag(velocity: velocity, ended: committed)
            case .nudgeRoot:
                // Its rubber-banded speed: a fraction of the finger's.
                driver.animate(rootSpring, to: 0, velocity: velocity * 0.25)
            case .scroll, nil:
                if isBrowserOpen { return }
                if clearDrag > 0 {
                    releaseClearDrag(velocity: velocity, ended: committed)
                    return
                }
                if rootReveal > 0 {
                    // Released with the block partway aside: it goes all the way back or stays revealed.
                    let extent = rootRevealExtent(layout)
                    let revealed = rootReveal + Fluid.project(velocity) > extent / 2
                    setRootReveal(revealed ? extent : 0, velocity: velocity)
                    focusedColumn = revealed ? 0 : viewControllers.count - 1
                    updateVerticalBarItems()
                    return
                }
                // Strip velocity in points per 60 Hz frame (opposite the finger).
                settle(velocity: -velocity / 60, layout: layout)
            }

        default:
            break
        }
    }

    // MARK: Root pull

    /// The stack pulled off the root by `distance`: the history fans out under it and the root leans after it.
    private func setClearDrag(_ distance: CGFloat) {
        clearSpring.set(distance)
        rootSpring.set(Fluid.rubberBand(distance * 0.2, dimension: Self.rootGive / 3))
    }

    /// Release of the root pull, decided by where it would carry the stack: far enough clears everything back to
    /// the root; partway (the history peeking out) opens the overview; a little springs back.
    private func releaseClearDrag(velocity: CGFloat, ended: Bool) {
        // Clearing everything is hard to undo: it takes real travel, and a flick is projected conservatively.
        let clearProjection = clearDrag + Fluid.project(velocity, decelerationRate: 0.985)
        defer { clearHapticArmed = false }
        if ended, viewControllers.count > 1, clearDrag > Self.minimumClearTravel,
            clearProjection > settings.throwawayDistance
        {
            // A flick that clears without ever having crossed the line still gets its haptic, at release.
            if !clearHapticArmed { throwawayFeedback.impactOccurred(intensity: 0.7) }
            throwAway(velocity: velocity)
        } else if ended, viewControllers.count > 1, settings.overviewEnabled, clearDrag > Self.peekToOverview,
            abs(velocity) < Self.maximumOverviewReleaseSpeed
        {
            // Only a deliberate pull opens it: real travel, let go without flinging (a hard swipe that merely
            // passes the line is someone paging, not asking for the overview).
            // Centered on whatever was in the middle of the screen, so it doesn't jump aside.
            openBrowser(focus: columnNearestCenter(in: currentFrames(makeLayout())), fromGesture: true)
            driver.animate(clearSpring, to: 0, velocity: velocity)
            driver.animate(rootSpring, to: 0)
        } else {
            driver.animate(clearSpring, to: 0, velocity: velocity)
            driver.animate(rootSpring, to: 0)
        }
    }

    /// Root pull past which letting go opens the overview (short of the throwaway distance).
    private static let peekToOverview: CGFloat = 80
    /// Letting go of a root pull faster than this (points per second) is a fling, not a request for the overview.
    private static let maximumOverviewReleaseSpeed: CGFloat = 700
    /// A root pull must travel at least this far before even a flick can clear the stack.
    private static let minimumClearTravel: CGFloat = 120

    /// The column showing at the middle of the screen (newer columns cover older ones), measured where the overview
    /// centers its filmstrip (clear of the trailing vertical bar).
    private func columnNearestCenter(in frames: [CGRect]) -> Int {
        let middle = (view.bounds.width - safeAreaInsets.right) / 2
        if let index = frames.indices.last(where: { frames[$0].minX <= middle && middle < frames[$0].maxX }) {
            return index
        }
        return frames.indices.min { abs(frames[$0].midX - middle) < abs(frames[$1].midX - middle) } ?? 0
    }

    // MARK: Overview

    /// Starts carrying columns into the overview, centered on the newest one.
    private func beginBrowsing() {
        guard !isBrowsing else { return }
        isBrowsing = true
        scrollBrowser(toColumn: viewControllers.count - 1, animated: false)
    }

    /// Opens the overview, centered on column `focus` (the newest, if nil). Released from a pull, it lands with the
    /// widget-drop plop (bounce rewards momentum); otherwise it settles critically damped, like a folder opening.
    private func openBrowser(velocity: CGFloat? = nil, focus: Int? = nil, fromGesture: Bool = false) {
        beginBrowsing()
        if let focus { scrollBrowser(toColumn: focus, animated: false) }
        isBrowserOpen = true
        browseShield.isHidden = false
        view.bringSubviewToFront(browseShield)
        setChromeHidden(true)
        browseHaptic.prepare()
        browseLanding = (opening: true, landed: false)
        if fromGesture {
            driver.animate(
                browseOpenSpring, to: 1, velocity: velocity, response: Self.browseSpringResponse,
                dampingRatio: Self.browseSpringDamping)
        } else {
            driver.animate(
                browseOpenSpring, to: 1, velocity: velocity, response: Self.browseSettleResponse, dampingRatio: 1)
        }
    }

    /// The overview's haptic, the moment it reaches its resting state (as SpringBoard taps when a widget lands).
    private func landBrowserIfNeeded() {
        guard let landing = browseLanding, landing.opening, !landing.landed else { return }
        // On contact, as SpringBoard taps when a dropped widget touches down: the moment it arrives, a touch
        // stronger the faster it comes in.
        guard browseOpenness >= 0.99 else { return }
        browseLanding = (landing.opening, true)
        browseHaptic.play(intensity: Float(min(max(0.5 + browseOpenSpring.velocity / 12, 0.5), 1)))
    }

    /// The overview hides the tab bar and the vertical bar's buttons.
    private func setChromeHidden(_ hidden: Bool) {
        if let tabBarController, tabBarController.isTabBarHidden != hidden {
            tabBarController.setTabBarHidden(hidden, animated: true)
        }
        updateVerticalBarItems()
    }

    /// Closes the overview back into the strip, revealing column `index` if one was picked.
    private func closeBrowser(revealing index: Int?, velocity: CGFloat? = nil) {
        isBrowserOpen = false
        commitBrowseRemoval()
        browseShield.isHidden = true
        let layout = makeLayout()
        if let index, layout.stripOrigins.indices.contains(index) {
            isPinnedToNewest = false
            offset = layout.revealOffset(for: index, from: offset)
            focusedColumn = index
            updateVerticalBarItems()
        }
        if browseLift != nil { driver.animate(browseLiftSpring, to: 0) }
        setChromeHidden(false)
        browseLanding = nil
        // Closing never bounces (folder close, switcher dismiss): critically damped.
        driver.animate(
            browseOpenSpring, to: 0, velocity: velocity, response: Self.browseSettleResponse, dampingRatio: 1
        ) { [weak self] in
            guard let self, !isBrowserOpen, browseOpenness == 0 else { return }
            isBrowsing = false
            browseLift = nil
            guard !isRunningColumnTransition else { return }
            applyColumnLayout()
            didComeToRest(at: offset)
        }
    }

    @objc private func handleBrowseLift(_ pan: UIPanGestureRecognizer) {
        guard let index = browseLift?.index else { return }
        let raw = browseLiftBase + pan.translation(in: view).y
        let velocity = pan.velocity(in: view).y
        switch pan.state {
        case .began, .changed:
            browseLiftSpring.set(raw)
            applyColumnLayout()
        // SpringBoard's flick-to-kill, either way: decided where the flick would land, and never for less than 62 pt.
        case .ended where abs(raw + Fluid.project(velocity)) > max(62, settings.popDistance):
            closeColumnsFromBrowser(from: index, velocity: velocity, downward: raw + Fluid.project(velocity) > 0)
        case .ended, .cancelled, .failed:
            driver.animate(browseLiftSpring, to: 0, velocity: velocity) { [weak self] in
                if self?.browseLift?.translation == 0 { self?.browseLift = nil }
            }
        default:
            break
        }
    }

    /// Like killing an app in the switcher: column `index` and everything after it fly off (the way they were
    /// thrown), and the overview closes ranks.
    private func closeColumnsFromBrowser(from index: Int, velocity: CGFloat = 0, downward: Bool = false) {
        guard index > 0, index < viewControllers.count else { return }
        if browseLift?.index != index {
            browseLift = (index, 0)
            browseLiftSpring.set(0)
        }
        let away = downward ? view.bounds.height : -view.bounds.height
        pendingBrowseRemoval = index
        driver.animate(browseLiftSpring, to: away, velocity: velocity, response: 0.32, dampingRatio: 1) { [weak self] in
            self?.commitBrowseRemoval()
        }
    }

    /// Removes the columns a flick sent off, now (when they've gone, or because something else needs the overview
    /// before they have: another flick, a tap, leaving it).
    private func commitBrowseRemoval() {
        guard let index = pendingBrowseRemoval else { return }
        pendingBrowseRemoval = nil
        browseLift = nil
        browseLiftSpring.set(0)
        removeColumnsUnderBrowser(keeping: index)
        guard isBrowserOpen else { return }
        if viewControllers.count < 2 {
            closeBrowser(revealing: nil)
        } else {
            // The filmstrip is shorter now; settle back within it if it's past the end.
            syncBrowseScrollView(browseLayout(frames: currentFrames(makeLayout())))
            let maxOffset = max(0, browseScrollView.contentSize.width - browseScrollView.bounds.width)
            if browseScrollView.contentOffset.x > maxOffset {
                browseScrollView.setContentOffset(CGPoint(x: maxOffset, y: 0), animated: true)
            }
        }
    }

    /// Drops every column from `keeping` on without a transition (they're already off screen). The overview's poses
    /// don't depend on the columns after a given one, so the remaining columns stay where they are.
    private func removeColumnsUnderBrowser(keeping count: Int) {
        let stack = viewControllers
        guard count < stack.count else { return }
        let removed = stack[count...]
        removed.dropLast().forEach { setAppeared($0, false) }
        removed.forEach { $0.viewIfLoaded?.isHidden = true }
        let newTop = stack[count - 1]
        // It's appeared as a leading column; UIKit will appear it again as the top.
        setAppeared(newTop, false)
        setViewControllers(Array(stack.prefix(count)), animated: false)
        removed.forEach { $0.viewIfLoaded?.isHidden = false }
        focusedColumn = min(focusedColumn, count - 1)
        view.layoutIfNeeded()
        applyColumnLayout()
    }

    /// Tweetie's release: _endScroll: projects a landing with the leftover friction, _animateToDestinationOffset
    /// keeps "throwing" only if that agrees with the release direction, and the delegate picks the stop.
    private func settle(velocity: CGFloat, layout: ColumnLayout) {
        let projected = scroller.projectedLanding(from: offset, velocity: velocity)
        let throwing = velocity != 0 && (projected - touchDownOffset).sign == velocity.sign
        var target = layout.restingOffset(proposed: projected, lastStop: lastStop, throwing: throwing)
        // Tweetie only advances on a measurable throw; a finger that eases off before lifting reads as no throw and
        // the strip springs all the way back. So intent counts too: a flick over minimumAdvanceSpeed, or a drag a
        // quarter of the way to the next stop, advances to it.
        let stops = layout.stopOffsets
        let moved = offset - lastStop
        let speed = velocity * 60
        let direction: CGFloat = abs(speed) > Self.minimumAdvanceSpeed ? (speed > 0 ? 1 : -1) : (moved >= 0 ? 1 : -1)
        let ahead = stops.filter { direction > 0 ? $0 > lastStop + 0.5 : $0 < lastStop - 0.5 }
        if let next = direction > 0 ? ahead.min() : ahead.max(), !layout.hasNothingToScroll {
            let intends =
                (abs(speed) > Self.minimumAdvanceSpeed && speed.sign == direction.sign)
                || abs(moved) > abs(next - lastStop) * 0.25
            let falls = (target - lastStop) * direction < abs(next - lastStop) - 0.5
            if intends, falls { target = next }
        }
        // The stop it's headed for counts as where it is from now on: a swipe that catches it still settling is
        // measured from there, not from the stop it left (which would read as no progress and spring back).
        lastStop = target
        stripSpring.set(offset)
        driver.animate(
            stripSpring, to: target, velocity: velocity * 60, response: Self.stripSettleResponse, dampingRatio: 1
        ) { [weak self] in
            self?.didComeToRest(at: target)
        }
    }

    private static let stripSettleResponse: CGFloat = 0.45

    /// A strip flick faster than this (points per second) advances a stop however short it was.
    private static let minimumAdvanceSpeed: CGFloat = 250

    /// Throwaway release: everything goes back to the root, the other columns carrying on toward trailing at the
    /// release speed. (Tweetie kept its first content column, since its root was a sidebar; ours is content.)
    private func throwAway(velocity: CGFloat) {
        if !popColumns(after: 0, style: .slide, velocity: velocity) {
            driver.animate(clearSpring, to: 0, velocity: velocity)
            driver.animate(rootSpring, to: 0)
        }
    }

    /// A gesture's pop back to column `index`, carrying its release on with `style`. False if UIKit doesn't pop (it
    /// refuses mid-transition, say), leaving nothing pending for some later transition.
    private func popColumns(after index: Int, style: TransitionStyle, velocity: CGFloat) -> Bool {
        let stack = viewControllers
        guard index >= 0, index < stack.count - 1 else { return false }
        pendingTransitionStyle = style
        pendingReleaseVelocity = velocity
        let popped =
            index == stack.count - 2
            ? popViewController(animated: true).map { [$0] }
            : popToViewController(stack[index], animated: true)
        guard popped?.isEmpty == false else {
            pendingTransitionStyle = .strip
            pendingReleaseVelocity = 0
            return false
        }
        return true
    }

    // MARK: Swipe-down dismissal

    /// Starts dragging column `index` (and the ones after it) down, catching it if it's still springing back.
    private func beginDismissal(of index: Int) {
        stopStrip()
        if dismissal?.index == index {
            let caught = dismissSpring.stop()
            dragBase = index == 0 ? Fluid.invertRubberBand(caught, dimension: Self.rootGive) : caught
        } else {
            dragBase = 0
            dismissal = (index, 0)
            dismissSpring.set(0)
        }
    }

    private func updateDismissal(translation: CGFloat) {
        let raw = dragBase + translation
        if dismissal?.index == 0 {
            // The root can't be dismissed, but it gives a little.
            dismissSpring.set(Fluid.rubberBand(raw, dimension: Self.rootGive))
        } else {
            dismissSpring.set(raw > 0 ? raw : Fluid.rubberBand(raw, dimension: view.bounds.height))
        }
        applyColumnLayout()
    }

    /// Release: dismiss if the flick would carry the column past popDistance, else spring it home.
    private func endDismissal(velocity: CGFloat, cancelled: Bool = false) {
        guard let dismissal, isColumnar else { return }
        let dismisses = !cancelled && dismissal.translation + Fluid.project(velocity) > settings.popDistance
        if !(dismisses && popColumns(after: dismissal.index - 1, style: .dismissDown, velocity: velocity)) {
            // The root's give is rubber-banded, so it carries only a fraction of the finger's speed.
            let velocity = dismissal.index == 0 ? velocity * 0.25 : velocity
            driver.animate(dismissSpring, to: 0, velocity: velocity) { [weak self] in
                guard let self, self.dismissal?.translation == 0 else { return }
                self.dismissal = nil
                applyColumnLayout()
            }
        }
    }

    @objc private func handleDismissPan(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began, .changed:
            updateDismissal(translation: pan.translation(in: view).y)
        case .ended:
            endDismissal(velocity: pan.velocity(in: view).y)
        case .cancelled, .failed:
            endDismissal(velocity: 0, cancelled: true)
        default:
            break
        }
    }

    // MARK: Debug autopilot (the Duo inner display can't be driven by synthesized touches)

    func debugScroll(toStop stopIndex: Int) {
        let stops = makeLayout().stopOffsets
        guard stops.indices.contains(stopIndex) else { return }
        isPinnedToNewest = false
        let target = stops[stopIndex]
        scroller.onRest = { [weak self] in self?.didComeToRest(at: target) }
        stripSpring.stop()
        scroller.easeTo(target, from: offset)
    }

    func debugReveal(columnAt index: Int) {
        reveal(columnAt: index)
    }

    func debugDismiss(columnAt index: Int) {
        guard index > 0, index < viewControllers.count else { return }
        pendingTransitionStyle = .dismissDown
        dismissSpring.stop()
        if dismissal?.index != index { dismissal = (index, 60) }
        applyColumnLayout()
        popToViewController(viewControllers[index - 1], animated: true)
    }

    /// Simulates a back swipe from the top column's leading edge dragged `distance` points, then released.
    func debugBackSwipe(distance: CGFloat) {
        guard viewControllers.count > 1 else { return }
        driver.animate(backSpring, to: distance, dampingRatio: 1) { [weak self] in
            self?.pendingTransitionStyle = .slide
            self?.popViewController(animated: true)
        }
    }

    /// Holds the strip pulled past the root by `distance` points (the root pull), no release.
    func debugHoldRootOverscroll(distance: CGFloat) {
        debugHoldClear(distance: distance)
    }

    /// Holds the strip dragged `distance` points of finger travel past its end (newest column stretching over the
    /// others), no release.
    func debugHoldEndOverscroll(distance: CGFloat) {
        isPinnedToNewest = false
        stopStrip()
        offset = makeLayout().maxOffset + rubberBand(distance)
        applyColumnLayout()
    }

    /// Simulates pulling past the root far enough to arm the throwaway, then letting go.
    func debugRootOverscroll(distance: CGFloat) {
        debugHoldRootOverscroll(distance: distance)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            releaseClearDrag(velocity: 0, ended: true)
        }
    }

    /// Holds a drag on the root at `distance` (everything after it pulled away) without releasing.
    func debugHoldClear(distance: CGFloat) {
        guard viewControllers.count > 1 else { return }
        stopStrip()
        isPinnedToNewest = false
        driver.animate(clearSpring, to: distance, dampingRatio: 1)
    }

    /// Releases a held root pull as a slow release would: clears if far enough, opens the overview partway, else
    /// springs back.
    func debugReleaseClear() {
        releaseClearDrag(velocity: 0, ended: true)
    }

    /// Stand-in for the hinge (the simulator's posture can't be scripted): toggles a fold at the display's middle.
    #if DEBUG
        func debugToggleFold() {
            let hinge = view.bounds.width / 2
            debugFold = debugFold == nil ? (hinge - 20)...(hinge + 20) : nil
            foldDidChange()
        }
    #endif

    func debugOpenBrowser() { openBrowser() }
    func debugFocusBrowser(on index: Int) { scrollBrowser(toColumn: index, animated: true) }
    func debugPickFromBrowser(columnAt index: Int?) { closeBrowser(revealing: index) }
    func debugCloseFromBrowser(columnAt index: Int) { closeColumnsFromBrowser(from: index) }

    /// Holds a swipe-down at `distance` on column `index` (to inspect the lifted look) without releasing.
    func debugLift(columnAt index: Int, distance: CGFloat) {
        guard index > 0, index < viewControllers.count else { return }
        beginDismissal(of: index)
        driver.animate(dismissSpring, to: distance, dampingRatio: 1)
    }
}

final class ColumnTransitionAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    private weak var controller: ColumnNavigationController?

    init(controller: ColumnNavigationController) {
        self.controller = controller
    }

    func transitionDuration(using transitionContext: (any UIViewControllerContextTransitioning)?) -> TimeInterval {
        0.4
    }

    func animateTransition(using transitionContext: any UIViewControllerContextTransitioning) {
        guard let controller else {
            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
            return
        }
        controller.runColumnTransition(transitionContext)
    }
}

extension UIView {
    /// Sets geometry through bounds and center and assigns the transform once (inside an animation block, one
    /// animation per property; resetting the transform to identity first would queue competing transform
    /// animations, which Core Animation flags on Liquid Glass layers underneath).
    func place(in frame: CGRect, transform: CGAffineTransform) {
        bounds.size = frame.size
        center = CGPoint(x: frame.midX, y: frame.midY)
        if self.transform != transform { self.transform = transform }
    }
}

#if DEBUG
    /// Logs on-screen (presentation) frames of the transitioning views every frame, when COLUMNNAV_TRACE=1.
    @MainActor
    final class TransitionTrace: NSObject {
        private static var current: TransitionTrace?
        private let views: [String: UIView]
        private weak var space: UIView?
        private var link: CADisplayLink?
        private var frameCount = 0

        private init(views: [String: UIView], space: UIView) {
            self.views = views
            self.space = space
        }

        static func start(_ views: [String: UIView], in space: UIView) {
            guard ProcessInfo.processInfo.environment["COLUMNNAV_TRACE"] == "1" else { return }
            current?.link?.invalidate()
            let trace = TransitionTrace(views: views, space: space)
            trace.log()
            trace.link = CADisplayLink(target: trace, selector: #selector(tick))
            trace.link?.add(to: .main, forMode: .common)
            current = trace
        }

        @objc private func tick() {
            frameCount += 1
            log()
            if frameCount > 40 {
                link?.invalidate()
                link = nil
            }
        }

        private func log() {
            guard let space, let spaceLayer = space.layer.presentation() ?? Optional(space.layer) else { return }
            let parts = views.sorted { $0.key < $1.key }.map { name, view -> String in
                let layer = view.layer.presentation() ?? view.layer
                guard view.window != nil else { return "\(name)=offscreen" }
                let r = layer.convert(layer.bounds, to: spaceLayer)
                return "\(name)=(\(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))x\(Int(r.height)))"
            }
            print("TRACE \(frameCount) " + parts.joined(separator: " "))
        }
    }
#endif
