import ColumnNavigation
import ComposableArchitecture
import FeedFeature
import Models
import ProfileFeature
import Routing
import SearchFeature
import SwiftUI
import TwitterUI
import UserListFeature
import WebFeature

/// A tab's navigation: one `ColumnNavigationController` whose stack is the root and the path. Horizontally regular,
/// it's Tweetie's stacked columns (each opened thing is a column after the one it came from, the strip slides and
/// snaps, columns pull down or off to close, a pull on the root throws them away or opens the overview); compact, it's
/// a plain navigation stack, with web pages in Safari's view instead of a column.
package struct TabStackView: View {
    @Bindable var store: StoreOf<TabStack>
    let title: LocalizedStringKey
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    package init(store: StoreOf<TabStack>, title: LocalizedStringKey) {
        self.store = store
        self.title = title
    }

    package var body: some View {
        ColumnStack(store: store, title: title, ids: Array(store.path.ids))
            // Under every bar, iPhone Duo's vertical bar included (which then carries the focused column's buttons):
            // the navigation controller keeps its columns clear of them itself.
            .ignoresSafeArea()
            .onChange(of: horizontalSizeClass == .regular, initial: true) { _, canShowColumns in
                store.send(.columnAvailabilityChanged(canShowColumns))
            }
            .fullScreenCover(item: safari) { page in
                SafariView(url: page.url)
                    .ignoresSafeArea()
            }
    }

    private var safari: Binding<TabStack.SafariPage?> {
        Binding {
            store.safari
        } set: { page in
            if page == nil { store.send(.safariDismissed) }
        }
    }
}

/// The column navigation controller, kept in step with the stack's path: opening adds (or replaces) columns, and a
/// column the controller lets go of (a back swipe, a pull down, a throw away, a flick in the overview) leaves the path.
private struct ColumnStack: UIViewControllerRepresentable {
    let store: StoreOf<TabStack>
    let title: LocalizedStringKey
    /// Read here so the path changing updates the controller.
    let ids: [StackElementID]

    func makeCoordinator() -> ColumnStackCoordinator {
        ColumnStackCoordinator(store: store, title: title)
    }

    func makeUIViewController(context: Context) -> ColumnNavigationController {
        let controller = ColumnNavigationController(rootViewController: context.coordinator.root)
        context.coordinator.sync(controller)
        return controller
    }

    func updateUIViewController(_ controller: ColumnNavigationController, context: Context) {
        context.coordinator.store = store
        context.coordinator.sync(controller)
    }
}

@MainActor
private final class ColumnStackCoordinator {
    /// Twitter for iPad's column: two beside the root's peek on iPhone Duo's inner display.
    static let columnWidth: CGFloat = 420
    /// A web page needs more room than a timeline.
    static let webPanelWidth: CGFloat = 600

    var store: StoreOf<TabStack>
    let root: UIViewController
    private var columns: [StackElementID: UIViewController] = [:]
    private var isAwaitingTransition = false

    init(store: StoreOf<TabStack>, title: LocalizedStringKey) {
        self.store = store
        root = ColumnHostingController(stack: store, id: nil, width: Self.columnWidth) {
            TabRootView(store: store, title: title)
        }
    }

    /// Makes the controller's stack match the path. Never in the middle of a transition: once it's done.
    func sync(_ controller: ColumnNavigationController) {
        if let transition = controller.transitionCoordinator {
            guard !isAwaitingTransition else { return }
            isAwaitingTransition = true
            transition.animate(alongsideTransition: nil) { [weak self, weak controller] _ in
                // After UIKit has let go of whatever the transition removed.
                DispatchQueue.main.async {
                    guard let self, let controller else { return }
                    self.isAwaitingTransition = false
                    self.sync(controller)
                }
            }
            return
        }
        let stack = [root] + store.path.ids.compactMap(column(for:))
        let current = controller.viewControllers
        guard stack.map(ObjectIdentifier.init) != current.map(ObjectIdentifier.init) else { return }
        let animated = controller.viewIfLoaded?.window != nil
        if stack.count < current.count, current.starts(with: stack, by: ===), let last = stack.last {
            controller.popToViewController(last, animated: animated)
        } else if stack.count == current.count + 1, stack.starts(with: current, by: ===), let last = stack.last {
            controller.pushViewController(last, animated: animated)
        } else {
            controller.setColumns(stack, animated: animated)
        }
    }

    private func column(for id: StackElementID) -> UIViewController? {
        if let column = columns[id] { return column }
        guard let state = store.path[id: id],
            let columnStore = store.scope(state: \.path[id: id], action: \.path[id: id])
        else { return nil }
        let column = ColumnHostingController(
            stack: store,
            id: id,
            width: state.isWide ? Self.webPanelWidth : Self.columnWidth
        ) {
            TabStackPathView(store: columnStore)
        }
        column.onRemoved = { [weak self] in self?.columnWasRemoved(id) }
        columns[id] = column
        return column
    }

