import ComposableArchitecture
import ImagePipeline
import MainFeature
import Routing
import SwiftUI
import TwitterClient
import TwitterUI

/// The app's scenes: the main window, plus standalone windows for a post, profile, or search that people open beside
/// it on iPhone Duo's inner display (the system only offers new windows where there's room for them).
public struct TwitterScenes: Scene {
    public init() {}

    public var body: some Scene {
        WindowGroup {
            AppView()
                .limitsImageHeadroom()
        }

        WindowGroup("Twitter", for: WindowRoute.self) { $route in
            if let route {
                RouteWindowRoot(route: route)
                    .id(route)
                    .limitsImageHeadroom()
                    .asyncImageURLSession(.images)
            } else {
                ContentUnavailableView("Nothing to Show", twitterIcon: .newWindow)
            }
        }
        // Only "Open in New Window" makes these; the system's New Window command belongs to the main group.
        .commandsRemoved()
    }
}

private struct RouteWindowRoot: View {
    @State private var store: StoreOf<RouteWindowFeature>

    init(route: WindowRoute) {
        store = Store(initialState: RouteWindowFeature.State(route: route)) {
            RouteWindowFeature()
        } withDependencies: {
            $0.useMockTwitterIfRequested()
        }
    }

    var body: some View {
        RouteWindowView(store: store)
    }
}
