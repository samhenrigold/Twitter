import ComposableArchitecture
import Foundation
import Testing

@testable import FeedFeature
@testable import ListsFeature
@testable import Models
@testable import Routing
@testable import TabStackFeature
@testable import TwitterClient

@MainActor
struct TabStackFeatureTests {
    @Test
    func reselectingTheTabAtItsRootScrollsTheTimelineToTheTopAndRefreshes() async {
        let store = TestStore(initialState: TabStack.State.home) {
            TabStack()
        } withDependencies: {
            $0[TwitterClient.self] = .previewValue
            $0.date.now = Date(timeIntervalSince1970: 0)
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
