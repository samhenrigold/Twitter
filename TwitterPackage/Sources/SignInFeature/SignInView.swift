import ComposableArchitecture
import Models
import SwiftUI
import TwitterClient
import TwitterUI
import WebKit

package struct SignInView: View {
    let store: StoreOf<SignInFeature>

    package init(store: StoreOf<SignInFeature>) {
        self.store = store
    }

    package var body: some View {
        NavigationStack {
            SignInWebView(
                pageLoadingChanged: { store.send(.pageLoadingChanged($0)) },
                sessionCaptured: { store.send(.sessionCaptured($0)) }
            )
            .id(store.attempt)
            .ignoresSafeArea(edges: .bottom)
            .overlay {
                if let errorMessage = store.errorMessage {
                    ContentUnavailableView {
                        Label("Couldn't sign in", twitterIcon: .warningStroke)
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Try Again") { store.send(.retryButtonTapped) }
                            .buttonStyle(.borderedProminent)
                    }
                    .background(.background)
                } else if store.isSigningIn {
                    ProgressView("Signing in…")
                        .padding()
                        .glassEffect(.regular, in: .rect(cornerRadius: 20))
                }
            }
            .navigationTitle("Sign in to Twitter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if store.isPageLoading {
                    ToolbarItem(placement: .topBarTrailing) {
                        ProgressView()
                    }
                }
            }
        }
    }
}

private struct SignInWebView: UIViewRepresentable {
    let pageLoadingChanged: (Bool) -> Void
    let sessionCaptured: ([String: String]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(pageLoadingChanged: pageLoadingChanged, sessionCaptured: sessionCaptured)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        configuration.websiteDataStore.httpCookieStore.add(context.coordinator)
        webView.load(URLRequest(url: URL(string: "https://x.com/i/flow/login")!))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.websiteDataStore.httpCookieStore.remove(coordinator)
        webView.stopLoading()
    }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver {
        private var didCapture = false
        private let pageLoadingChanged: (Bool) -> Void
        private let sessionCaptured: ([String: String]) -> Void

        package init(
            pageLoadingChanged: @escaping (Bool) -> Void, sessionCaptured: @escaping ([String: String]) -> Void
        ) {
            self.pageLoadingChanged = pageLoadingChanged
            self.sessionCaptured = sessionCaptured
        }

        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            // Checks `didCapture` again after the await: another change can capture while this one reads the jar.
            Task.immediate {
                guard !didCapture else { return }
                var jar: [String: String] = [:]
                for cookie in await cookieStore.allCookies() where cookie.domain.hasSuffix("x.com") {
                    jar[cookie.name] = cookie.value
                }
                guard jar["auth_token"] != nil, jar["ct0"] != nil, jar["twid"] != nil, !didCapture else { return }
                didCapture = true
                sessionCaptured(jar)
            }
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            webView.load(navigationAction.request)
            return nil
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            pageLoadingChanged(true)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pageLoadingChanged(false)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            pageLoadingChanged(false)
        }

        func webView(
            _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error
        ) {
            // The page never started (offline, say): the spinner stops.
            pageLoadingChanged(false)
        }
    }
}
