import Models

actor SessionStore {
    private var current: TwitterWebSession?
    private let vault = CookieVault()
    private var restoring: Task<User?, any Error>?
    private var viewer: User?

    /// Every window restores on launch; concurrent calls share one round trip and later calls reuse its result.
    func restore() async throws -> User? {
        if current != nil, let viewer { return viewer }
        if let restoring { return try await restoring.value }
        let task = Task { try await performRestore() }
        restoring = task
        defer { restoring = nil }
        return try await task.value
    }

    func signIn(cookies: [String: String]) async throws -> User {
        let session = makeSession(cookies: cookies, saving: true)
        let viewer = try await session.viewer()
        // The actor is reentrant: a sign-out or newer sign-in during `viewer()` supersedes this one.
        guard current === session else { throw TwitterError.notSignedIn }
        self.viewer = viewer
        return viewer
    }

    func signOut() {
        current = nil
        viewer = nil
        vault.clear()
    }

    /// The signed-in session, picked up from the Keychain if this launch hasn't made one yet. Requests don't wait for
    /// `restore` to validate it: the app shows a remembered account at launch, and its timelines load in parallel.
    func session() throws -> TwitterWebSession {
        if let current { return current }
        guard let cookies = Keychain.loadCookies() else { throw TwitterError.notSignedIn }
        return makeSession(cookies: cookies, saving: false)
    }

    private func performRestore() async throws -> User? {
        guard let session = try? session() else { return nil }
        do {
            let viewer = try await session.viewer()
            // The actor is reentrant: a sign-in or sign-out during `viewer()` supersedes this restore.
            guard current === session else { return self.viewer }
            self.viewer = viewer
            return viewer
        } catch TwitterError.unauthorized {
            guard current === session else { return self.viewer }
            signOut()
            return nil
        }
    }

    private func makeSession(cookies: [String: String], saving: Bool) -> TwitterWebSession {
        let generation = vault.begin(saving: saving ? cookies : nil)
        let session = TwitterWebSession(cookies: cookies) { [vault] cookies in
            vault.save(cookies, generation: generation)
        }
        current = session
        return session
    }
}
