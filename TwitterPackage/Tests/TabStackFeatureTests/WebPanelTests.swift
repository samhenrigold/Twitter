import ComposableArchitecture
import Foundation
import Testing

@testable import Models
@testable import Routing
@testable import TabStackFeature
@testable import WebFeature

@MainActor
struct WebPanelTests {
    let url = URL(string: "https://www.pointfree.co/episodes")!

    @Test
    func webLinkOpensAPanelBesideTheColumns() async {
        var state = TabStack.State.home
        state.canShowColumns = true
        let store = TestStore(initialState: state) {
            TabStack()
        }

        await store.send(.root(.feeds(.delegate(.open(.web(url)))))) {
            $0.path = StackState([.web(WebFeature.State(url: self.url))])
        }
    }

    @Test
    func webLinkOnOneStackOpensSafari() async {
        let store = TestStore(initialState: TabStack.State.home) {
            TabStack()
        }

        await store.send(.root(.feeds(.delegate(.open(.web(url)))))) {
            $0.safari = TabStack.SafariPage(url: self.url)
        }
        await store.send(.safariDismissed) {
            $0.safari = nil
        }
    }

    @Test
    func columnAvailabilityFollowsTheDisplay() async {
        let store = TestStore(initialState: TabStack.State.home) {
            TabStack()
        }

        await store.send(.columnAvailabilityChanged(true)) {
            $0.canShowColumns = true
        }
    }

    @Test
    func openingTheSamePageAgainFocusesItsPanel() async {
        var state = TabStack.State.home
        state.canShowColumns = true
        state.path.append(.web(WebFeature.State(url: url)))
        state.path.append(Route.thread(Tweet.mocks[0]).pathState)
        let store = TestStore(initialState: state) {
            TabStack()
        }
        let sameURL = URL(string: "https://WWW.pointfree.co/episodes/#top")!

        await store.send(.root(.feeds(.delegate(.open(.web(sameURL)))))) {
            $0.path.removeLast()
        }
    }

    @Test
    func postLinkInsideAPanelOpensAColumnAfterIt() async {
        var state = TabStack.State.home
        state.canShowColumns = true
        state.path.append(.web(WebFeature.State(url: url)))
        let store = TestStore(initialState: state) {
            TabStack()
        }

        await store.send(.path(.element(id: 0, action: .web(.inAppLinkTapped(.threadID("12345"))))))
        await store.receive(\.path[id: 0].web.delegate) {
            $0.path[id: 1] = Route.threadID("12345").pathState
        }
    }

    @Test
    func panelRemembersWhereTheReaderGot() async {
        let store = TestStore(initialState: WebFeature.State(url: url)) {
            WebFeature()
        }
        let next = URL(string: "https://www.pointfree.co/collections")!

        await store.send(.pageChanged(url: next, title: "Collections")) {
            $0.currentURL = next
            $0.title = "Collections"
        }
        #expect(store.state.shows(next))
        #expect(store.state.shows(url))
        #expect(store.state.pageURL == next)
    }

    @Test
    func openInSafariOpensTheCurrentPage() async {
        let opened = LockIsolated<[URL]>([])
        var state = WebFeature.State(url: url)
        let next = URL(string: "https://www.pointfree.co/collections")!
        state.currentURL = next
        let store = TestStore(initialState: state) {
            WebFeature()
        } withDependencies: {
            $0.openURL = OpenURLEffect { url in
                opened.withValue { $0.append(url) }
                return true
            }
        }

        await store.send(.openInSafariButtonTapped)
        await store.finish()
        #expect(opened.value == [next])
    }

    @Test
    func windowRootedAtAPage() {
        let state = TabStack.State.window(.web(url))
        #expect(state.root.web?.url == url)
    }
}
