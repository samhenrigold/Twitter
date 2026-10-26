import ComposableArchitecture
import Foundation
import TwitterClient
import TwitterDatabase
import TwitterUI

/// Prepares app-wide dependencies. Call once, from the app's `init`, before any scene builds a store.
public func bootstrapTwitter() {
    // Registering the Chirp faces is file I/O that nothing needs until the first text is laid out, so it overlaps
    // opening the database. The first font lookup waits for it if it's still going.
    Task.detached(priority: .high) { TwitterFont.register() }
    prepareDependencies { dependencies in
        withErrorReporting {
            try dependencies.bootstrapDatabase()
        }
        dependencies.useMockTwitterIfRequested()
    }
    // Start restoring the session before any scene exists: it reads the Keychain and opens the connection to x.com
    // while SwiftUI builds the first frame. The main window's own restore joins this one.
    @Dependency(TwitterClient.self) var client
    Task.detached(priority: .userInitiated) {
        _ = try? await client.restoreSession()
    }
}

extension DependencyValues {
    /// `--mock-twitter` (debug builds) swaps in canned data and a cache that remembers nothing, for UI work without
    /// signing in.
    mutating func useMockTwitterIfRequested() {
        #if DEBUG
            guard ProcessInfo.processInfo.arguments.contains("--mock-twitter") else { return }
            self[TwitterClient.self] = .previewValue
            self[TimelineCache.self] = .previewValue
            // The mock account mustn't be remembered as the real one for the next launch. One shared in-memory store,
            // so every window still sees the same viewer.
            defaultFileStorage = mockFileStorage
        #endif
    }
}

#if DEBUG
    private let mockFileStorage = FileStorage.inMemory
#endif
