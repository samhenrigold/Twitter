import ComposableArchitecture
import Foundation
import Testing

@testable import FeedFeature
@testable import ListsFeature
@testable import Models
@testable import Routing
@testable import TabStackFeature
@testable import TwitterClient
@testable import WebFeature

@MainActor
struct TabStackFeatureTests {
    @Test
    func reselectingTheTabAtItsRootScrollsTheTimelineToTheTopAndRefreshes() async {
        let store = TestStore(initialState: TabStack.State.home) {
            TabStack()
        } withDependencies: {
            $0[TwitterClient.self] = .previewValue
        }
        store.exhaustivity = .off

        await store.send(.tabReselected)
        await store.receive(\.root.feeds.reselected)
        await store.receive(\.root.feeds.feeds) {
            guard case .feeds(let feeds) = $0.root else { return }
            #expect(feeds.feeds.first?.scrollToTopRequests == 1)
        }
    }

    @Test
    func reselectingTheTabReturnsToTheRoot() async {
        var state = TabStack.State.home
        state.path.append(Route.thread(Tweet.mocks[0]).pathState)
        state.path.append(Route.profile(.mock).pathState)
        let store = TestStore(initialState: state) {
            TabStack()
        }

        await store.send(.tabReselected) {
            $0.path = StackState()
        }
    }

    @Test
    func openingFromRootReplacesPath() async {
        let first = Tweet.mocks[0]
        let second = Tweet.mocks[1]
        var state = TabStack.State.home
        state.path.append(Route.thread(first).pathState)
        state.path.append(Route.thread(second).pathState)
        let store = TestStore(initialState: state) {
            TabStack()
        }
        store.exhaustivity = .off

        await store.send(.root(.feeds(.delegate(.open(.thread(second)))))) {
            $0.path = StackState([Route.thread(second).pathState])
        }
    }

    @Test
    func listsOpenAsAColumnAndAListOpensItsTimelineAfterIt() async {
        let list = TwitterList.mocks[0]
        let store = TestStore(initialState: TabStack.State.home) {
            TabStack()
        }
        store.exhaustivity = .off

        await store.send(.root(.feeds(.delegate(.open(.lists(userID: User.mock.id)))))) {
            $0.path = StackState([.lists(ListsFeature.State(userID: User.mock.id))])
        }
        let listsID = store.state.path.ids[0]
        await store.send(.path(.element(id: listsID, action: .lists(.listTapped(list)))))
        await store.receive(\.path[id: listsID].lists.delegate)
        #expect(store.state.path.count == 2)
        guard case .list(let feed) = store.state.path.last else {
            Issue.record("Expected a list column")
            return
        }
        #expect(feed.source == .list(id: list.id, name: list.name))
    }

    @Test
    func openingFromAnEarlierColumnReplacesTheColumnsAfterIt() async {
        let first = Tweet.mocks[0]
        let second = Tweet.mocks[1]
        var state = TabStack.State.home
        state.path.append(Route.thread(first).pathState)
        state.path.append(Route.thread(second).pathState)
        let store = TestStore(initialState: state) {
            TabStack()
        }
        store.exhaustivity = .off

        await store.send(.path(.element(id: 0, action: .thread(.delegate(.open(.profile(.mock))))))) {
            $0.path.removeLast()
            $0.path.append(Route.profile(.mock).pathState)
        }
    }

    @Test
    func openingFromPathPushes() async {
        let first = Tweet.mocks[0]
        let second = Tweet.mocks[1]
        var state = TabStack.State.home
        state.path.append(Route.thread(first).pathState)
        let store = TestStore(initialState: state) {
            TabStack()
        }
        store.exhaustivity = .off

        await store.send(.path(.element(id: 0, action: .thread(.delegate(.open(.thread(second))))))) {
            $0.path.append(Route.thread(second).pathState)
        }
    }

    @Test
    func windowRootedAtThreadOpensRepliesInDetail() async {
        let first = Tweet.mocks[0]
        let second = Tweet.mocks[1]
        let store = TestStore(initialState: TabStack.State.window(.thread(tweetID: first.id))) {
            TabStack()
        }
        store.exhaustivity = .off

        #expect(store.state.root.thread?.source == .thread(tweetID: first.id))
        await store.send(.root(.thread(.delegate(.open(.thread(second)))))) {
            $0.path = StackState([Route.thread(second).pathState])
        }
    }

