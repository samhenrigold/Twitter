import ComposableArchitecture
import Foundation
import Testing

@testable import FeedFeature
@testable import Models
@testable import TwitterClient
@testable import TwitterDatabase

@MainActor
struct FeedCacheTests {
    @Test
    func firstLoadShowsCacheThenPutsFreshPostsAboveWithAGap() async {
        let cached = FeedPage(cachedItems: [.tweet(FeedTweet(tweet: Tweet.mocks[0]))], bottomCursor: "stale")
        let fresh = FeedPage(items: [.tweet(FeedTweet(tweet: Tweet.mocks[1]))], bottomCursor: "next", topCursor: nil)
        let saved = LockIsolated<[FeedPage]>([])
        let store = TestStore(initialState: FeedFeature.State(source: .home(following: false))) {
            FeedFeature()
        } withDependencies: {
            $0.date.now = Date(timeIntervalSince1970: 0)
            $0[TimelineCache.self].load = { _ in cached }
            $0[TimelineCache.self].topItemID = { _ in FeedItem.tweet(FeedTweet(tweet: Tweet.mocks[0])).id }
            $0[TimelineCache.self].save = { _, page, isRefresh in
                #expect(isRefresh)
                saved.withValue { $0.append(page) }
            }
            $0[TwitterClient.self].feed = { _, _ in fresh }
        }

        await store.send(.task) {
            $0.isLoading = true
        }
        // The only cached item is the top one, so there's nowhere to restore to.
        await store.receive(\.cachedPageLoaded) {
            $0.items = IdentifiedArray(uniqueElements: cached.items)
            $0.cachedBottomCursor = "stale"
        }
        let merged: IdentifiedArrayOf<FeedItem> = [
            fresh.items[0], .showMore(TimelineMerge.gap(cursor: "next")), cached.items[0]
        ]
        await store.receive(\.pageResponse) {
            $0.isLoading = false
            $0.hasLoaded = true
            $0.lastRefreshed = Date(timeIntervalSince1970: 0)
            $0.items = merged
            $0.bottomCursor = "stale"
            $0.cachedBottomCursor = nil
        }
        #expect(saved.value.map { $0.items.map(\.id) } == [merged.ids.elements])
    }

    @Test
    func rebuiltViewReturnsToWhereScrollingStopped() async {
        let items: [FeedItem] = Tweet.mocks.prefix(3).map { .tweet(FeedTweet(tweet: $0)) }
        var state = FeedFeature.State(source: .home(following: false), items: IdentifiedArray(uniqueElements: items))
        state.hasLoaded = true
        let clock = TestClock()
        let saved = LockIsolated<FeedItem.ID?>(nil)
        let store = TestStore(initialState: state) {
            FeedFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0[TimelineCache.self].saveTopItemID = { _, id in saved.setValue(id) }
        }

        await store.send(.scrollStopped(topItemID: items[2].id)) {
            $0.lastTopItemID = items[2].id
        }
        await clock.advance(by: .seconds(1))
        #expect(saved.value == items[2].id)
        // Folding or unfolding rebuilds the view, which starts again from its task.
        await store.send(.task) {
            $0.restoringTopItemID = items[2].id
        }
    }

    @Test
    func freshPostsAboveTheReaderAreCountedNotShown() async {
        let reading = FeedItem.tweet(FeedTweet(tweet: Tweet.mocks[0]))
        let newer = FeedItem.tweet(FeedTweet(tweet: Tweet.mocks[1]))
        var state = FeedFeature.State(source: .home(following: false), items: [reading])
        state.hasLoaded = true
        state.isAtTop = false
        state.bottomCursor = "older"
        let store = TestStore(initialState: state) {
            FeedFeature()
        } withDependencies: {
            $0.date.now = Date(timeIntervalSince1970: 0)
            $0[TwitterClient.self].feed = { _, _ in
                FeedPage(items: [newer, reading], bottomCursor: "page", topCursor: nil)
            }
        }

        await store.send(.refreshPulled) {
            $0.isLoading = true
        }
        await store.receive(\.pageResponse) {
            $0.isLoading = false
            $0.lastRefreshed = Date(timeIntervalSince1970: 0)
            $0.items = [newer, reading]
            $0.newPostCount = 1
        }
        await store.send(.isAtTopChanged(true)) {
            $0.isAtTop = true
            $0.newPostCount = 0
        }
    }
}
