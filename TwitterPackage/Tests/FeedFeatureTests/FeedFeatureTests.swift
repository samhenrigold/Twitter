import ComposableArchitecture
import Foundation
import Testing

@testable import FeedFeature
@testable import Models
@testable import Routing
@testable import TweetEngagement
@testable import TwitterClient
@testable import TwitterDatabase

@MainActor
struct FeedFeatureTests {
    @Test
    func taskLoadsFirstPage() async {
        let page = FeedPage(items: [.tweet(FeedTweet(tweet: Tweet.mocks[0]))], bottomCursor: "next", topCursor: nil)
        let store = TestStore(initialState: FeedFeature.State(source: .home(following: false))) {
            FeedFeature()
        } withDependencies: {
            $0.date.now = Date(timeIntervalSince1970: 0)
            $0[TwitterClient.self].feed = { _, cursor in
                #expect(cursor == nil)
                return page
            }
        }

        await store.send(.task) {
            $0.isLoading = true
        }
        await store.receive(\.pageResponse) {
            $0.isLoading = false
            $0.hasLoaded = true
            $0.lastRefreshed = Date(timeIntervalSince1970: 0)
            $0.items = IdentifiedArray(uniqueElements: page.items)
            $0.bottomCursor = "next"
        }
    }

    @Test
    func choosingTheTabRefreshesOnlyOnceStaleOrWhenThereIsSomethingNew() async {
        var state = FeedFeature.State(source: .home(following: false))
        state.hasLoaded = true
        state.lastRefreshed = Date(timeIntervalSince1970: 0)
        let store = TestStore(initialState: state) {
            FeedFeature()
        } withDependencies: {
            $0.date.now = Date(timeIntervalSince1970: 60)
            $0[TwitterClient.self].feed = { _, _ in FeedPage(items: [], bottomCursor: nil, topCursor: nil) }
            $0[TimelineCache.self].save = { _, _, _ in }
        }

        // A minute on: still fresh.
        await store.send(.tabSelected(hasNew: false))
        // Something new: refreshes anyway.
        await store.send(.tabSelected(hasNew: true)) {
            $0.isLoading = true
        }
        await store.receive(\.pageResponse) {
            $0.isLoading = false
            $0.lastRefreshed = Date(timeIntervalSince1970: 60)
        }
    }

    @Test
    func loadingNotificationsMarksThemRead() async {
        let page = FeedPage(items: [], bottomCursor: nil, topCursor: "top-cursor")
        let readCursor = LockIsolated<String?>(nil)
        var state = FeedFeature.State(source: .notifications(.all))
        state.hasLoaded = true
        let store = TestStore(initialState: state) {
            FeedFeature()
        } withDependencies: {
            $0.date.now = Date(timeIntervalSince1970: 0)
            $0[TwitterClient.self].feed = { _, _ in page }
            $0[TwitterClient.self].markNotificationsRead = { readCursor.setValue($0) }
            $0[TimelineCache.self].save = { _, _, _ in }
        }

        await store.send(.refreshPulled) {
            $0.isLoading = true
        }
        await store.receive(\.pageResponse) {
            $0.isLoading = false
            $0.lastRefreshed = Date(timeIntervalSince1970: 0)
        }
        #expect(readCursor.value == "top-cursor")
    }

    @Test
    func rowNearBottomLoadsNextPage() async {
        let first = Tweet.mocks[0]
        let second = Tweet.mocks[1]
        var state = FeedFeature.State(
            source: .home(following: true),
            items: [.tweet(FeedTweet(tweet: first))]
        )
        state.bottomCursor = "cursor-1"
        state.hasLoaded = true
        let store = TestStore(initialState: state) {
            FeedFeature()
        } withDependencies: {
            $0[TwitterClient.self].feed = { _, cursor in
                #expect(cursor == "cursor-1")
                return FeedPage(items: [.tweet(FeedTweet(tweet: second))], bottomCursor: nil, topCursor: nil)
            }
        }

        await store.send(.rowAppeared(FeedItem.tweet(FeedTweet(tweet: first)).id)) {
            $0.isLoading = true
        }
        await store.receive(\.pageResponse) {
            $0.isLoading = false
            $0.items.append(.tweet(FeedTweet(tweet: second)))
            $0.bottomCursor = nil
        }
    }

