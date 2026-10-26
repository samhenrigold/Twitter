import ComposableArchitecture
import ComposeFeature
import Models
import Routing
import TabStackFeature
import TwitterClient

@Reducer
package struct MainFeature {
    @ObservableState
    package struct State: Equatable {
        var bookmarks = TabStack.State.bookmarks
        @Presents var compose: ComposeFeature.State?
        var explore = TabStack.State.explore
        var home = TabStack.State.home
        var notifications = TabStack.State.notifications
        var profile: TabStack.State
        var selectedTab = Tab.home
        /// Unread notifications, badging the Notifications tab until it's opened.
        var unreadNotifications = 0
        package var viewer: User

        package init(viewer: User) {
            self.viewer = viewer
            profile = .profile(viewer: viewer)
        }
    }

    package enum Tab: String, Hashable {
        case bookmarks
        case explore
        case home
        case notifications
        case profile
    }

    package enum Action: BindableAction {
        case binding(BindingAction<State>)
        case bookmarks(TabStack.Action)
        case compose(PresentationAction<ComposeFeature.Action>)
        case delegate(Delegate)
        case explore(TabStack.Action)
        case home(TabStack.Action)
        case notifications(TabStack.Action)
        case profile(TabStack.Action)
        case task
        case unreadNotificationsResponse(Int)

        package enum Delegate {
            case signedOut
        }
    }

    @Dependency(TwitterClient.self) var client
    @Dependency(\.continuousClock) var clock

    /// How often the Notifications badge checks for more.
    static let unreadPollInterval: Duration = .seconds(180)

    enum CancelID {
        case unreadPolling
    }

    package init() {}

    package var body: some Reducer<State, Action> {
        BindingReducer()
        Scope(state: \.bookmarks, action: \.bookmarks) { TabStack() }
        Scope(state: \.explore, action: \.explore) { TabStack() }
        Scope(state: \.home, action: \.home) { TabStack() }
        Scope(state: \.notifications, action: \.notifications) { TabStack() }
        Scope(state: \.profile, action: \.profile) { TabStack() }
        Reduce { state, action in
            switch action {
            case .bookmarks(.delegate(let delegate)),
                .explore(.delegate(let delegate)),
                .home(.delegate(let delegate)),
                .notifications(.delegate(let delegate)),
                .profile(.delegate(let delegate)):
                switch delegate {
                case .compose(let draft):
                    state.compose = ComposeFeature.State(draft: draft)
                    return .none
                case .open:
                    return .none
                case .signOut:
                    return .run { send in
                        await client.signOut()
                        await send(.delegate(.signedOut))
                    }
                }

            case .binding(\.selectedTab):
                if state.selectedTab == .notifications { state.unreadNotifications = 0 }
                return .none

            case .task:
                return .run { send in
                    while true {
                        if let count = try? await client.unreadNotificationCount() {
                            await send(.unreadNotificationsResponse(count))
                        }
                        try await clock.sleep(for: Self.unreadPollInterval)
                    }
                }
                .cancellable(id: CancelID.unreadPolling, cancelInFlight: true)

            case .unreadNotificationsResponse(let count):
                // Already reading them: nothing to badge.
                state.unreadNotifications = state.selectedTab == .notifications ? 0 : count
                return .none

            case .binding, .bookmarks, .compose, .delegate, .explore, .home, .notifications, .profile:
                return .none
            }
        }
        .ifLet(\.$compose, action: \.compose) {
            ComposeFeature()
        }
    }
}
