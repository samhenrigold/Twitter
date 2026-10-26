import Dependencies
import DependenciesMacros
import Foundation
import IssueReporting
import Models
import SQLiteData

/// Twitter's data, kept on disk so timelines and profiles show instantly at launch, in new windows, and when pushed,
/// while the network refreshes them. Twitter stays the source of truth: everything here is disposable.
@DependencyClient
package struct TimelineCache: Sendable {
    /// Forgets everything, e.g. on sign-out.
    package var clear: @Sendable () async throws -> Void
    /// The cached timeline, or `nil` if there isn't one (or it no longer decodes).
    package var load: @Sendable (_ source: FeedSource) async throws -> FeedPage?
    /// Drops timelines nobody has looked at for a while.
    package var prune: @Sendable () async throws -> Void
    /// Records a page: a refresh replaces the timeline, anything else appends to it.
    package var save: @Sendable (_ source: FeedSource, _ page: FeedPage, _ isRefresh: Bool) async throws -> Void
    package var saveTopItemID: @Sendable (_ source: FeedSource, _ itemID: String) async throws -> Void
    package var saveUser: @Sendable (_ user: User) async throws -> Void
    /// Where the reader left off in a timeline: the item that was at the top of the screen.
    package var topItemID: @Sendable (_ source: FeedSource) async throws -> String?
    package var user: @Sendable (_ screenName: String) async throws -> User?
}

extension TimelineCache: TestDependencyKey {
    /// The cache is invisible to features' logic, so tests get an empty one; tests about caching override it.
    package static var testValue: TimelineCache { previewValue }

    /// Previews and `--mock-twitter` start empty and remember nothing.
    package static let previewValue = TimelineCache(
        clear: {},
        load: { _ in nil },
        prune: {},
        save: { _, _, _ in },
        saveTopItemID: { _, _ in },
        saveUser: { _ in },
        topItemID: { _ in nil },
        user: { _ in nil }
    )
}

extension TimelineCache: DependencyKey {
    package static var liveValue: TimelineCache {
        @Dependency(\.defaultDatabase) var database
        @Dependency(\.date.now) var now
        return TimelineCache(
            clear: {
                try await database.write { db in
                    try TimelineRecord.delete().execute(db)
                    try UserRecord.delete().execute(db)
                }
            },
            // JSON coding of whole pages is heavy, so the coding closures run off the caller's actor.
            load: { @concurrent source in
                guard let key = source.cacheKey else { return nil }
                let (timeline, entries) = try await database.read { db in
                    (
                        try TimelineRecord.find(key).fetchOne(db),
                        try TimelineEntryRecord
                            .where { $0.timelineID.eq(key) }
                            .order(by: \.position)
                            .fetchAll(db)
                    )
                }
                guard let timeline, !entries.isEmpty else { return nil }
                let decoder = JSONDecoder()
                var items: [FeedItem] = []
                for entry in entries {
                    guard let item = try? decoder.decode(FeedItem.self, from: entry.payload) else { return nil }
                    items.append(item)
                }
                return FeedPage(cachedItems: items, bottomCursor: timeline.bottomCursor)
            },
            prune: {
                let cutoff = now.addingTimeInterval(-Self.retention)
                try await database.write { db in
                    try TimelineRecord.where { $0.refreshedAt.lt(cutoff) }.delete().execute(db)
                    try UserRecord.where { $0.fetchedAt.lt(cutoff) }.delete().execute(db)
                }
            },
            save: { @concurrent source, page, isRefresh in
                guard let key = source.cacheKey else { return }
                let encoder = JSONEncoder()
                let payloads = page.items.compactMap { item in
                    (try? encoder.encode(item)).map { (item.id, $0) }
                }
                let refreshedAt = now
                try await database.write { db in
                    if isRefresh {
                        try TimelineEntryRecord.where { $0.timelineID.eq(key) }.delete().execute(db)
                    }
                    // Keeps the reader's top item, which pages don't know about.
                    try TimelineRecord.insert {
                        TimelineRecord(id: key, bottomCursor: page.bottomCursor, refreshedAt: refreshedAt)
                    } onConflict: {
                        $0.id
                    } doUpdate: { timeline, excluded in
                        timeline.bottomCursor = excluded.bottomCursor
                        timeline.refreshedAt = excluded.refreshedAt
                    }
                    .execute(db)
                    let start = try TimelineEntryRecord.where { $0.timelineID.eq(key) }.fetchCount(db)
                    let records = payloads.enumerated()
                        .filter { start + $0.offset < Self.maximumEntries }
                        .map { offset, element in
                            TimelineEntryRecord(
                                id: "\(key)|\(element.0)",
                                timelineID: key,
                                position: start + offset,
                                payload: element.1
                            )
                        }
                    guard !records.isEmpty else { return }
                    try TimelineEntryRecord.insert {
                        records
                    } onConflict: {
                        $0.id
                    } doUpdate: { entry, excluded in
                        entry.payload = excluded.payload
                    }
                    .execute(db)
                }
            },
            saveTopItemID: { source, itemID in
                guard let key = source.cacheKey else { return }
                try await database.write { db in
                    try TimelineRecord.find(key).update { $0.topItemID = #bind(itemID) }.execute(db)
                }
            },
            saveUser: { @concurrent user in
                let payload = try JSONEncoder().encode(user)
                let fetchedAt = now
                try await database.write { db in
                    try UserRecord.upsert {
                        UserRecord(id: user.screenName.lowercased(), payload: payload, fetchedAt: fetchedAt)
                    }
                    .execute(db)
                }
            },
            topItemID: { source in
                guard let key = source.cacheKey else { return nil }
                return try await database.read { db in
                    try TimelineRecord.find(key).fetchOne(db)?.topItemID
                }
            },
            user: { @concurrent screenName in
                let record = try await database.read { db in
                    try UserRecord.find(screenName.lowercased()).fetchOne(db)
                }
                return record.flatMap { try? JSONDecoder().decode(User.self, from: $0.payload) }
            }
        )
    }

    /// Enough to fill a few screens; paging past it goes to the network anyway.
    static let maximumEntries = 200
    static let retention: TimeInterval = 7 * 24 * 60 * 60
}

extension FeedSource {
    /// A stable storage key, or `nil` for timelines not worth keeping (searches change with every query).
    package var cacheKey: String? {
        switch self {
        case .bookmarks: "bookmarks"
        case .home(let following): following ? "home.following" : "home.forYou"
        case .notifications(let mentionsOnly): mentionsOnly ? "notifications.mentions" : "notifications.all"
        case .search, .searchMedia: nil
        case .thread(let tweetID): "thread.\(tweetID)"
        case .userLikes(let userID): "user.\(userID).likes"
        case .userMedia(let userID): "user.\(userID).media"
        case .userPosts(let userID): "user.\(userID).posts"
        case .userReplies(let userID): "user.\(userID).replies"
        }
    }
}
