import Dependencies
import Models
import Synchronization
import TwitterClient
import TwitterDatabase

/// Profiles looked up by handle for previews. Remembered in memory for the session; the database's user cache and
/// the network fill it.
package enum ProfileLookup {
    private static let memory = Mutex<[String: User]>([:])

    package static func remembered(_ screenName: String) -> User? {
        memory.withLock { $0[screenName.lowercased()] }
    }

    package static func remember(_ user: User) {
        memory.withLock { memory in
            if memory.count > 500 { memory.removeAll(keepingCapacity: true) }
            memory[user.screenName.lowercased()] = user
        }
    }

    /// From memory or the on-disk cache, without touching the network.
    @concurrent package static func stored(_ screenName: String) async -> User? {
        if let user = remembered(screenName) { return user }
        @Dependency(TimelineCache.self) var cache
        guard let user = try? await cache.user(screenName) else { return nil }
        remember(user)
        return user
    }

    /// From the network, saved for next time.
    @concurrent package static func fetch(_ screenName: String) async -> User? {
        @Dependency(TwitterClient.self) var client
        @Dependency(TimelineCache.self) var cache
        guard let user = try? await client.user(screenName) else { return nil }
        remember(user)
        try? await cache.saveUser(user)
        return user
    }
}
