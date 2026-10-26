import ComposableArchitecture
import Testing

@testable import FeedFeature
@testable import Models
@testable import ProfileFeature
@testable import Routing
@testable import TabStackFeature
@testable import TwitterClient

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

    /// Reselecting the tab closes every column while their loads are on their way: each column's effects (its own and
    /// its children's, like a profile's timelines) end with it, so nothing comes back for a screen that's gone.
    @Test
    func reselectingTheTabCancelsTheClosedColumnsLoads() async {
        var state = TabStack.State.home
        state.path.append(Route.thread(Tweet.mocks[0]).pathState)
        state.path.append(Route.profile(.mockFriend).pathState)
        let store = TestStore(initialState: state) {
            TabStack()
        } withDependencies: {
            $0[TwitterClient.self].feed = { _, _ in
                try await Task.sleep(for: .seconds(60))
                return FeedPage(items: [], bottomCursor: nil, topCursor: nil)
            }
            $0[TwitterClient.self].user = { _ in
                try await Task.sleep(for: .seconds(60))
                return .mockFriend
            }
        }
        let posts = FeedSource.userPosts(userID: User.mockFriend.id)

        await store.send(.path(.element(id: 0, action: .thread(.task)))) {
            $0.path[id: 0, case: \.thread]?.isLoading = true
        }
        await store.send(.path(.element(id: 1, action: .profile(.task)))) {
            $0.path[id: 1, case: \.profile]?.isFetchingUser = true
        }
        let postsTask = TabStackPath.Action.profile(.feeds(.feeds(.element(id: posts, action: .task))))
        await store.send(.path(.element(id: 1, action: postsTask))) {
            $0.path[id: 1, case: \.profile]?.feeds?.feeds[id: posts]?.isLoading = true
        }
        await store.send(.tabReselected) {
            $0.path = StackState()
        }
    }

    /// A column closed from UIKit (pulled down, thrown away, swiped back) leaves the path with every column after it,
    /// and their loads end with them.
    @Test
    func closingAColumnCancelsItsLoadsAndThoseOfTheColumnsAfterIt() async {
        var state = TabStack.State.home
        state.path.append(Route.thread(Tweet.mocks[0]).pathState)
        state.path.append(Route.thread(Tweet.mocks[1]).pathState)
        state.path.append(Route.profile(.mockFriend).pathState)
        let store = TestStore(initialState: state) {
            TabStack()
        } withDependencies: {
            $0[TwitterClient.self].feed = { _, _ in
                try await Task.sleep(for: .seconds(60))
                return FeedPage(items: [], bottomCursor: nil, topCursor: nil)
            }
            $0[TwitterClient.self].user = { _ in
                try await Task.sleep(for: .seconds(60))
                return .mockFriend
            }
        }

        await store.send(.path(.element(id: 1, action: .thread(.task)))) {
            $0.path[id: 1, case: \.thread]?.isLoading = true
        }
        await store.send(.path(.element(id: 2, action: .profile(.task)))) {
            $0.path[id: 2, case: \.profile]?.isFetchingUser = true
        }
        await store.send(.path(.popFrom(id: 1))) {
            $0.path.removeLast(2)
        }
    }

    /// What's opened from an earlier column replaces the ones after it; a load the replaced column had going is
    /// cancelled rather than answering into whatever now has its place.
    @Test
    func openingFromAnEarlierColumnCancelsTheReplacedColumnsLoads() async {
        var state = TabStack.State.home
        state.path.append(Route.thread(Tweet.mocks[0]).pathState)
        state.path.append(Route.profile(.mockFriend).pathState)
        let store = TestStore(initialState: state) {
            TabStack()
        } withDependencies: {
            $0[TwitterClient.self].user = { _ in
                try await Task.sleep(for: .seconds(60))
                return .mockFriend
            }
        }

        await store.send(.path(.element(id: 1, action: .profile(.task)))) {
            $0.path[id: 1, case: \.profile]?.isFetchingUser = true
        }
        await store.send(.path(.element(id: 0, action: .thread(.delegate(.open(.thread(Tweet.mocks[1]))))))) {
            $0.path.removeLast()
            $0.path.append(Route.thread(Tweet.mocks[1]).pathState)
        }
    }
}
