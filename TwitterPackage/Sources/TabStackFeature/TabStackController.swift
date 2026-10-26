import ColumnNavigation
import ComposableArchitecture
import SafariServices
import SwiftUI

/// A tab's navigation: one `ColumnNavigationController` whose stack is the root and the path, in every size class.
/// Horizontally regular, it's Tweetie's stacked columns (each opened thing is a column after the one it came from, the
/// strip slides and snaps, columns pull down or off to close, a pull on the root throws them away or opens the
/// overview); compact, it's a plain navigation stack, with web pages in Safari's view instead of a column.
///
/// The navigation controller is kept in step with the path: opening adds (or replaces) columns, and a column the
/// controller lets go of (a back swipe, a pull down, a throw away, a flick in the overview) leaves the path.
///
/// Columns are hosted straight in UIKit, with no SwiftUI container around the navigation controller: a SwiftUI
/// `TabView` (or any host managing toolbars) above it stops the columns' toolbars and titles reaching its bar.
@MainActor
package final class TabStackController: NSObject {
    /// Twitter for iPad's column: two beside the root's peek on iPhone Duo's inner display.
    static let columnWidth: CGFloat = 420
    /// A web page needs more room than a timeline.
    static let webPanelWidth: CGFloat = 600

    package let navigationController: ColumnNavigationController
    private let store: StoreOf<TabStack>
    private var columns: [StackElementID: UIViewController] = [:]
    private var isAwaitingTransition = false
    private var observation: ObserveToken?

    package init(store: StoreOf<TabStack>, title: LocalizedStringKey) {
        self.store = store
        let root = ColumnHostingController(stack: store, id: nil, width: Self.columnWidth) {
            TabRootView(store: store, title: title)
        }
        // Columns put their own (SwiftUI) buttons in iPhone Duo's vertical bar when focused.
        ColumnSettings.shared.columnsPlaceVerticalBarItems = true
        navigationController = ColumnNavigationController(rootViewController: root)
        super.init()
        navigationController.registerForTraitChanges([UITraitHorizontalSizeClass.self]) {
            [weak self] (controller: ColumnNavigationController, _) in
            self?.columnAvailabilityChanged()
        }
        // Launched already wide (iPhone Duo open), the size class never changes: the root's first layout says so.
        root.onLayout = { [weak self] in self?.columnAvailabilityChanged() }
        observation = observe { [weak self] in
            guard let self else { return }
            _ = store.path.ids
            sync()
            presentSafariIfNeeded()
        }
    }

    /// Whether the window is wide enough for columns (otherwise a web page opens in Safari's view).
    private func columnAvailabilityChanged() {
        let canShowColumns = navigationController.traitCollection.horizontalSizeClass == .regular
        if store.canShowColumns != canShowColumns { store.send(.columnAvailabilityChanged(canShowColumns)) }
    }

    /// Makes the controller's stack match the path. Never in the middle of a transition: once it's done.
    private func sync() {
        let controller = navigationController
        if let transition = controller.transitionCoordinator {
            guard !isAwaitingTransition else { return }
            isAwaitingTransition = true
            transition.animate(alongsideTransition: nil) { [weak self] _ in
                // After UIKit has let go of whatever the transition removed.
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    isAwaitingTransition = false
                    sync()
                }
            }
            return
        }
        guard let root = controller.viewControllers.first else { return }
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

    private func presentSafariIfNeeded() {
        guard let page = store.safari, navigationController.presentedViewController == nil else { return }
        let safari = SFSafariViewController(url: page.url)
        safari.delegate = self
        navigationController.present(safari, animated: true)
    }
}

extension TabStackController: SFSafariViewControllerDelegate {
    package nonisolated func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        MainActor.assumeIsolated { _ = store.send(.safariDismissed) }
    }
}
