import ComposableArchitecture
import Foundation
import Testing

@testable import FeedFeature
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
    func reselectingTheTabWithColumnsAsksTheViewToCloseThem() async {
        var state = TabStack.State.home
        state.canShowColumns = true
        state.path.append(Route.thread(Tweet.mocks[0]).pathState)
        let store = TestStore(initialState: state) {
            TabStack()
        }

        await store.send(.tabReselected) {
            $0.closeAllColumnsRequests = 1
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

struct ColumnLayoutTests {
    @Test
    func rootIsACentredColumnOfItsOwnOnAFlatDisplay() {
        var geometry = ColumnGeometry()
        geometry.width = 950
        let layout = ColumnLayout(geometry: geometry, depth: 0)
        #expect(layout.showsColumns)
        #expect(layout.width(ofColumn: 0) == 475)
        // Drawn wider than its slot, a readable column centred on the desk.
        #expect(layout.rootDrawnWidth == ColumnLayout.readableRootWidth)
        #expect(layout.leadingInset == 155)
        #expect(layout.offset == 0)
        #expect(ColumnLayout(geometry: geometry, depth: 1).leadingInset == 0)
    }

    @Test
    func rootSpansADisplayWithNoRoomBesideIt() {
        var geometry = ColumnGeometry()
        geometry.width = 790
        let layout = ColumnLayout(geometry: geometry, depth: 0)
        #expect(layout.canShowColumns)
        #expect(!layout.showsColumns)
    }

    @Test
    func rootIsTheLeftPageAcrossAFold() {
        var geometry = ColumnGeometry()
        geometry.width = 951
        geometry.fold = 460...490
        let layout = ColumnLayout(geometry: geometry, depth: 0)
        #expect(layout.showsColumns)
        #expect(layout.width(ofColumn: 0) == 475)
        #expect(layout.leadingInset == 0)
    }

    @Test
    func narrowDisplayShowsNoColumns() {
        var geometry = ColumnGeometry()
        geometry.width = 466
        #expect(!ColumnLayout(geometry: geometry, depth: 2).showsColumns)
    }

    @Test
    func landscapeShowsTheTwoNewestColumns() {
        var geometry = ColumnGeometry()
        geometry.width = 950
        let one = ColumnLayout(geometry: geometry, depth: 1)
        let twoColumns: CGFloat = 2 * one.columnWidth
        #expect(twoColumns == geometry.width)
        #expect(one.offset == 0)
        #expect(!one.isCovered(column: 0))

        let two = ColumnLayout(geometry: geometry, depth: 2)
        #expect(two.columnWidth == one.columnWidth)
        #expect(two.offset == two.columnWidth)
        #expect(two.isCovered(column: 0))
        #expect(!two.isCovered(column: 1))
    }

    @Test
    func portraitPeeksThePreviousColumn() {
        var geometry = ColumnGeometry()
        geometry.width = 669
        let layout = ColumnLayout(geometry: geometry, depth: 1)
        #expect(layout.columnWidth == ColumnLayout.preferredColumnWidth)
        // The root keeps the whole width; the column slides over all but a sliver of it.
        #expect(layout.width(ofColumn: 0) == geometry.width)
        #expect(layout.offset == layout.columnWidth)
        #expect(layout.isCovered(column: 0))
        #expect(!layout.isCovered(column: 1))
    }

    @Test
    func activeFoldPutsColumnsOnEitherSide() {
        var geometry = ColumnGeometry()
        geometry.width = 951
        geometry.fold = 460...490
        let layout = ColumnLayout(geometry: geometry, depth: 1)
        // Two pages meeting at the fold's middle.
        #expect(layout.width(ofColumn: 0) == 475)
        #expect(layout.width(ofColumn: 1) == 476)
        #expect(layout.offset == 0)
    }

    @Test
    func activeFoldKeepsTheNewestColumnRightOfIt() {
        var geometry = ColumnGeometry()
        geometry.width = 951
        geometry.fold = 460...490
        let layout = ColumnLayout(geometry: geometry, depth: 2)
        #expect(layout.width(ofColumn: 1) == 475)
        #expect(layout.width(ofColumn: 2) == 476)
        // The first column is the page left of the fold, the newest the page right of it, and the root is off the
        // leading edge.
        #expect(layout.minX(ofColumn: 1) - layout.offset == 0)
        #expect(layout.minX(ofColumn: 2) - layout.offset == 475)
        // Slides back a page at a time, always resting with a column either side of the fold.
        #expect(layout.isScrollable)
        #expect(layout.snapOffsets == [0, 475])
    }

    @Test
    func widePanelLeavesASliverOfThePreviousColumn() {
        var geometry = ColumnGeometry()
        geometry.width = 951
        let layout = ColumnLayout(geometry: geometry, wideColumns: [true])
        #expect(layout.width(ofColumn: 1) == 951 - ColumnLayout.webPanelPeek)
        #expect(layout.width(ofColumn: 0) == layout.columnWidth)
        #expect(layout.offset == layout.columnWidth - ColumnLayout.webPanelPeek)
        #expect(layout.isCovered(column: 0))
    }

    @Test
    func widePanelKeepsToItsSideOfTheFold() {
        var geometry = ColumnGeometry()
        geometry.width = 951
        geometry.fold = 460...490
        let layout = ColumnLayout(geometry: geometry, wideColumns: [true])
        #expect(layout.width(ofColumn: 1) == 476)
    }

    @Test
    func stripRestsOnColumnEdges() {
        var geometry = ColumnGeometry()
        geometry.width = 669
        let layout = ColumnLayout(geometry: geometry, depth: 2)
        // Root at the leading edge, the first column at either edge, the newest at the trailing edge.
        #expect(layout.snapOffsets == [0, 476, 669, 952])
        #expect(layout.offset == 952)
    }

    @Test
    func newColumnSlidesInFromTheTrailingEdge() {
        var geometry = ColumnGeometry()
        geometry.width = 950
        let none = ColumnLayout(geometry: geometry, depth: 0)
        let one = ColumnLayout(geometry: geometry, depth: 1)
        let two = ColumnLayout(geometry: geometry, depth: 2)
        // The first column comes in over the half the root gave up; later ones ride in on the strip's slide.
        #expect(one.entranceOffset(ofColumn: 1, from: none) == 475)
        #expect(two.entranceOffset(ofColumn: 2, from: one) == 0)
        // Replacing the newest column brings the replacement in from the edge too.
        #expect(two.entranceOffset(ofColumn: 2, from: two) == 475)
    }
}

struct ColumnSnappingTests {
    let stops: [CGFloat] = [0, 283, 476, 759]

    @Test
    func flickGoesOnToTheNextEdgeInItsDirection() {
        #expect(ColumnSnapping.bestStop(in: stops, for: 300, velocity: 800) == 476)
        #expect(ColumnSnapping.bestStop(in: stops, for: 460, velocity: -800) == 283)
    }

    @Test
    func flickNeverSpringsBackAgainstTheFinger() {
        #expect(ColumnSnapping.bestStop(in: stops, for: 290, velocity: 800) == 476)
        #expect(ColumnSnapping.bestStop(in: stops, for: 470, velocity: -800) == 283)
    }

    @Test
    func lettingGoSettlesOnTheNearestEdge() {
        #expect(ColumnSnapping.bestStop(in: stops, for: 300, velocity: 0) == 283)
        #expect(ColumnSnapping.bestStop(in: stops, for: 400, velocity: 0) == 476)
    }

    @Test
    func pullingPastEitherEndSettlesAtThatEnd() {
        #expect(ColumnSnapping.bestStop(in: stops, for: -150, velocity: -800) == 0)
        #expect(ColumnSnapping.bestStop(in: stops, for: 900, velocity: 800) == 759)
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
