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
        TabView(selection: reselectableTab) {
            Tab(value: .home) {
                TabStackView(store: tabStack(.home), title: "Home")
            } label: {
                TabLabel("Home", icon: .homeStroke, selectedIcon: .home, isSelected: store.selectedTab == .home)
            }

            Tab(value: .notifications) {
                TabStackView(store: tabStack(.notifications), title: "Notifications")
            } label: {
                TabLabel(
                    "Notifications", icon: .notificationsStroke, selectedIcon: .notifications,
                    isSelected: store.selectedTab == .notifications)
            }

            Tab(value: .bookmarks) {
                TabStackView(store: tabStack(.bookmarks), title: "Bookmarks")
            } label: {
                TabLabel(
                    "Bookmarks", icon: .bookmarkStroke, selectedIcon: .bookmark,
                    isSelected: store.selectedTab == .bookmarks)
            }

            Tab(value: .profile) {
                TabStackView(store: tabStack(.profile), title: "Profile")
            } label: {
                TabLabel(
                    "Profile", icon: .personStroke, selectedIcon: .person, isSelected: store.selectedTab == .profile)
            }

            Tab(value: .explore) {
                TabStackView(store: tabStack(.explore), title: "Explore")
            } label: {
                TabLabel(
                    "Explore", icon: .searchStroke, selectedIcon: .search, isSelected: store.selectedTab == .explore)
            }
        }
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

    /// The selected tab; choosing the one already showing takes it back to its root, or its timeline to the top.
    private var reselectableTab: Binding<MainFeature.Tab> {
        Binding {
            store.selectedTab
        } set: { tab in
            if tab == store.selectedTab {
                tabStack(tab).send(.tabReselected)
            } else {
                store.selectedTab = tab
            }
        }
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

/// A tab in Twitter's own glyphs: outlined, and filled while selected.
private struct TabLabel: View {
    let icon: TwitterIcon
    let isSelected: Bool
    let selectedIcon: TwitterIcon
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey, icon: TwitterIcon, selectedIcon: TwitterIcon, isSelected: Bool) {
        self.icon = icon
        self.isSelected = isSelected
        self.selectedIcon = selectedIcon
        self.title = title
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            (isSelected ? selectedIcon : icon).image
        }
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