    @Test
    func likeUpdatesSharedEngagementAndSyncs() async {
        var tweet = Tweet.mocks[0]
        tweet.likeCount = 10
        tweet.repostCount = 2
        tweet.bookmarkCount = 1
        tweet.isLiked = false
        tweet.isReposted = true
        tweet.isBookmarked = false
        let synced = LockIsolated<[String]>([])
        let store = TestStore(
            initialState: FeedFeature.State(source: .bookmarks, items: [.tweet(FeedTweet(tweet: tweet))])
        ) {
            FeedFeature()
        } withDependencies: {
            $0[TweetEngagementSync.self].sync = { tweetID, interaction in
                synced.withValue { $0.append("\(tweetID)-\(interaction)") }
            }
        }

        await store.send(.likeButtonTapped(tweet)) {
            $0.$engagements.withLock {
                $0 = [
                    tweet.id: Engagement(
                        bookmark: Engagement.Toggle(desired: false, server: false, serverCount: 1),
                        like: Engagement.Toggle(desired: true, server: false, serverCount: 10),
                        repost: Engagement.Toggle(desired: true, server: true, serverCount: 2)
                    )
                ]
            }
        }
        #expect(store.state.engagements[tweet.id]?.like.count == 11)
        await store.finish()
        #expect(synced.value == ["\(tweet.id)-like"])
    }

    @Test
    func tappingTweetOpensThread() async {
        let tweet = Tweet.mocks[0]
        let store = TestStore(initialState: FeedFeature.State(source: .home(following: false))) {
            FeedFeature()
        }

        await store.send(.tweetTapped(tweet))
        await store.receive(\.delegate, .open(.thread(tweet)))
    }

    @Test
    func tappingFocusedTweetInThreadDoesNothing() async {
        let tweet = Tweet.mocks[0]
        let store = TestStore(initialState: FeedFeature.State(source: .thread(tweetID: tweet.id))) {
            FeedFeature()
        }

        await store.send(.tweetTapped(tweet))
    }

    @Test
    func mentionLinkOpensProfile() async throws {
        let store = TestStore(initialState: FeedFeature.State(source: .home(following: false))) {
            FeedFeature()
        }
        let url = try #require(URL(string: "\(Route.scheme)://user/pointfreeco"))

        await store.send(.linkTapped(url))
        await store.receive(\.delegate, .open(.profileHandle("pointfreeco")))
    }

    @Test
    func webLinkOpensWebPanel() async throws {
        let store = TestStore(initialState: FeedFeature.State(source: .home(following: false))) {
            FeedFeature()
        }
        let url = try #require(URL(string: "https://www.pointfree.co/episodes"))

        await store.send(.linkTapped(url))
        await store.receive(\.delegate, .open(.web(url)))
    }

    @Test
    func postLinkOpensInApp() async throws {
        let store = TestStore(initialState: FeedFeature.State(source: .home(following: false))) {
            FeedFeature()
        }
        let url = try #require(URL(string: "https://x.com/pointfreeco/status/12345"))

        await store.send(.linkTapped(url))
        await store.receive(\.delegate, .open(.threadID("12345")))
    }

    @Test
    func linkToTheThreadItselfDoesNothing() async throws {
        let store = TestStore(initialState: FeedFeature.State(source: .thread(tweetID: "12345"))) {
            FeedFeature()
        }
        let url = try #require(URL(string: "https://twitter.com/pointfreeco/status/12345"))

        await store.send(.linkTapped(url))
    }

    @Test
    func nonWebLinkGoesToTheSystem() async throws {
        let opened = LockIsolated<[URL]>([])
        let store = TestStore(initialState: FeedFeature.State(source: .home(following: false))) {
            FeedFeature()
        } withDependencies: {
            $0.openURL = OpenURLEffect { url in
                opened.withValue { $0.append(url) }
                return true
            }
        }
        let url = try #require(URL(string: "mailto:hello@example.com"))

        await store.send(.linkTapped(url))
        await store.finish()
        #expect(opened.value == [url])
    }

