import ComposableArchitecture
import ComposeFeature
import Models
import Routing
import SwiftUI
import TabStackFeature
import TwitterClient
import TwitterUI

package struct MainView: View {
    @Bindable var store: StoreOf<MainFeature>
    /// Per-window, so each main window reopens on the tab it was showing.
    @SceneStorage("selectedTab") private var savedTab = MainFeature.Tab.home
    #if DEBUG
        @Environment(\.openWindow) private var openWindow
    #endif

    package init(store: StoreOf<MainFeature>) {
        self.store = store
    }

    package var body: some View {
        MainTabs(store: store, selection: store.selectedTab)
            // The tab bar controller keeps its tabs clear of the bars itself.
            .ignoresSafeArea()
            .sheet(item: $store.scope(state: \.compose, action: \.compose)) { composeStore in
                ComposeView(store: composeStore)
            }
            .onAppear {
                store.selectedTab = savedTab
                #if DEBUG
                    applyLaunchArguments()
                #endif
            }
            .onChange(of: store.selectedTab) { savedTab = store.selectedTab }
    }

    private func tabStack(_ tab: MainFeature.Tab) -> StoreOf<TabStack> {
        switch tab {
        case .bookmarks: store.scope(state: \.bookmarks, action: \.bookmarks)
        case .explore: store.scope(state: \.explore, action: \.explore)
        case .home: store.scope(state: \.home, action: \.home)
        case .notifications: store.scope(state: \.notifications, action: \.notifications)
        case .profile: store.scope(state: \.profile, action: \.profile)
        }
    }
}

/// The tabs, in UIKit's tab bar controller (iPhone Duo puts its bar in the vertical bar). Each tab is its stack's
/// column navigation controller with nothing in between: a SwiftUI `TabView` would keep the columns' toolbars out of
/// the navigation bar.
private struct MainTabs: UIViewControllerRepresentable {
    let store: StoreOf<MainFeature>
    /// Read here so choosing a tab elsewhere (state restoration, launch arguments) updates the controller.
    let selection: MainFeature.Tab

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }

    func makeUIViewController(context: Context) -> UITabBarController {
        let controller = UITabBarController()
        controller.delegate = context.coordinator
        controller.tabs = MainFeature.Tab.allInOrder.map { tab in
            UITab(title: tab.title, image: tab.icon(isSelected: false), identifier: tab.rawValue) {
                [coordinator = context.coordinator] _ in
                coordinator.stack(for: tab).navigationController
            }
        }
        context.coordinator.select(selection, in: controller)
        return controller
    }

    func updateUIViewController(_ controller: UITabBarController, context: Context) {
        context.coordinator.select(selection, in: controller)
    }

    @MainActor
    final class Coordinator: NSObject, UITabBarControllerDelegate {
        private let store: StoreOf<MainFeature>
        private var stacks: [MainFeature.Tab: TabStackController] = [:]

        init(store: StoreOf<MainFeature>) {
            self.store = store
        }

        func stack(for tab: MainFeature.Tab) -> TabStackController {
            if let stack = stacks[tab] { return stack }
            let stack = TabStackController(store: tabStack(tab), title: tab.titleKey)
            stacks[tab] = stack
            return stack
        }

        func select(_ selection: MainFeature.Tab, in controller: UITabBarController) {
            for tab in controller.tabs {
                guard let value = MainFeature.Tab(rawValue: tab.identifier) else { continue }
                tab.image = value.icon(isSelected: value == selection)
            }
            if controller.selectedTab?.identifier != selection.rawValue,
                let tab = controller.tab(forIdentifier: selection.rawValue)
            {
                controller.selectedTab = tab
            }
        }

        /// Choosing the tab already showing takes it back to its root, or its timeline to the top (rather than the
        /// tab bar controller popping the stack itself).
        func tabBarController(_ controller: UITabBarController, shouldSelectTab tab: UITab) -> Bool {
            guard let value = MainFeature.Tab(rawValue: tab.identifier) else { return false }
            if value == store.selectedTab {
                tabStack(value).send(.tabReselected)
                return false
            }
            return true
        }

        func tabBarController(_ controller: UITabBarController, didSelectTab tab: UITab, previousTab: UITab?) {
            guard let value = MainFeature.Tab(rawValue: tab.identifier), value != store.selectedTab else { return }
            store.selectedTab = value
        }

        private func tabStack(_ tab: MainFeature.Tab) -> StoreOf<TabStack> {
            switch tab {
            case .bookmarks: store.scope(state: \.bookmarks, action: \.bookmarks)
            case .explore: store.scope(state: \.explore, action: \.explore)
            case .home: store.scope(state: \.home, action: \.home)
            case .notifications: store.scope(state: \.notifications, action: \.notifications)
            case .profile: store.scope(state: \.profile, action: \.profile)
            }
        }
    }
}

extension MainFeature.Tab {
    fileprivate static let allInOrder: [Self] = [.home, .notifications, .bookmarks, .profile, .explore]