    /// The controller let go of a column: it, and everything after it, leaves the path (unless the path already let
    /// go of it first).
    private func columnWasRemoved(_ id: StackElementID) {
        columns[id] = nil
        guard store.path.ids.contains(id) else { return }
        store.send(.path(.popFrom(id: id)))
    }
}

/// One column's screen. It offers New Tweet to iPhone Duo's vertical bar, which carries the focused column's buttons;
/// without a vertical bar, the root keeps New Tweet in its own bar.
private final class ColumnHostingController<Content: View>: UIHostingController<ColumnScreen<Content>>,
    ColumnBarItemProviding
{
    /// Called once the navigation controller has removed this column from its stack.
    var onRemoved: (() -> Void)?
    private let chrome: ColumnChrome
    private let stack: StoreOf<TabStack>

    init(stack: StoreOf<TabStack>, id: StackElementID?, width: CGFloat, @ViewBuilder content: () -> Content) {
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

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        if parent == nil { onRemoved?() }
    }

    func makeColumnBarItems() -> [UIBarButtonItem] {
        let compose = UIBarButtonItem(
            title: String(localized: "New Tweet"),
            image: UIImage(systemName: "square.and.pencil"),
            primaryAction: UIAction { [weak self] _ in self?.performColumnBarAction(Self.composeIdentifier) }
        )
        compose.identifier = Self.composeIdentifier
        return [compose]
    }

    func performColumnBarAction(_ identifier: String) {
        if identifier == Self.composeIdentifier { stack.send(.composeButtonTapped) }
    }

    func setColumnBarItemsShown(_ shown: Bool) {
        if chrome.showsBarItems != shown { chrome.showsBarItems = shown }
    }

    private static var composeIdentifier: String { "column.compose" }
}

/// Whether a column shows its bar buttons in its own bar (not while iPhone Duo's vertical bar hosts them).
@MainActor
@Observable
private final class ColumnChrome {
    var showsBarItems = true
}

/// A column: with its own bar as a column, or in the navigation controller's bar on a plain stack.
private struct ColumnScreen<Content: View>: View {
    let stack: StoreOf<TabStack>
    /// `nil` for the root.
    let id: StackElementID?
    let chrome: ColumnChrome
    let content: Content
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            // Columns draw their own bars (the navigation controller's shows only the top one, and is hidden).
            if horizontalSizeClass == .regular {
                NavigationStack {
                    screen
                        // The card is laid out clear of the window's sides (iPhone Duo's vertical bar), but is handed
                        // their insets wherever it overlaps them.
                        .ignoresSafeArea(.container, edges: .horizontal)
                }
            } else {
                screen
            }
        }
        .alreadyHereShake(trigger: stack.shake.count, isActive: stack.shake.column == id)
    }

    private var screen: some View {
        content
            .toolbar {
                if id == nil, chrome.showsBarItems {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("New Tweet", systemImage: "square.and.pencil") {
                            stack.send(.composeButtonTapped)
                        }
                    }
                }
            }
    }
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

private struct TabRootView: View {
    let store: StoreOf<TabStack>
    let title: LocalizedStringKey

    var body: some View {
        TabRootContentView(store: store.scope(state: \.root, action: \.root))
            .navigationTitle(title)
    }
}

private struct TabRootContentView: View {
    let store: StoreOf<TabRoot>

    var body: some View {
        switch store.case {
        case .feeds(let store):
            FeedsView(store: store)
                .navigationBarTitleDisplayMode(.inline)
        case .profile(let store):
            ProfileView(store: store)
        case .quotes(let store):
            FeedView(store: store)
                .navigationTitle("Quote Tweets")
                .navigationBarTitleDisplayMode(.inline)
        case .search(let store):
            SearchView(store: store)
        case .thread(let store):
            ThreadView(store: store)
                .navigationBarTitleDisplayMode(.inline)
        case .userList(let store):
            UserListView(store: store)
        case .web(let store):
            WebPanelView(store: store)
        }
    }
}

private struct TabStackPathView: View {
    let store: StoreOf<TabStackPath>

    var body: some View {
        switch store.case {
        case .profile(let store):
            ProfileView(store: store)
        case .quotes(let store):
            FeedView(store: store)
                .navigationTitle("Quote Tweets")
                .navigationBarTitleDisplayMode(.inline)
        case .search(let store):
            SearchView(store: store)
        case .thread(let store):
            ThreadView(store: store)
                .navigationTitle("Tweet")
                .navigationBarTitleDisplayMode(.inline)
        case .userList(let store):
            UserListView(store: store)
        case .web(let store):
            WebPanelView(store: store)
        }
    }
}
