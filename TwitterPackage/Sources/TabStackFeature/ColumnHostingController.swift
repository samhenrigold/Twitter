import ColumnNavigation
import ComposableArchitecture
import SwiftUI
import TwitterUI

/// One column's screen. While it's the focused column, its buttons (New Tweet and its "…") go in iPhone Duo's vertical
/// bar; otherwise they stay in its own bar, the root's with New Tweet.
final class ColumnHostingController<Content: View>: UIHostingController<ColumnScreen<Content>>,
    ColumnBarItemProviding
{
    /// Called once the navigation controller has removed this column from its stack.
    var onRemoved: (() -> Void)?
    /// Called on each layout pass, once the column has its traits.
    var onLayout: (() -> Void)?
    /// Whether its content has been let go, its screen having left the path (see `contentWasRemoved()`).
    var isContentRemoved: Bool { chrome.isContentRemoved }
    /// Whether it's laid out as a column, drawing its own bar.
    var isLaidOutAsColumn: Bool { chrome.showsColumnBar == true }
    private let chrome: ColumnChrome
    private let stack: StoreOf<TabStack>

    init(stack: StoreOf<TabStack>, id: StackElementID?, width: CGFloat, @ContentBuilder content: () -> Content) {
        let chrome = ColumnChrome()
        self.chrome = chrome
        self.stack = stack
        super.init(rootView: ColumnScreen(stack: stack, id: id, chrome: chrome, content: content()))
        preferredContentSize.width = width
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The column's screen has left the path (closed from the store: the tab reselected, or replaced by what's opened
    /// from an earlier column), but its view lives on while it animates away. Laid out as columns, it's moved between
    /// the strip's cards on the way, and SwiftUI appears it again each time: its rows and `.task`s would keep sending
    /// actions for a screen that's no longer there. So it's swapped for a still image of itself and its content let
    /// go. On a plain stack UIKit's own transition leaves the view where it is, and its content stays for the bar's
    /// title and buttons to animate out with.
    func contentWasRemoved() {
        guard chrome.showsColumnBar == true, !chrome.isContentRemoved else { return }
        chrome.still = view.window == nil ? nil : view.snapshotView(afterScreenUpdates: false)
        chrome.isContentRemoved = true
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        if parent == nil { onRemoved?() }
    }

    override func viewWillLayoutSubviews() {
        // Decided before the bar first shows, so its buttons never flash in and out.
        if let columns = navigationController as? ColumnNavigationController {
            setColumnBarItemsShown(!columns.hostsColumnBarItemsInVerticalBar)
        }
        // The column draws its own bar exactly while the navigation controller's is hidden (it's laid out as columns).
        let showsColumnBar = navigationController?.isNavigationBarHidden == true
        if chrome.showsColumnBar != showsColumnBar { chrome.showsColumnBar = showsColumnBar }
        // As a card, the column is already inset from the screen's edges and bars: its bar and content keep plain
        // symmetric margins instead of following the system's safe area (the Duo's vertical bar, the status bar). As
        // the plain top of a navigation stack (compact width), it follows the system guides as usual.
        //
        // The card sits wherever the strip puts it, often below the status bar, but UIKit hands it the navigation
        // controller's top safe area regardless. So the header goes by where the column really is: just under
        // whatever part of the window's top safe area it actually overlaps (usually none). In portrait the bar sits
        // right at the card's top edge: it gets a little room above and below.
        // (The horizontal safe area is ignored in SwiftUI, by the column's content: see ColumnScreen.)
        var additional = UIEdgeInsets.zero
        var padding: CGFloat = 0
        if showsColumnBar, let window = view.window {
            let inherited = view.safeAreaInsets.top - additionalSafeAreaInsets.top
            let overlap = max(0, window.safeAreaInsets.top - view.convert(view.bounds.origin, to: window).y)
            // Portrait by the shape of the space the columns get (the navigation controller's), not the window's.
            let space = navigationController?.view.bounds.size ?? window.bounds.size
            padding = space.height > space.width ? Self.portraitBarPadding : 0
            additional.top = overlap + padding - inherited
        }
        if additionalSafeAreaInsets != additional { additionalSafeAreaInsets = additional }
        if chrome.barPadding != padding { chrome.barPadding = padding }
        onLayout?()
        super.viewWillLayoutSubviews()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Its timeline may only just have loaded: pulling down at its top dismisses the column.
        (navigationController as? ColumnNavigationController)?.columnContentDidLayout(self)
        // Its list is the column's content scroll view, for the bars' edge effects.
        if contentScrollView(for: .top) == nil, let scrollView = Self.mainScrollView(in: view) {
            setContentScrollView(scrollView)
        }
    }

    /// The outermost scroll view taking up most of the column's height: its content, not a carousel inside it.
    private static func mainScrollView(in view: UIView) -> UIScrollView? {
        var queue = [view]
        while !queue.isEmpty {
            let next = queue.removeFirst()
            if let scrollView = next as? UIScrollView, !(scrollView is UITextView),
                scrollView.bounds.height >= view.bounds.height / 2
            {
                return scrollView
            }
            queue.append(contentsOf: next.subviews)
        }
        return nil
    }

    private static var portraitBarPadding: CGFloat { 8 }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        // Folding, unfolding and rotating change the safe area: measure again.
        view.setNeedsLayout()
    }

    func makeColumnBarItems() -> [UIBarButtonItem] {
        let compose = UIBarButtonItem(
            title: String(localized: "New Tweet"),
            image: TwitterIcon.compose.uiImage,
            primaryAction: UIAction { [weak self] _ in self?.performColumnBarAction(Self.composeIdentifier) }
        )
        compose.identifier = Self.composeIdentifier
        // Held, its drafts, as Twitter's compose button.
        compose.menu = UIMenu(children: [
            UIAction(title: String(localized: "Drafts"), image: TwitterIcon.drafts.uiImage) { [weak self] _ in
                self?.stack.send(.composeButtonLongPressed)
            }
        ])
        compose.style = .prominent
        return [compose]
    }

    func performColumnBarAction(_ identifier: String) {
        if identifier == Self.composeIdentifier { stack.send(.composeButtonTapped) }
    }

    func setColumnBarItemsShown(_ shown: Bool) {
        if chrome.showsBarItems != shown { chrome.showsBarItems = shown }
    }

    func setColumnBarItemsInVerticalBar(_ inVerticalBar: Bool) {
        if chrome.isInVerticalBar != inVerticalBar { chrome.isInVerticalBar = inVerticalBar }
    }

    private static var composeIdentifier: String { "column.compose" }
}

