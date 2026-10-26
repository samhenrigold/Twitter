import ComposableArchitecture
import Foundation
import Testing

@testable import FeedFeature
@testable import Models
@testable import TwitterClient
@testable import TwitterDatabase

@MainActor
struct MarkAsViewedTests {
    @Test
    func loadingNotificationsDoesNotMarkThemRead() async {
        let page = FeedPage(items: [unread("a")], bottomCursor: nil, topCursor: "top-cursor")
        let store = TestStore(initialState: FeedFeature.State(source: .notifications(.all))) {
            FeedFeature()
        } withDependencies: {
            $0.date.now = Date(timeIntervalSince1970: 0)
            $0[TwitterClient.self].feed = { _, _ in page }
            $0[TwitterClient.self].markNotificationsRead = { _ in Issue.record("Marked read on load") }
            $0[TimelineCache.self].load = { _ in nil }
            $0[TimelineCache.self].save = { _, _, _ in }
        }

        await store.send(.task) {
            $0.isLoading = true
        }
        await store.receive(\.pageResponse) {
            $0.isLoading = false
            $0.hasLoaded = true
            $0.lastRefreshed = Date(timeIntervalSince1970: 0)
            $0.topCursor = "top-cursor"
            $0.items = [unread("a")]
        }
    }

    @Test
    func rowsSeenOnceSettledAreReadAndTheCursorIsSentOnce() async {
        let clock = TestClock()
        let sent = LockIsolated<[String]>([])
        let store = TestStore(initialState: loaded()) {
            FeedFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0[TwitterClient.self].markNotificationsRead = { cursor in sent.withValue { $0.append(cursor) } }
        }

        await store.send(.visibilityChanged(isOnScreen: true)) {
            $0.isOnScreen = true
        }
        await store.send(.rowViewedChanged(unread("a").id, isViewed: true)) {
            $0.viewedItemIDs = [unread("a").id]
        }
        await clock.advance(by: .milliseconds(499))
        #expect(sent.value.isEmpty)
        await clock.advance(by: .milliseconds(1))
        // Only the row seen loses its blue; the one below it isn't seen yet.
        await store.receive(\.viewingSettled) {
            $0.items[id: unread("a").id]?.isUnread = false
            $0.lastSeenCursor = "top-cursor"
        }
        #expect(sent.value == ["top-cursor"])

        // Scrolled on to the next: it's read, but Twitter has already been told about this cursor.
        await store.send(.scrollPhaseChanged(isScrolling: true)) {
            $0.isScrolling = true
        }
        await store.send(.rowViewedChanged(unread("b").id, isViewed: true)) {
            $0.viewedItemIDs.insert(unread("b").id)
        }
        await store.send(.scrollPhaseChanged(isScrolling: false)) {
            $0.isScrolling = false
            $0.items[id: unread("b").id]?.isUnread = false
        }
        #expect(sent.value == ["top-cursor"])
    }

    @Test
    func dragCancelsThePendingMark() async {
        let clock = TestClock()
        let store = TestStore(initialState: loaded()) {
            FeedFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0[TwitterClient.self].markNotificationsRead = { _ in Issue.record("Marked read mid-drag") }
        }

        await store.send(.visibilityChanged(isOnScreen: true)) {
            $0.isOnScreen = true
        }
        await store.send(.rowViewedChanged(unread("a").id, isViewed: true)) {
            $0.viewedItemIDs = [unread("a").id]
        }
        await clock.advance(by: .milliseconds(300))
        await store.send(.scrollPhaseChanged(isScrolling: true)) {
            $0.isScrolling = true
        }
        // Dragged back off it before coming to rest: nothing seen, nothing sent.
        await store.send(.rowViewedChanged(unread("a").id, isViewed: false)) {
            $0.viewedItemIDs = []
        }
        await clock.advance(by: .seconds(1))
        await store.send(.scrollPhaseChanged(isScrolling: false)) {
            $0.isScrolling = false
        }
    }

    @Test
    func goingOffScreenCancelsThePendingMark() async {
        let clock = TestClock()
        let store = TestStore(initialState: loaded()) {
            FeedFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0[TwitterClient.self].markNotificationsRead = { _ in Issue.record("Marked read off screen") }
        }

        await store.send(.visibilityChanged(isOnScreen: true)) {
            $0.isOnScreen = true
        }
        await store.send(.rowViewedChanged(unread("a").id, isViewed: true)) {
            $0.viewedItemIDs = [unread("a").id]
        }
        await store.send(.visibilityChanged(isOnScreen: false)) {
            $0.isOnScreen = false
            $0.viewedItemIDs = []
        }
        await clock.advance(by: .seconds(1))
    }

    @Test
    func otherFeedsDoNotMarkAnything() async {
        let store = TestStore(initialState: FeedFeature.State(source: .notifications(.mentions))) {
            FeedFeature()
        }

        await store.send(.visibilityChanged(isOnScreen: true))
        await store.send(.rowViewedChanged(unread("a").id, isViewed: true))
        await store.send(.scrollPhaseChanged(isScrolling: true))
    }

    @Test
    func aRowIsSeenWithEachEdgeNearlyOnScreenOrHalfOfItShowing() {
        func isViewed(_ top: CGFloat, _ bottom: CGFloat) -> Bool {
            MarkAsViewed.isViewed(top: top, bottom: bottom, visibleTop: 100, visibleBottom: 700)
        }
        #expect(isViewed(100, 200))
        // Cut off by less than 25 points, or with half of it showing.
        #expect(isViewed(76, 176))
        #expect(isViewed(60, 300))
        #expect(isViewed(600, 800))
        #expect(!isViewed(0, 180))
        #expect(!isViewed(640, 800))
        // Taller than the screen: seen while its middle is on screen.
        #expect(isViewed(-200, 1200))
        #expect(!isViewed(-1000, 500))
        // Off screen altogether.
        #expect(!isViewed(0, 90))
    }

    private func unread(_ id: String) -> FeedItem {
        .notification(
            TwitterNotification(id: id, icon: "person_icon", message: "Followed you", users: [], isUnread: true))
    }

    private func loaded() -> FeedFeature.State {
        var state = FeedFeature.State(source: .notifications(.all), items: [unread("a"), unread("b")])
        state.hasLoaded = true
        state.topCursor = "top-cursor"
        return state
    }
}
