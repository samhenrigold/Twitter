import ComposableArchitecture
import Foundation
import ImagePipeline
import Models
import PostText
import Routing
import TweetEngagement
import TwitterClient
import TwitterDatabase
import TwitterUI

@Reducer
package struct FeedFeature {
    @ObservableState
    package struct State: Equatable, Identifiable {
        var bottomCursor: String?
        /// The cursor saved with the cached page: used to keep paging past cached posts once fresh ones land above.
        var cachedBottomCursor: String?
        @Shared(.engagements) var engagements
        var errorMessage: String?
        var hasLoaded = false
        var isLoading = false
        /// When the timeline last came fresh from Twitter (not the cache).
        var lastRefreshed: Date?
        var items: IdentifiedArrayOf<FeedItem> = []
        /// Whether the top of the timeline is on screen. Seeing the top is what counts as reading.
        var isAtTop = true
        /// "Show more replies" rows whose page is loading.
        var loadingShowMoreIDs: Set<FeedItem.ID> = []
        /// Posts that arrived above where the reader is, not yet scrolled up to.
        var newPostCount = 0
        /// The thread a long-pressed post opens to, live in its context menu's preview while the menu is up. Presented
        /// here rather than in a store of the preview's own so it loads with this feed's dependencies (the mock client
        /// under `--mock-twitter`, in tests), and so its loading is cancelled when the menu goes away.
        @Presents var alert: AlertState<Action.Alert>?
        @Presents var preview: FeedFeature.State?
        /// The post whose text is up in the system's translation sheet.
        var translating: Tweet?
        /// The item at the top of the screen when scrolling last stopped, to return to when the feed's view is rebuilt
        /// (folding or unfolding the device).
        var lastTopItemID: FeedItem.ID?
        /// Where to put the reader back once cached items are on screen; cleared once the view has scrolled there.
        var restoringTopItemID: FeedItem.ID?
        /// Counts requests to scroll back to the top (the tab tapped again); the view scrolls on each change.
        var scrollToTopRequests = 0
        package let source: FeedSource

        package var id: FeedSource { source }

        /// The post a thread is about; it anchors the thread's scroll position.
        var focusedItemID: FeedItem.ID? {
            guard case .thread(let tweetID) = source else { return nil }
            return items.first { $0.tweets.first?.id == tweetID }?.id
        }

        package init(source: FeedSource, items: IdentifiedArrayOf<FeedItem> = []) {
            self.source = source
            self.items = items
        }

        /// Where a thread's focused post is: the rows before it are the conversation above it, the rest its replies.
        /// The start when the post isn't (yet) in the thread.
        var focusedIndex: Int {
            focusedItemID.flatMap { items.index(id: $0) } ?? 0
        }

        static let earlierConversationID = "cursor-top-conversation"
        /// How long a timeline stays fresh: coming back to its tab after longer than this loads what's new.
        static let staleInterval: TimeInterval = 120

        /// Timelines the reader works through keep their place; a thread or a search is read fresh each time.
        var keepsReadingPosition: Bool {
            switch source {
            case .search, .searchMedia, .thread: false
            case .bookmarks, .home, .list, .notifications, .userLikes, .userMedia, .userPosts, .userReplies: true
            }
        }
    }

    package enum Action {
        case alert(PresentationAction<Alert>)
        case authorTapped(User)
        case blockButtonTapped(User)
        case blockFailed(userID: String, isBlocking: Bool)
        case bookmarkButtonTapped(Tweet)
        case cachedPageLoaded(FeedPage, topItemID: FeedItem.ID?)
        case delegate(ContentDelegate)
        case deleteButtonTapped(Tweet)
        /// Twitter refused to delete a post: the rows taken out for it go back where they were.
        case deleteFailed(removed: [Int: FeedItem], message: String)
        case isAtTopChanged(Bool)
        case likeButtonTapped(Tweet)
        /// Who liked a post. Only the viewer's own posts list anyone, since Twitter made likes private.
        case likesButtonTapped(Tweet)
        case linkTapped(URL)
        case muteButtonTapped(User)
        case muteFailed(userID: String, isMuting: Bool)
        case newPostsButtonTapped
        case pageResponse(Result<FeedPage, any Error>, isRefresh: Bool)
        case pollChoiceTapped(tweetID: Tweet.ID, choice: Int)
        case pollVoteFailed(tweetID: Tweet.ID, choice: Int)
        indirect case preview(PresentationAction<FeedFeature.Action>)
        /// A post's context menu preview went away. Identified by post, since the next menu's preview can appear
        /// before the last one's has gone.
        case previewHidden(tweetID: Tweet.ID)
        case previewShown(Tweet)
        case quoteButtonTapped(Tweet)
        case quotesButtonTapped(Tweet)
        case refreshPulled
        case replyButtonTapped(Tweet)
        case repostButtonTapped(Tweet)
        case repostsButtonTapped(Tweet)
        /// Its tab's button tapped while it's showing: back to the top, and fetch what's new.
        case reselected
        case retryButtonTapped
        case rowAppeared(FeedItem.ID)
        case scrollStopped(topItemID: FeedItem.ID)
        case showMoreButtonTapped(ShowMoreCursor)
        case showMoreResponse(ShowMoreCursor, Result<FeedPage, any Error>)
        /// Its tab was chosen: refreshes if it's been a while, or right away when Twitter has said there's something new
        /// (`hasNew`, for Notifications' unread count).
        case tabSelected(hasNew: Bool)
        case task
        case topItemRestored
        case translateButtonTapped(Tweet)
        case translationDismissed
        case tweetTapped(Tweet)

        package enum Alert: Equatable {
            case confirmDelete(tweetID: Tweet.ID)
        }
    }

    enum CancelID: Hashable {
        case page(FeedSource)
        case saveTopItem(FeedSource)
    }

    @Dependency(\.continuousClock) var clock
    @Dependency(\.date.now) var now
    @Dependency(TwitterClient.self) var client
    @Dependency(TweetEngagementSync.self) var engagementSync
    @Dependency(ImageLoader.self) var imageLoader
    @Dependency(\.openURL) var openURL
    @Dependency(TimelineCache.self) var timelineCache

    package init() {}

    package var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .authorTapped(let user):
                return .send(.delegate(.open(.profile(user))))

            case .blockButtonTapped(let user):
                let isBlocking = !user.isBlocking
                state.setBlocking(isBlocking, userID: user.id)
                return .run { _ in
                    try await client.setBlocking(isBlocking, user.id)
                } catch: { _, send in
                    await send(.blockFailed(userID: user.id, isBlocking: !isBlocking))
                }

            case .alert(.presented(.confirmDelete(let tweetID))):
                // Out of the timeline at once; back where it was if Twitter refuses.
                var removed: [Int: FeedItem] = [:]
                for (index, item) in state.items.enumerated().reversed()
                where item.tweets.first?.id == tweetID {
                    removed[index] = item
                    state.items.remove(at: index)
                }
                return .run { _ in
                    try await client.deleteTweet(tweetID)
                } catch: { [removed] error, send in
                    await send(.deleteFailed(removed: removed, message: error.localizedDescription))
                }

            case .alert:
                return .none

            case .deleteButtonTapped(let tweet):
                state.alert = AlertState {
                    TextState("Delete Tweet?")
                } actions: {
                    ButtonState(role: .destructive, action: .confirmDelete(tweetID: tweet.id)) {
                        TextState("Delete")
                    }
                    ButtonState(role: .cancel) {
                        TextState("Cancel")
                    }
                } message: {
                    TextState(
                        "This can't be undone. It will be removed from your profile, the timelines of the accounts "
                            + "that follow you, and search results."
                    )
                }
                return .none

            case .deleteFailed(let removed, let message):
                for (index, item) in removed.sorted(by: { $0.key < $1.key }) where state.items[id: item.id] == nil {
                    state.items.insert(item, at: min(index, state.items.count))
                }
                state.alert = AlertState {
                    TextState("Couldn't delete Tweet")
                } message: {
                    TextState(message)
                }
                return .none

            case .muteButtonTapped(let user):
                let isMuting = !user.isMuting
                state.setMuting(isMuting, userID: user.id)
                return .run { _ in
                    try await client.setMuting(isMuting, user.id)
                } catch: { _, send in
                    await send(.muteFailed(userID: user.id, isMuting: !isMuting))
                }

            case .pollChoiceTapped(let tweetID, let choice):
                guard let poll = state.poll(of: tweetID), poll.canVote(now: now) else { return .none }
                // Counted at once, as Twitter shows the results the moment you vote.
                state.updatePoll(of: tweetID) {
                    $0.choices[choice].count += 1
                    $0.selectedChoiceIndex = choice
                }
                return .run { _ in
                    try await client.vote(tweetID, poll, choice)
                } catch: { _, send in
                    await send(.pollVoteFailed(tweetID: tweetID, choice: choice))
                }

            case .pollVoteFailed(let tweetID, let choice):
                state.updatePoll(of: tweetID) {
                    $0.choices[choice].count -= 1
                    $0.selectedChoiceIndex = nil
                }
                return .none

            case .muteFailed(let userID, let isMuting):
                state.setMuting(isMuting, userID: userID)
                return .none

            case .blockFailed(let userID, let isBlocking):
                state.setBlocking(isBlocking, userID: userID)
                return .none

            case .bookmarkButtonTapped(let tweet):
                let effect = toggle(.bookmark, tweet: tweet, state: &state)
                // Taken out of Bookmarks, it leaves the list, as in Twitter.
                if state.source == .bookmarks, !state.engagements.engagement(for: tweet).bookmark.isOn {
                    state.items.removeAll { $0.tweets.first?.id == tweet.id }
                }
                return effect

            case .topItemRestored:
                state.restoringTopItemID = nil
                return .none

            case .cachedPageLoaded(let page, let topItemID):
                // Shown until the network answers. Paging waits for a live cursor; the cached one only continues
                // past cached posts after fresh ones are merged in above them.
                guard state.items.isEmpty else { return .none }
                state.items = IdentifiedArray(page.items, uniquingIDsWith: { first, _ in first })
                state.cachedBottomCursor = page.bottomCursor
                if let topItemID, topItemID != state.items.first?.id, state.items[id: topItemID] != nil {
                    state.restoringTopItemID = topItemID
                    state.isAtTop = false
                }
                state.$engagements.withLock { $0.refresh(from: page.items.lazy.flatMap(\.tweets)) }
                return .none

            case .delegate:
                return .none

            case .likeButtonTapped(let tweet):
                return toggle(.like, tweet: tweet, state: &state)

            case .likesButtonTapped(let tweet):
                return .send(.delegate(.open(.userList(.likers(tweetID: tweet.id)))))

            case .linkTapped(let url):
                // Posts and profiles open in the app, other pages in a web panel (or Safari's view on one stack),
                // and anything else (mail, phone numbers, other apps) goes to the system.
                switch Route.forLink(url) {
                case .threadID(let id) where state.source == .thread(tweetID: id):
                    return .none
                case .some(let route):
                    return .send(.delegate(.open(route)))
                case nil:
                    return .run { _ in await openURL(url) }
                }

            case .newPostsButtonTapped:
                state.newPostCount = 0
                return .none

            case .pageResponse(.success(let page), let isRefresh) where isRefresh && state.keepsReadingPosition:
                state.isLoading = false
                state.hasLoaded = true
                state.errorMessage = nil
                state.lastRefreshed = now
                let merge = TimelineMerge(
                    fresh: page,
                    onScreen: state.items,
                    existingCursor: state.bottomCursor ?? state.cachedBottomCursor
                )
                state.items = merge.items
                state.bottomCursor = merge.bottomCursor
                state.cachedBottomCursor = nil
                state.newPostCount = state.isAtTop ? 0 : state.newPostCount + merge.newCount
                state.$engagements.withLock { $0.refresh(from: page.items.lazy.flatMap(\.tweets)) }
                let merged = FeedPage(cachedItems: Array(merge.items), bottomCursor: state.bottomCursor)
                return .merge(
                    .run { [source = state.source] _ in
                        await withErrorReporting {
                            try await timelineCache.save(source, merged, true)
                        }
                    },
                    markRead(page, source: state.source)
                )

            case .pageResponse(.success(let page), let isRefresh):
                state.isLoading = false
                state.hasLoaded = true
                state.errorMessage = nil
                if isRefresh {
                    state.lastRefreshed = now
                    state.items = IdentifiedArray(page.items, uniquingIDsWith: { first, _ in first })
                    state.showEarlierConversation(above: page.topCursor)
                } else {
                    for item in page.items where state.items[id: item.id] == nil {
                        state.items.append(item)
                    }
                }
                state.bottomCursor = page.items.isEmpty ? nil : page.bottomCursor
                state.$engagements.withLock { $0.refresh(from: page.items.lazy.flatMap(\.tweets)) }
                return .run { [source = state.source] _ in
                    await withErrorReporting {
                        try await timelineCache.save(source, page, isRefresh)
                    }
                }

            case .pageResponse(.failure(let error), _):
                state.isLoading = false
                state.hasLoaded = true
                state.errorMessage = error.localizedDescription
                return .none

            case .preview:
                // A preview can't be interacted with; nothing it does reaches the columns.
                return .none

            case .previewHidden(let tweetID):
                guard state.preview?.source == .thread(tweetID: tweetID) else { return .none }
                state.preview = nil
                return .none

            case .previewShown(let tweet):
                guard state.preview?.source != .thread(tweetID: tweet.id) else { return .none }
                // Starting from the post itself, as an opened thread does, so it's on screen before the rest loads.
                state.preview = .thread(opening: tweet)
                return .none

            case .quoteButtonTapped(let tweet):
                return .send(.delegate(.compose(Draft(quoting: tweet))))

            case .quotesButtonTapped(let tweet):
                return .send(.delegate(.open(.quotes(tweetID: tweet.id))))

            case .refreshPulled:
                return loadPage(state: &state, isRefresh: true)

            case .reselected:
                state.scrollToTopRequests += 1
                return loadPage(state: &state, isRefresh: true)

            case .tabSelected(let hasNew):
                guard state.hasLoaded, !state.isLoading else { return .none }
                let isStale = state.lastRefreshed.map { now.timeIntervalSince($0) > State.staleInterval } ?? true
                guard hasNew || isStale else { return .none }
                return loadPage(state: &state, isRefresh: true)

            case .replyButtonTapped(let tweet):
                guard tweet.viewerCanReply else { return .none }
                return .send(.delegate(.compose(Draft(replyingTo: tweet))))

            case .repostButtonTapped(let tweet):
                return toggle(.repost, tweet: tweet, state: &state)

            case .repostsButtonTapped(let tweet):
                return .send(.delegate(.open(.userList(.reposters(tweetID: tweet.id)))))

            case .retryButtonTapped:
                return loadPage(state: &state, isRefresh: state.items.isEmpty)

            case .rowAppeared(let id):
                guard let index = state.items.index(id: id) else { return .none }
                let prefetch = prefetchImages(after: index, in: state.items)
                guard
                    index >= state.items.count - 5,
                    state.bottomCursor != nil,
                    !state.isLoading,
                    state.errorMessage == nil
                else { return prefetch }
                return .merge(prefetch, loadPage(state: &state, isRefresh: false))

            case .isAtTopChanged(let isAtTop):
                state.isAtTop = isAtTop
                if isAtTop { state.newPostCount = 0 }
                return .none

            case .scrollStopped(let topItemID):
                state.lastTopItemID = topItemID
                // Remembered once scrolling stops, not on every frame.
                return .run { [source = state.source] _ in
                    try await clock.sleep(for: .seconds(1))
                    await withErrorReporting {
                        try await timelineCache.saveTopItemID(source, topItemID)
                    }
                }
                .cancellable(id: CancelID.saveTopItem(state.source), cancelInFlight: true)

            case .showMoreResponse(let cursor, .success(let page)):
                let id = FeedItem.showMore(cursor).id
                state.loadingShowMoreIDs.remove(id)
                guard let index = state.items.index(id: id) else { return .none }
                state.items.remove(at: index)
                var position = index
                var reachedExisting = false
                for item in page.items {
                    guard state.items[id: item.id] == nil else {
                        reachedExisting = true
                        continue
                    }
                    state.items.insert(item, at: position)
                    position += 1
                }
                // A timeline gap that's still open after this page gets a new gap row where it now starts.
                if cursor.id.hasPrefix(TimelineMerge.gapPrefix), !reachedExisting, let next = page.bottomCursor {
                    state.items.insert(.showMore(TimelineMerge.gap(cursor: next)), at: position)
                }
                // Earlier in a conversation: there may be more above still.
                if cursor.id == State.earlierConversationID {
                    state.showEarlierConversation(above: page.topCursor)
                }
                state.$engagements.withLock { $0.refresh(from: page.items.lazy.flatMap(\.tweets)) }
                return .none

            case .showMoreResponse(let cursor, .failure):
                state.loadingShowMoreIDs.remove(FeedItem.showMore(cursor).id)
                return .none

            case .showMoreButtonTapped(let cursor):
                let id = FeedItem.showMore(cursor).id
                guard state.items[id: id] != nil, state.loadingShowMoreIDs.insert(id).inserted else { return .none }
                return .run { [source = state.source] send in
                    await send(.showMoreResponse(cursor, Result { try await client.feed(source, cursor.cursor) }))
                }

            case .task:
                // A rebuilt view (after folding or unfolding) starts at the top; put the reader back.
                if state.hasLoaded, let lastTopItemID = state.lastTopItemID, state.items[id: lastTopItemID] != nil {
                    state.restoringTopItemID = lastTopItemID
                }
                guard !state.hasLoaded, !state.isLoading else { return .none }
                return loadPage(state: &state, isRefresh: true)

            case .translateButtonTapped(let tweet):
                state.translating = tweet
                return .none

            case .translationDismissed:
                state.translating = nil
                return .none

            case .tweetTapped(let tweet):
                guard state.source != .thread(tweetID: tweet.id) else { return .none }
                return .send(.delegate(.open(.thread(tweet))))
            }
        }
        .ifLet(\.$alert, action: \.alert)
        .ifLet(\.$preview, action: \.preview) {
            FeedFeature()
        }
    }

    /// Notifications on screen are read: Twitter is told, as its own apps do on showing them, which clears the unread
    /// count. Those marked unread stay marked until the next refresh.
    private func markRead(_ page: FeedPage, source: FeedSource) -> EffectOf<Self> {
        guard source == .notifications(.all), let cursor = page.topCursor else { return .none }
        return .run { _ in
            try await client.markNotificationsRead(cursor)
        }
    }

    private func loadPage(state: inout State, isRefresh: Bool) -> EffectOf<Self> {
        state.isLoading = true
        state.errorMessage = nil
        let source = state.source
        let cursor = isRefresh ? nil : state.bottomCursor
        // A first load shows whatever was cached last time while the network catches up.
        let readsCache = isRefresh && state.items.isEmpty
        return .run { send in
            // The request starts first so reading the cache doesn't delay it.
            async let page = Result { try await client.feed(source, cursor) }
            if readsCache, let cached = try? await timelineCache.load(source), !cached.items.isEmpty {
                await Self.typesetText(of: cached.items)
                await send(.cachedPageLoaded(cached, topItemID: try? await timelineCache.topItemID(source)))
            }
            let response = await page
            if case .success(let fresh) = response {
                await Self.typesetText(of: fresh.items)
            }
            await send(.pageResponse(response, isRefresh: isRefresh))
        }
        .cancellable(id: CancelID.page(source), cancelInFlight: true)
    }

    /// Typesets a page's post text off the main actor before the page reaches state, so its rows draw their text
    /// fully on their first frame instead of swapping it in.
    private static func typesetText(of items: [FeedItem]) async {
        await PostTextTypesetter.prewarm(items.flatMap(\.tweets).map(TweetText.timelineInput(for:)))
    }

    /// Warms the image cache for the rows just below one that appeared, so they draw fully on their first frame.
    private func prefetchImages(after index: Int, in items: IdentifiedArrayOf<FeedItem>) -> EffectOf<Self> {
        let upcoming = items.elements.dropFirst(index + 1).prefix(Self.prefetchDistance)
        let requests = upcoming.flatMap { item in
            item.tweets.flatMap { FeedImages.requests(for: $0, scale: Self.prefetchScale) }
        }
        guard !requests.isEmpty else { return .none }
        return .run { _ in imageLoader.prefetch(requests) }
    }

    static let prefetchDistance = 6
    /// Every iPhone that runs this app draws at 3x.
    static let prefetchScale: CGFloat = 3

    private func toggle(_ interaction: Interaction, tweet: Tweet, state: inout State) -> EffectOf<Self> {
        state.$engagements.withLock { $0.toggle(interaction, for: tweet) }
        return .run { _ in await engagementSync.sync(tweet.id, interaction) }
    }
}
