import Synchronization

/// Persists session cookies in call order. Each session gets a generation; a superseded or signed-out session's
/// rotations are dropped, so a stale session can never write its cookies back over a newer one.
final class CookieVault: Sendable {
    private let generation = Mutex(0)

    /// Starts a new generation (optionally saving its initial cookies) and returns it.
    func begin(saving cookies: [String: String]?) -> Int {
        generation.withLock { generation in
            generation += 1
            if let cookies { Keychain.saveCookies(cookies) }
            return generation
        }
    }

    func save(_ cookies: [String: String], generation: Int) {
        self.generation.withLock { current in
            guard current == generation else { return }
            Keychain.saveCookies(cookies)
        }
    }

    func clear() {
        generation.withLock { generation in
            generation += 1
            Keychain.deleteCookies()
        }
    }
}