    @Test
    func openingWhatTheNextColumnShowsFocusesItInsteadOfDuplicating() async {
        let first = Tweet.mocks[0]
        let second = Tweet.mocks[1]
        var state = TabStack.State.home
        state.path.append(Route.thread(first).pathState)
        state.path.append(Route.thread(second).pathState)
        let store = TestStore(initialState: state) {
            TabStack()
        }
        store.exhaustivity = .off

        await store.send(.root(.feeds(.delegate(.open(.thread(first))))))
        #expect(store.state.path.count == 1)
        #expect(store.state.path.first == Route.thread(first).pathState)
    }

    @Test
    func openingWhatTheAskingColumnShowsShakesIt() async {
        let store = TestStore(initialState: TabStack.State.profile(viewer: .mock)) {
            TabStack()
        }
        store.exhaustivity = .off

        await store.send(.root(.profile(.delegate(.open(.profileHandle(User.mock.screenName.uppercased())))))) {
            $0.shake = TabStack.ColumnShake(column: nil, count: 1)
        }
    }

    @Test
    func profileOpensItsFollowersAsTheNextColumnAndAFollowerAfterThat() async {
        let followers = Route.userList(.followers(userID: User.mock.id))
        let store = TestStore(initialState: TabStack.State.profile(viewer: .mock)) {
            TabStack()
        }
        store.exhaustivity = .off

        await store.send(.root(.profile(.delegate(.open(followers))))) {
            $0.path = StackState([followers.pathState])
        }
        await store.send(.path(.element(id: 0, action: .userList(.delegate(.open(followers)))))) {
            $0.shake = TabStack.ColumnShake(column: 0, count: 1)
        }
        await store.send(.path(.element(id: 0, action: .userList(.delegate(.open(.profile(.mockFriend))))))) {
            $0.path.append(Route.profile(.mockFriend).pathState)
        }
    }

    @Test
    func quotesOpenAsALatestSearchForThePost() {
        guard case .quotes(let feed) = Route.quotes(tweetID: "100").pathState else {
            Issue.record("Expected a quotes column")
            return
        }
        #expect(feed.source == .search(query: "quoted_tweet_id:100", latest: true))
        #expect(TabStack.State.window(.quotes(tweetID: "100")).root.quotes?.source == feed.source)
    }

    @Test
    func postActivityLinksOpenInTheApp() throws {
        let base = "https://x.com/pointfreeco/status/100"
        #expect(Route(url: try #require(URL(string: base + "/quotes"))) == .quotes(tweetID: "100"))
        #expect(Route(url: try #require(URL(string: base + "/retweets"))) == .userList(.reposters(tweetID: "100")))
        #expect(Route(url: try #require(URL(string: base + "/likes"))) == .userList(.likers(tweetID: "100")))
        #expect(Route(url: try #require(URL(string: base + "/photo/1"))) == .threadID("100"))
    }

    @Test
    func composeFromRootIsForwarded() async {
        let tweet = Tweet.mocks[0]
        let store = TestStore(initialState: TabStack.State.home) {
            TabStack()
        }

        await store.send(.root(.feeds(.delegate(.compose(Draft(replyingTo: tweet))))))
        await store.receive(\.delegate, .compose(Draft(replyingTo: tweet)))
    }
}

@MainActor
struct TabStackCancellationTests {
    @Test
    func replacingPathCancelsInFlightThreadLoad() async {
        let first = Tweet.mocks[0]
        let second = Tweet.mocks[1]
        var state = TabStack.State.home
        state.path.append(Route.thread(first).pathState)
        let store = TestStore(initialState: state) {
            TabStack()
        } withDependencies: {
            $0[TwitterClient.self].feed = { _, _ in
                try await Task.sleep(for: .seconds(60))
                return FeedPage(items: [], bottomCursor: nil, topCursor: nil)
            }
        }

        await store.send(.path(.element(id: 0, action: .thread(.task)))) {
            $0.path[id: 0, case: \.thread]?.isLoading = true
        }
        await store.send(.root(.feeds(.delegate(.open(.thread(second)))))) {
            $0.path = StackState([Route.thread(second).pathState])
        }
    }
}

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
