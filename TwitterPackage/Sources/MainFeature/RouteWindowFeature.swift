import ComposableArchitecture
import ComposeFeature
import Models
import Routing
import TabStackFeature
import TwitterClient

/// A secondary window showing one post, profile, or search, alongside the main window on iPhone Duo's inner display.
@Reducer
package struct RouteWindowFeature {
    @ObservableState
    package struct State: Equatable {
        @Presents var compose: ComposeFeature.State?
        let route: WindowRoute
        var stack: TabStack.State
        var status = Status.restoring
        @Shared(.viewer) var viewer

        package init(route: WindowRoute) {
            self.route = route
            stack = .window(route)
            // A remembered account shows right away; `task` checks it's still signed in.
            if viewer != nil { status = .ready }
        }

        package enum Status: Equatable {
            /// The account this window was showing signed out in another window; the window closes itself.
            case signedOutElsewhere
            case failed(String)
            case ready
            case restoring
            case signedOut
        }
    }

    package enum Action {
        case compose(PresentationAction<ComposeFeature.Action>)
        case restoreSessionResponse(Result<User?, any Error>)
        case stack(TabStack.Action)
        case task
        case viewerChanged(User?)
    }

    enum CancelID {
        case viewer
    }

    @Dependency(TwitterClient.self) var client

    package init() {}

    package var body: some Reducer<State, Action> {
        Scope(state: \.stack, action: \.stack) { TabStack() }
        Reduce { state, action in
            switch action {
            case .compose:
                return .none

            case .restoreSessionResponse(.success(let viewer)):
                guard let viewer else {
                    state.status = .signedOut
                    return .cancel(id: CancelID.viewer)
                }
                let wasReady = state.status == .ready
                state.status = .ready
                if state.viewer != viewer { state.$viewer.withLock { $0 = viewer } }
                // Already watching since `task` if the account was remembered.
                guard !wasReady else { return .none }
                // Watch only once this window has its own account, so it can't mistake "not restored yet" for a
                // sign-out elsewhere.
                return .publisher {
                    state.$viewer.publisher.map(Action.viewerChanged)
                }
                .cancellable(id: CancelID.viewer, cancelInFlight: true)

            case .restoreSessionResponse(.failure(let error)):
                // Offline with a remembered account: keep showing what's cached.
                guard state.status != .ready else { return .none }
                state.status = .failed(error.localizedDescription)
                return .none

            case .stack(.delegate(.compose(let draft))):
                state.compose = ComposeFeature.State(draft: draft)
                return .none

            case .stack(.delegate(.drafts)):
                state.compose = .drafts()
                return .none

            case .stack(.delegate(.signOut)):
                reportIssue("Secondary windows never show the viewer's own profile, so they can't sign out.")
                return .none

            case .stack:
                return .none

            case .task:
                let restore = Effect<Action>.run { send in
                    await send(.restoreSessionResponse(Result { try await client.restoreSession() }))
                }
                guard state.status == .ready else {
                    state.status = .restoring
                    return restore
                }
                // Showing the remembered account already: watch it, and check it's still signed in alongside.
                return .merge(
                    .publisher { state.$viewer.publisher.map(Action.viewerChanged) }
                        .cancellable(id: CancelID.viewer, cancelInFlight: true),
                    restore
                )

            case .viewerChanged(let viewer):
                guard state.status == .ready, viewer == nil else { return .none }
                state.status = .signedOutElsewhere
                return .cancel(id: CancelID.viewer)
            }
        }
        .ifLet(\.$compose, action: \.compose) {
            ComposeFeature()
        }
    }
}
