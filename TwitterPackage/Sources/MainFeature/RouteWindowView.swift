import ComposableArchitecture
import ComposeFeature
import Routing
import SwiftUI
import TabStackFeature
import TwitterUI

package struct RouteWindowView: View {
    @Bindable var store: StoreOf<RouteWindowFeature>
    @Environment(\.dismissWindow) private var dismissWindow

    package init(store: StoreOf<RouteWindowFeature>) {
        self.store = store
    }

    package var body: some View {
        Group {
            switch store.status {
            case .signedOutElsewhere:
                Color.clear
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't reach Twitter", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { store.send(.task) }
                        .buttonStyle(.borderedProminent)
                }
            case .ready:
                TabStackView(store: store.scope(state: \.stack, action: \.stack), title: store.route.windowTitle)
            case .restoring:
                ProgressView()
            case .signedOut:
                ContentUnavailableView(
                    "Signed Out",
                    systemImage: "person.crop.circle.badge.xmark",
                    description: Text("Sign in from the main Twitter window to see this.")
                )
            }
        }
        .task { store.send(.task) }
        .onChange(of: store.status) {
            if store.status == .signedOutElsewhere { dismissWindow() }
        }
        .sheet(item: $store.scope(state: \.compose, action: \.compose)) { composeStore in
            ComposeView(store: composeStore)
        }
    }
}

extension WindowRoute {
    fileprivate var windowTitle: LocalizedStringKey {
        switch self {
        case .profile(let screenName): "@\(screenName)"
        case .quotes: "Quote Tweets"
        case .search(let query): "Search: \(query)"
        case .thread: "Tweet"
        case .userList(let source): "\(source.title)"
        case .web(let url): "\(url.host() ?? url.absoluteString)"
        }
    }
}