    fileprivate var title: String {
        switch self {
        case .bookmarks: String(localized: "Bookmarks")
        case .explore: String(localized: "Explore")
        case .home: String(localized: "Home")
        case .notifications: String(localized: "Notifications")
        case .profile: String(localized: "Profile")
        }
    }

    fileprivate var titleKey: LocalizedStringKey { LocalizedStringKey(title) }

    /// Twitter's glyph: outlined, and filled while selected.
    fileprivate func icon(isSelected: Bool) -> UIImage? {
        let icon: TwitterIcon =
            switch self {
            case .bookmarks: isSelected ? .bookmark : .bookmarkStroke
            case .explore: isSelected ? .search : .searchStroke
            case .home: isSelected ? .home : .homeStroke
            case .notifications: isSelected ? .notifications : .notificationsStroke
            case .profile: isSelected ? .person : .personStroke
            }
        return icon.uiImage
    }
}

#if DEBUG
    extension MainView {
        /// `--tab <home|notifications|bookmarks|profile|explore>`, `--open-thread`, `--open-web`, `--open-profile` and `--open-window-thread` put the app on a given screen at
        /// launch, for capturing it without tapping there.
        fileprivate func applyLaunchArguments() {
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "--tab"), index + 1 < arguments.count,
                let tab = MainFeature.Tab(rawValue: arguments[index + 1])
            {
                store.selectedTab = tab
            }
            if arguments.contains("--open-thread"), let tweet = Tweet.mocks.first {
                store.send(.home(.root(.feeds(.delegate(.open(.thread(tweet)))))))
            }
            // `--search <query>`: that search's results, opened from the home timeline.
            if let index = arguments.firstIndex(of: "--search"), index + 1 < arguments.count {
                store.send(.home(.root(.feeds(.delegate(.open(.search(arguments[index + 1])))))))
            }
            // `--compose`: the New Tweet sheet.
            if arguments.contains("--compose") {
                store.send(.home(.composeButtonTapped))
            }
            // `--open-reply`: a reply's thread, with the conversation it replies to above it.
            if arguments.contains("--open-reply") {
                store.send(.home(.root(.feeds(.delegate(.open(.thread(.mockReply)))))))
            }
            if arguments.contains("--open-web"), let url = URL(string: "https://www.pointfree.co") {
                // Once the stack knows whether it has room for a web panel, rather than Safari's view.
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1))
                    store.send(.home(.root(.feeds(.delegate(.open(.web(url)))))))
                }
            }
            // `--cycle-columns`: opens a thread column, closes it and opens it again, a few seconds apart, to watch
            // the strip go from one column to two without touching anything.
            if arguments.contains("--cycle-columns"), let tweet = Tweet.mocks.first {
                Task { @MainActor in
                    for _ in 0..<2 {
                        try? await Task.sleep(for: .seconds(2))
                        store.send(.home(.root(.feeds(.delegate(.open(.thread(tweet)))))))
                        try? await Task.sleep(for: .seconds(2))
                        // `--pop`: close as a pulled-down or thrown-away column does, straight out of the path.
                        if arguments.contains("--pop"), let id = store.home.path.ids.first {
                            store.send(.home(.path(.popFrom(id: id))))
                        } else {
                            store.send(.home(.tabReselected))
                        }
                    }
                }
            }
            if arguments.contains("--open-window-thread"), let tweet = Tweet.mocks.first {
                openWindow(value: Route.thread(tweet).window)
            }
            // `--open-profile` (after `--open-thread`) opens a third column from the thread.
            if arguments.contains("--open-profile"), let id = store.home.path.ids.last {
                store.send(.home(.path(.element(id: id, action: .thread(.delegate(.open(.profile(.mock))))))))
            }
            // `--open-followers`, `--open-following`, `--open-reposts`, `--open-likes` and `--open-quotes` open the mock
            // profile's or first mock post's list as a column from the home timeline, or after `--open-thread`'s
            // thread.
            let lists: [(argument: String, route: Route)] = [
                ("--open-followers", .userList(.followers(userID: User.mock.id))),
                ("--open-following", .userList(.following(userID: User.mock.id))),
                ("--open-likes", .userList(.likers(tweetID: Tweet.mocks[0].id))),
                ("--open-lists", .lists(userID: User.mock.id)),
                ("--open-quotes", .quotes(tweetID: Tweet.mocks[0].id)),
                ("--open-reposts", .userList(.reposters(tweetID: Tweet.mocks[0].id)))
            ]
            for list in lists where arguments.contains(list.argument) {
                if let id = store.home.path.ids.last, case .thread? = store.home.path[id: id] {
                    store.send(.home(.path(.element(id: id, action: .thread(.delegate(.open(list.route)))))))
                } else {
                    store.send(.home(.root(.feeds(.delegate(.open(list.route))))))
                }
            }
        }
    }
#endif