    @Test
    func showMoreRepliesLoadsCursorAndReplacesRowInPlace() async {
        let focused = Tweet.mocks[0]
        let after = Tweet.mocks[2]
        let reply = Tweet.mocks[1]
        let cursor = ShowMoreCursor(id: "cursor-showmore-1", cursor: "more")
        let tombstone = Tombstone(id: "tweet-9", text: "This Tweet is unavailable.")
        var state = FeedFeature.State(
            source: .thread(tweetID: focused.id),
            items: [.tweet(FeedTweet(tweet: focused)), .showMore(cursor), .tweet(FeedTweet(tweet: after))]
        )
        state.bottomCursor = "bottom"
        state.hasLoaded = true
        let store = TestStore(initialState: state) {
            FeedFeature()
        } withDependencies: {
            $0[TwitterClient.self].feed = { source, requested in
                #expect(source == .thread(tweetID: focused.id))
                #expect(requested == "more")
                return FeedPage(
                    items: [
                        .tweet(FeedTweet(tweet: reply)), .tombstone(tombstone),
                        // Already on screen; must not be duplicated.
                        .tweet(FeedTweet(tweet: after))
                    ],
                    bottomCursor: "ignored",
                    topCursor: nil
                )
            }
        }

        await store.send(.showMoreButtonTapped(cursor)) {
            $0.loadingShowMoreIDs = [FeedItem.showMore(cursor).id]
        }
        await store.receive(\.showMoreResponse) {
            $0.loadingShowMoreIDs = []
            $0.items = [
                .tweet(FeedTweet(tweet: focused)), .tweet(FeedTweet(tweet: reply)), .tombstone(tombstone),
                .tweet(FeedTweet(tweet: after))
            ]
        }
        // Nothing was engaged with, so loading replies leaves the shared engagements untouched.
        #expect(store.state.engagements.isEmpty)
        #expect(store.state.bottomCursor == "bottom")
    }

    @Test
    func replyThreadJoinsItsConversationAndLoadsWhatsAboveIt() async {
        let root = Tweet.mocks[0]
        let parent = Tweet.mocks[1]
        let reply = Tweet.mocks[2]
        let earlier = ShowMoreCursor(
            id: FeedFeature.State.earlierConversationID, cursor: "top", label: "Show earlier Tweets")
        let store = TestStore(
            initialState: FeedFeature.State(
                source: .thread(tweetID: reply.id), items: [.tweet(FeedTweet(tweet: reply))])
        ) {
            FeedFeature()
        } withDependencies: {
            $0.date.now = Date(timeIntervalSince1970: 0)
            $0[TwitterClient.self].feed = { _, cursor in
                cursor == "top"
                    ? FeedPage(items: [.tweet(FeedTweet(tweet: root))], bottomCursor: nil, topCursor: nil)
                    : FeedPage(
                        items: [.tweet(FeedTweet(tweet: parent)), .tweet(FeedTweet(tweet: reply))],
                        bottomCursor: nil,
                        topCursor: "top"
                    )
            }
            $0[TimelineCache.self].load = { _ in nil }
        }
        func joined(_ tweet: Tweet, above: Bool, below: Bool) -> FeedItem {
            var item = FeedTweet(tweet: tweet)
            item.connectsAbove = above
            item.connectsBelow = below
            return .tweet(item)
        }

        await store.send(.task) {
            $0.isLoading = true
        }
        await store.receive(\.pageResponse) {
            $0.isLoading = false
            $0.hasLoaded = true
            $0.lastRefreshed = Date(timeIntervalSince1970: 0)
            $0.items = [
                .showMore(earlier), joined(parent, above: false, below: true), joined(reply, above: true, below: false)
            ]
        }
        await store.send(.showMoreButtonTapped(earlier)) {
            $0.loadingShowMoreIDs = [FeedItem.showMore(earlier).id]
        }
        await store.receive(\.showMoreResponse) {
            $0.loadingShowMoreIDs = []
            $0.items = [
                joined(root, above: false, below: true), joined(parent, above: true, below: true),
                joined(reply, above: true, below: false)
            ]
        }
    }

    @Test
    func deletingAPostConfirmsThenRemovesItAndRestoresItIfTwitterRefuses() async {
        struct Refused: Error {}
        let mine = Tweet.mocks[1]
        let other = Tweet.mocks[0]
        var state = FeedFeature.State(
            source: .home(following: false),
            items: [.tweet(FeedTweet(tweet: other)), .tweet(FeedTweet(tweet: mine))]
        )
        state.hasLoaded = true
        let store = TestStore(initialState: state) {
            FeedFeature()
        } withDependencies: {
            $0[TwitterClient.self].deleteTweet = { id in
                #expect(id == mine.id)
                throw Refused()
            }
        }
        store.exhaustivity = .off(showSkippedAssertions: false)

        await store.send(.deleteButtonTapped(mine))
        #expect(store.state.alert != nil)
        await store.send(.alert(.presented(.confirmDelete(tweetID: mine.id))))
        #expect(store.state.items.map(\.id) == [FeedItem.tweet(FeedTweet(tweet: other)).id])
        await store.receive(\.deleteFailed)
        #expect(store.state.items.map(\.id) == state.items.map(\.id))
        #expect(store.state.alert != nil)
    }

