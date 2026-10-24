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
    @State private var sidebarGeometry = SidebarGeometry()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.toolbarVerticalEdge) private var toolbarVerticalEdge
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #if DEBUG
        @Environment(\.openWindow) private var openWindow
    #endif

    package init(store: StoreOf<MainFeature>) {
        self.store = store
    }

    package var body: some View {
        let placement = SidebarPlacement(
            geometry: sidebarGeometry,
            verticalBarEdge: toolbarVerticalEdge,
            isRegular: horizontalSizeClass == .regular && verticalSizeClass == .regular,
        )
        // Measured outside the layers, which reach into the side bar they measure.
        ZStack(alignment: placement.edge == .trailing ? .leading : .trailing) {
            // Behind both: the backdrop the sidebar slides back over as it widens.
            ColumnBackdrop()

            // The tabs underneath, their bar hidden for Twitter for iPad's sidebar.
            TabView(selection: $store.selectedTab) {
                Tab(value: .home) {
                    TabStackView(store: tabStack(.home), title: "Home")
                        .toolbarVisibility(.hidden, for: .tabBar)
                } label: {
                    TabLabel("Home", icon: .home, isSelected: store.selectedTab == .home)
                }

                Tab(value: .notifications) {
                    TabStackView(store: tabStack(.notifications), title: "Notifications")
                        .toolbarVisibility(.hidden, for: .tabBar)
                } label: {
                    TabLabel("Notifications", icon: .at, isSelected: store.selectedTab == .notifications)
                }

                Tab(value: .bookmarks) {
                    TabStackView(store: tabStack(.bookmarks), title: "Bookmarks")
                        .toolbarVisibility(.hidden, for: .tabBar)
                } label: {
                    TabLabel("Bookmarks", icon: .bookmark, isSelected: store.selectedTab == .bookmarks)
                }

                Tab(value: .profile) {
                    TabStackView(store: tabStack(.profile), title: "Profile")
                        .toolbarVisibility(.hidden, for: .tabBar)
                } label: {
                    TabLabel("Profile", icon: .profile, isSelected: store.selectedTab == .profile)
                }

                Tab(value: .explore) {
                    TabStackView(store: tabStack(.explore), title: "Explore")
                        .toolbarVisibility(.hidden, for: .tabBar)
                } label: {
                    TabLabel("Explore", icon: .hash, isSelected: store.selectedTab == .explore)
                }
            }
            .tabViewStyle(.tabBarOnly)
            .environment(\.hasClassicSidebar, true)
            // Laid out for the width they'll have once the sidebar has settled (see `columnStripWidth`), so the columns
            // are placed once rather than chasing the sidebar frame by frame.
            // Before the window is measured (or while a measurement is out of range) there's no width to give.
            .frame(width: placement.validStripWidth)
            .environment(\.columnStripWidth, placement.validStripWidth)
            // Down past the home indicator, as a tab view is: the tabs keep their own content clear of it. The
            // sidebar keeps clear of it and of the camera itself.
            .ignoresSafeArea(.container, edges: .bottom)

            placedSidebar(placement)
                .frame(maxWidth: .infinity, alignment: placement.edge == .trailing ? .trailing : .leading)
                // In step with the columns sliding as one opens or closes.
                .animation(TabStackView.columnSlide, value: placement)
        }
        // Sideways into the system's side bar, which the sidebar fills.
        .ignoresSafeArea(
            .container,
            edges: placement.isInSystemSideBar ? (placement.edge == .leading ? .leading : .trailing) : []
        )
        .onGeometryChange(for: SidebarGeometry.self) { proxy in
            SidebarGeometry(proxy: proxy)
        } action: { geometry in
            sidebarGeometry = geometry
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

    /// Where iPhone Duo keeps a side bar, in its place at its width, tucked under the camera and status bar; elsewhere,
    /// room of its own.
    private func placedSidebar(_ placement: SidebarPlacement) -> some View {
        sidebar(placement)
            // Its own room is the side bar's safe area; it lays out across all of it.
            .ignoresSafeArea(.container, edges: placement.isInSystemSideBar ? .horizontal : [])
            .frame(width: placement.width.isFinite ? max(placement.width, 0) : nil)
            // Nothing of the wider sidebar spills sideways over the tabs as it collapses; up and down it still reaches
            // under the status bar and home indicator.
            .mask { Rectangle().ignoresSafeArea(edges: .vertical) }
            .zIndex(1)
    }

    private func sidebar(_ placement: SidebarPlacement) -> some View {
        ClassicSidebar(
            tabs: Self.tabs,
            selection: $store.selectedTab,
            edge: placement.edge,
            isExpanded: placement.isExpanded,
            topInset: placement.statusBarHeight,
            centerOffset: placement.isInSystemSideBar && !placement.isExpanded ? -5 : 0,
            compose: { tabStack(store.selectedTab).send(.composeButtonTapped) },
            reselect: { tabStack($0).send(.tabReselected) },
            actions: { SidebarBackButton(store: tabStack(store.selectedTab)) }
        )
    }

    private static var tabs: [ClassicSidebarTab<MainFeature.Tab>] {
        [
            ClassicSidebarTab("Home", icon: .home, id: MainFeature.Tab.home),
            ClassicSidebarTab("Notifications", icon: .at, id: .notifications),
            ClassicSidebarTab("Bookmarks", icon: .bookmark, id: .bookmarks),
            ClassicSidebarTab("Profile", icon: .profile, id: .profile),
            ClassicSidebarTab("Explore", icon: .hash, id: .explore)
        ]
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

/// What the sidebar's placement depends on: the window's width, and the side bar iPhone Duo keeps beside the content
/// in some poses (the trailing safe area).
private struct SidebarGeometry: Equatable {
    var height: CGFloat = 0
    var leadingInset: CGFloat = 0
    var trailingInset: CGFloat = 0
    var width: CGFloat = 0

    init() {}

    init(proxy: GeometryProxy) {
        height = proxy.size.height
        leadingInset = proxy.safeAreaInsets.leading
        trailingInset = proxy.safeAreaInsets.trailing
        width = proxy.size.width
    }
}

/// Where the sidebar goes and how wide it is.
private struct SidebarPlacement: Equatable {
    /// The narrowest column worth reading beside the expanded sidebar.
    static let expandingWidth: CGFloat = 400
    /// The narrowest column of two side by side (`ColumnLayout.minimumColumnWidth`).
    static let twoColumnWidth: CGFloat = 400
    static let collapsedWidth: CGFloat = 72
    static let expandedWidth: CGFloat = 220
    /// The status bar at the top of iPhone Duo's side bar: the sidebar's first button goes just under it.
    static let systemStatusBarHeight: CGFloat = 104

    var edge = HorizontalEdge.trailing
    var isExpanded = false
    var isInSystemSideBar = false
    var statusBarHeight: CGFloat = 0
    /// The width left for the tabs beside the sidebar.
    var stripWidth: CGFloat = 0

    /// `stripWidth` where it's a usable frame width; `nil` before the window has a real size.
    var validStripWidth: CGFloat? {
        stripWidth.isFinite && stripWidth > 0 ? stripWidth : nil
    }
    var width: CGFloat = 0

    /// - Parameter verticalBarEdge: Where iPhone Duo would put a vertical toolbar (`toolbarVerticalEdge`), if
    ///   anywhere: the side bar beside the content, under the camera and status bar.
    /// - Parameter isRegular: Whether the window is regular both ways: room for a column and a sidebar that names its
    ///   tabs. A compact window keeps the strip.
    init(geometry: SidebarGeometry, verticalBarEdge: HorizontalEdge?, isRegular: Bool) {
        let windowWidth = geometry.width + geometry.leadingInset + geometry.trailingInset
        // Expanded beside a lone column, where the window is regular and wide enough for both.
        // Expanded where the window can't show two columns side by side anyway (the inner display upright), so it
        // never changes as columns open and close: nothing beside it resizes, and the columns only ever slide.
        let canExpand =
            isRegular && windowWidth >= Self.expandingWidth + Self.expandedWidth
            && windowWidth - Self.collapsedWidth < 2 * Self.twoColumnWidth
        if let verticalBarEdge {
            // In the system's side bar, under its status bar, as its own vertical bar would be: at its width, or
            // reaching past it when expanded.
            edge = verticalBarEdge
            isInSystemSideBar = true
            statusBarHeight = Self.systemStatusBarHeight
            let inset = verticalBarEdge == .leading ? geometry.leadingInset : geometry.trailingInset
            let sideBarWidth = inset > 0 ? inset : Self.collapsedWidth
            isExpanded = canExpand
            width = isExpanded ? max(Self.expandedWidth, sideBarWidth) : sideBarWidth
            stripWidth = max(geometry.width + inset - width, 0)
        } else {
            isExpanded = canExpand
            width = isExpanded ? Self.expandedWidth : Self.collapsedWidth
            stripWidth = max(geometry.width - width, 0)
        }
    }
}

/// A tab in Twitter 4.x's own icons, which draw their selected state themselves (blue, with a glow).
private struct TabLabel: View {
    let icon: ClassicTabIcon
    let isSelected: Bool
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey, icon: ClassicTabIcon, isSelected: Bool) {
        self.icon = icon
        self.isSelected = isSelected
        self.title = title
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            icon.image(isSelected: isSelected)
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