/// Where a column's bar buttons go: its own bar, iPhone Duo's vertical bar (the focused column), or nowhere (the
/// others, while the vertical bar hosts the focused one's).
@MainActor
@Observable
final class ColumnChrome {
    /// Whether the column draws its own bar (laid out as a column); `nil` until its first layout.
    var showsColumnBar: Bool?
    /// Room above and below the column's own bar (in portrait).
    var barPadding: CGFloat = 0
    var showsBarItems = true
    var isInVerticalBar = false
    /// The column's screen has left the path: its content is gone, and a still image of it shows instead.
    var isContentRemoved = false
    var still: UIView?

    var placement: ColumnBarPlacement {
        isInVerticalBar ? .verticalBar : showsBarItems ? .ownBar : .hidden
    }
}

/// A column: with its own bar as a column, or in the navigation controller's bar on a plain stack (bridged from the
/// toolbar).
struct ColumnScreen<Content: View>: View {
    let stack: StoreOf<TabStack>
    /// `nil` for the root.
    let id: StackElementID?
    let chrome: ColumnChrome
    let content: Content
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        if chrome.isContentRemoved {
            // Nothing live: the column as it last looked, as it goes.
            ColumnStill(view: chrome.still)
                .ignoresSafeArea()
        } else {
            column
        }
    }

    private var column: some View {
        Group {
            // Columns draw their own bars (the navigation controller's shows only the top one, and is hidden). Before
            // the first layout says which, the size class is the best guess.
            if chrome.showsColumnBar ?? (horizontalSizeClass == .regular) {
                NavigationStack {
                    screen
                        // The card is laid out clear of the window's sides (iPhone Duo's vertical bar) but is handed
                        // their insets anyway: its content keeps plain symmetric margins.
                        .ignoresSafeArea(.container, edges: .horizontal)
                        // The room below the bar, for the content and its scroll indicator alike.
                        .safeAreaPadding(.top, chrome.barPadding)
                }
            } else {
                screen
            }
        }
        .alreadyHereShake(trigger: stack.shake.count, isActive: stack.shake.column == id)
        // A hosting controller of its own: the window's limit doesn't reach in.
        .limitsImageHeadroom()
    }

    private var screen: some View {
        content
            // Titles sit at the leading edge, never centered.
            .toolbarTitleAlignment(.leading)
            .environment(\.columnBarPlacement, chrome.placement)
            .toolbar {
                // In the root's own bar; while a column is focused, in iPhone Duo's vertical bar with its other buttons.
                // Never in the bar of a column the vertical bar isn't showing.
                if (id == nil && chrome.placement == .ownBar) || chrome.placement == .verticalBar {
                    ToolbarItem(placement: chrome.placement == .verticalBar ? .bottomBar : .topBarTrailing) {
                        // Held, its drafts, as Twitter's compose button. A bar button's hold is its menu.
                        Menu {
                            Button {
                                stack.send(.composeButtonLongPressed)
                            } label: {
                                Label("Drafts", twitterIcon: .drafts)
                            }
                        } label: {
                            Label {
                                Text("New Tweet")
                            } icon: {
                                TwitterIcon.compose.image
                            }
                        } primaryAction: {
                            stack.send(.composeButtonTapped)
                        }
                        .buttonStyle(.glassProminent)
                    }
                    .axisBehavior(.verticalPreferred)
                }
            }
    }
}

/// A snapshot of a column's view, in place of its content once its screen has left the path.
private struct ColumnStill: UIViewRepresentable {
    let view: UIView?

    func makeUIView(context: Context) -> UIView {
        view ?? UIView()
    }

    func updateUIView(_ view: UIView, context: Context) {}
}

private struct AlreadyHereShake: ViewModifier {
    let isActive: Bool
    let trigger: Int

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: CGFloat.zero, trigger: trigger) { content, offset in
                content.offset(x: isActive ? offset : 0)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(-5, duration: 0.08)
                    CubicKeyframe(3, duration: 0.08)
                    SpringKeyframe(0, duration: 0.15)
                }
            }
            .sensoryFeedback(.warning, trigger: trigger) { _, _ in isActive }
    }
}

extension View {
    /// Twitter's gentle "no": a short shake when asked to open what's already showing.
    fileprivate func alreadyHereShake(trigger: Int, isActive: Bool) -> some View {
        modifier(AlreadyHereShake(isActive: isActive, trigger: trigger))
    }
}