    @Test
    func votingCountsAtOnceAndUndoesIfTwitterRefuses() async {
        struct Refused: Error {}
        let poll = Tweet.mockOpenPoll
        var state = FeedFeature.State(source: .home(following: false), items: [.tweet(FeedTweet(tweet: poll))])
        state.hasLoaded = true
        let store = TestStore(initialState: state) {
            FeedFeature()
        } withDependencies: {
            $0.date.now = Date()
            $0[TwitterClient.self].vote = { tweetID, _, choice in
                #expect(tweetID == poll.id)
                #expect(choice == 1)
                throw Refused()
            }
        }
        store.exhaustivity = .off

        await store.send(.pollChoiceTapped(tweetID: poll.id, choice: 1))
        #expect(store.state.poll(of: poll.id)?.selectedChoiceIndex == 1)
        #expect(store.state.poll(of: poll.id)?.choices[1].count == 1_023)
        await store.receive(\.pollVoteFailed)
        #expect(store.state.poll(of: poll.id)?.selectedChoiceIndex == nil)
        #expect(store.state.poll(of: poll.id)?.choices[1].count == 1_022)
    }

    @Test
    func unbookmarkingInBookmarksTakesThePostOut() async {
        var tweet = Tweet.mocks[0]
        tweet.isBookmarked = true
        let state = FeedFeature.State(source: .bookmarks, items: [.tweet(FeedTweet(tweet: tweet))])
        state.$engagements.withLock { $0.refresh(from: [tweet]) }
        let store = TestStore(initialState: state) {
            FeedFeature()
        } withDependencies: {
            $0[TweetEngagementSync.self].sync = { _, _ in }
        }
        store.exhaustivity = .off

        await store.send(.bookmarkButtonTapped(tweet))
        #expect(store.state.items.isEmpty)
    }

    @Test
    func showMoreFailureKeepsRow() async {
        struct Failure: Error {}
        let cursor = ShowMoreCursor(id: "cursor-showmore-1", cursor: "more")
        let store = TestStore(
            initialState: FeedFeature.State(source: .thread(tweetID: "1"), items: [.showMore(cursor)])
        ) {
            FeedFeature()
        } withDependencies: {
            $0[TwitterClient.self].feed = { _, _ in throw Failure() }
        }

        await store.send(.showMoreButtonTapped(cursor)) {
            $0.loadingShowMoreIDs = [FeedItem.showMore(cursor).id]
        }
        await store.receive(\.showMoreResponse) {
            $0.loadingShowMoreIDs = []
        }
    }

    @Test
    func blockIsOptimisticAndRevertsOnFailure() async {
        struct Failure: Error {}
        let tweet = Tweet.mocks[0]
        let calls = LockIsolated<[Bool]>([])
        let store = TestStore(
            initialState: FeedFeature.State(source: .home(following: false), items: [.tweet(FeedTweet(tweet: tweet))])
        ) {
            FeedFeature()
        } withDependencies: {
            $0[TwitterClient.self].setBlocking = { isBlocking, userID in
                #expect(userID == tweet.author.id)
                calls.withValue { $0.append(isBlocking) }
                throw Failure()
            }
        }

        var blocked = tweet
        blocked.author.isBlocking = true
        await store.send(.blockButtonTapped(tweet.author)) {
            $0.items = [.tweet(FeedTweet(tweet: blocked))]
        }
        await store.receive(\.blockFailed) {
            $0.items = [.tweet(FeedTweet(tweet: tweet))]
        }
        #expect(calls.value == [true])
    }

    @Test
    func replyIsIgnoredWhenViewerCantReply() async {
        var tweet = Tweet.mocks[0]
        tweet.replyRestriction = ReplyRestriction(policy: .mentioned, viewerCanReply: false)
        let store = TestStore(initialState: FeedFeature.State(source: .home(following: false))) {
            FeedFeature()
        }

        await store.send(.replyButtonTapped(tweet))
    }
}

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
