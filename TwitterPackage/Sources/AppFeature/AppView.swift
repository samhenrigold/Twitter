import ComposableArchitecture
import ImagePipeline
import MainFeature
import Models
import SignInFeature
import SwiftUI
import TwitterClient
import TwitterClientLive
import TwitterUI

public struct AppView: View {
    @State private var store = Store(initialState: AppFeature.State()) {
        AppFeature()
    } withDependencies: {
        $0.useMockTwitterIfRequested()
    }

    public init() {}

    public var body: some View {
        AppRootView(store: store)
            .asyncImageURLSession(.images)
    }
}

private struct AppRootView: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        Group {
            switch store.state {
            case .launchFailed(let message):
                ContentUnavailableView {
                    Label("Couldn't reach Twitter", twitterIcon: .cloudOff)
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { store.send(.retryButtonTapped) }
                        .buttonStyle(.borderedProminent)
                }
            case .launching:
                LaunchingView()
            case .main:
                if let store = store.scope(state: \.main, action: \.main) {
                    MainView(store: store)
                }
            case .signIn:
                if let store = store.scope(state: \.signIn, action: \.signIn) {
                    SignInView(store: store)
                }
            }
        }
        .task { store.send(.task) }
    }
}

/// Matches the blank launch screen, and only shows a spinner if restoring the session is actually slow, so a quick
/// restore doesn't flash one.
private struct LaunchingView: View {
    @State private var showsSpinner = false

    var body: some View {
        ZStack {
            Color.clear

            if showsSpinner {
                ProgressView()
                    .transition(.opacity)
            }
        }
        .task {
            guard (try? await Task.sleep(for: .milliseconds(500))) != nil else { return }
            withAnimation { showsSpinner = true }
        }
    }
}

#Preview {
    AppView()
}
