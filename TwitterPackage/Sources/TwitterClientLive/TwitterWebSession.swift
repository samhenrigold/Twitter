import Foundation
import Models
import os

/// Talks to Twitter's web GraphQL API with the cookies from the in-app sign-in.
actor TwitterWebSession {
    static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
    /// The public bearer token embedded in x.com's web client for every visitor (not a secret).
    static let webBearer =
        "AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA"
    /// How long a catalog is used before it's rebuilt in the background.
    private static let catalogLifetime: TimeInterval = 6 * 3600
    /// How long a saved catalog is used at all. Query IDs rotate every few weeks, and a rotated one forces a rebuild.
    private static let catalogMaximumAge: TimeInterval = 7 * 24 * 3600

    private let log = Logger(subsystem: "gold.samhenri.Twitter", category: "api")
    private let session: URLSession
    private var cookies: [String: String]
    private let onCookiesChanged: @Sendable ([String: String]) -> Void
    private var catalog: CatalogSnapshot?
    private var catalogTask: Task<CatalogSnapshot, Never>?
    /// Debug-only logged-out mode used to preview the UI with public data.
    private var guestToken: String?

    func activateGuestSession() async throws {
        var request = URLRequest(url: URL(string: "https://api.x.com/1.1/guest/activate.json")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(Self.webBearer)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await session.data(for: request)
        guestToken = (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["guest_token"] as? String
    }

    init(cookies: [String: String], onCookiesChanged: @escaping @Sendable ([String: String]) -> Void) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 30
        session = URLSession(configuration: configuration)
        self.cookies = cookies
        self.onCookiesChanged = onCookiesChanged
    }

    // MARK: - Catalog

    private static var catalogFile: URL {
        let dir = URL.applicationSupportDirectory.appending(path: "Twitter", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "web-client-catalog.json")
    }

    /// The catalog to make requests with. Building one downloads and scans megabytes of x.com's JavaScript, so a
    /// saved catalog is used for days, stale-while-revalidate: past `catalogLifetime` it's rebuilt in the background
    /// while requests keep going with it, and `graphQLData` forces a rebuild if Twitter has rotated an ID meanwhile.
    /// Only a launch with nothing usable on disk waits for a build.
    func currentCatalog(forceRefresh: Bool = false) async throws -> CatalogSnapshot {
        if !forceRefresh {
            if catalog == nil { catalog = Self.savedCatalog() }
            if let catalog {
                let age = Date.now.timeIntervalSince(catalog.createdAt)
                if age < Self.catalogMaximumAge {
                    if age >= Self.catalogLifetime { _ = catalogBuild() }
                    return catalog
                }
            }
        }
        return await catalogBuild().value
    }

    /// Joins the build in flight, or starts one.
    private func catalogBuild() -> Task<CatalogSnapshot, Never> {
        if let catalogTask { return catalogTask }
        let task = Task { await buildCatalog() }
        catalogTask = task
        return task
    }

    private func buildCatalog() async -> CatalogSnapshot {
        defer { catalogTask = nil }
        do {
            let snapshot = try await CatalogBuilder.build { url in try await self.fetchText(url) }
            catalog = snapshot
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: Self.catalogFile, options: .atomic)
            }
            log.notice(
                "Catalog built: \(snapshot.operations.count) operations, transaction id \(snapshot.transactionAnimationKey == nil ? "unavailable" : "ready", privacy: .public)"
            )
            return snapshot
        } catch {
            log.error("Catalog build failed: \(error.localizedDescription, privacy: .public)")
            if let catalog { return catalog }
            let fallback = CatalogSnapshot.fallback
            catalog = fallback
            return fallback
        }
    }

    private static func savedCatalog() -> CatalogSnapshot? {
        guard let data = try? Data(contentsOf: catalogFile) else { return nil }
        return try? JSONDecoder().decode(CatalogSnapshot.self, from: data)
    }

    private func fetchText(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,*/*", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        if url.host() == "x.com" { request.setValue(cookieHeader, forHTTPHeaderField: "Cookie") }
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse {
            if url.host() == "x.com" { absorbCookies(from: http) }
            guard (200..<300).contains(http.statusCode) else {
                throw TwitterError.http(http.statusCode, url.absoluteString)
            }
        }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Requests

    private var cookieHeader: String {
        cookies.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "; ")
    }

    private func absorbCookies(from response: HTTPURLResponse) {
        guard let fields = response.allHeaderFields as? [String: String], let url = response.url else { return }
        let updated = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
        guard !updated.isEmpty else { return }
        var changed = false
        for cookie in updated where cookie.domain.hasSuffix("x.com") {
            if let expires = cookie.expiresDate, expires < .now {
                changed = cookies.removeValue(forKey: cookie.name) != nil || changed
            } else if cookies[cookie.name] != cookie.value {
                cookies[cookie.name] = cookie.value
                changed = true
            }
        }
        if changed { onCookiesChanged(cookies) }
    }

    private func apiRequest(
        url: URL, method: String, body: Data?, transactionPath: String, generator: TransactionIDGenerator?
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer \(Self.webBearer)", forHTTPHeaderField: "Authorization")
        request.setValue(cookies["ct0"] ?? "", forHTTPHeaderField: "x-csrf-token")
        request.setValue("OAuth2Session", forHTTPHeaderField: "x-twitter-auth-type")
        request.setValue("yes", forHTTPHeaderField: "x-twitter-active-user")
        request.setValue("en", forHTTPHeaderField: "x-twitter-client-language")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("https://x.com", forHTTPHeaderField: "Origin")
        request.setValue("https://x.com/", forHTTPHeaderField: "Referer")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        if let guestToken {
            request.setValue(guestToken, forHTTPHeaderField: "x-guest-token")
            request.setValue(nil, forHTTPHeaderField: "x-twitter-auth-type")
            request.setValue(nil, forHTTPHeaderField: "x-csrf-token")
        }
        if let generator {
            request.setValue(
                generator.generate(method: method, path: transactionPath), forHTTPHeaderField: "x-client-transaction-id"
            )
        }
        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Any, Int) {
        let (data, http) = try await send(request)
        if (200..<300).contains(http.statusCode) {
            return ((try? JSONSerialization.jsonObject(with: data)) ?? [:], http.statusCode)
        }
        return (try Self.failure(data, http), http.statusCode)
    }

    /// Sends a request and absorbs any rotated cookies, leaving the body undecoded.
    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TwitterError.http(0, "No response") }
        absorbCookies(from: http)
        return (data, http)
    }

    /// Inspects a non-2xx response: throws for auth and rate-limit failures, otherwise returns the error JSON.
    private static func failure(_ data: Data, _ http: HTTPURLResponse) throws -> Any {
        let json = try? JSONSerialization.jsonObject(with: data)
        switch http.statusCode {
        case 401:
            throw TwitterError.unauthorized
        case 429:
            let reset = (http.value(forHTTPHeaderField: "x-rate-limit-reset")).flatMap(Double.init).map(
                Date.init(timeIntervalSince1970:))
            throw TwitterError.rateLimited(resetAt: reset)
        default:
            let message = Self.errorMessages(json).first ?? String(decoding: data.prefix(300), as: UTF8.self)
            if http.statusCode == 403,
                message.localizedCaseInsensitiveContains("authenticat") || message.contains("(32)")
            {
                throw TwitterError.unauthorized
            }
            return json ?? ["__status": http.statusCode, "__message": message]
        }
    }

    private static func errorMessages(_ json: Any?) -> [String] {
        ((json as? [String: Any])?["errors"] as? [[String: Any]] ?? []).compactMap { $0["message"] as? String }
    }

    /// Parses a 2xx GraphQL body, throwing when it carries errors and no data.
    private static func graphQLJSON(_ data: Data) throws -> Any {
        let json = (try? JSONSerialization.jsonObject(with: data)) ?? [:]
        if (json as? [String: Any])?["data"] == nil, let message = errorMessages(json).first {
            throw TwitterError.api(message)
        }
        return json
    }

    /// Parses a timeline body off the session actor, so large pages don't hold up other requests.
    @concurrent private static func decodePage(_ data: Data) async throws -> FeedPage {
        TimelineParser.page(from: try graphQLJSON(data))
    }

    /// Runs a GraphQL operation and returns its parsed JSON.
    func graphQL(_ operation: String, variables: [String: JSONValue], usePOST: Bool? = nil) async throws -> Any {
        try Self.graphQLJSON(try await graphQLData(operation, variables: variables, usePOST: usePOST))
    }

    /// Runs a GraphQL timeline operation, decoding the page off the session actor.
    func graphQLPage(_ operation: String, variables: [String: JSONValue], usePOST: Bool? = nil) async throws
        -> FeedPage
    {
        try await Self.decodePage(try await graphQLData(operation, variables: variables, usePOST: usePOST))
    }

    /// Runs a GraphQL operation with variables, retrying once with a fresh catalog when Twitter has
    /// rotated query IDs (404) or added required feature flags (400). Returns the undecoded 2xx body.
    private func graphQLData(_ operation: String, variables: [String: JSONValue], usePOST: Bool?) async throws
        -> Data
    {
        var extraFeatures: [String: JSONValue] = [:]
        var refreshed = false
        var forceRefresh = false
        for _ in 0..<3 {
            let catalog = try await currentCatalog(forceRefresh: forceRefresh)
            forceRefresh = false
            guard let op = catalog.operations[operation] else {
                if !refreshed {
                    refreshed = true
                    forceRefresh = true
                    continue
                }
                throw TwitterError.missingOperation(operation)
            }

            var features: [String: JSONValue] = [:]
            for name in op.featureSwitches { features[name] = catalog.featureValues[name] ?? false }
            features.merge(extraFeatures) { $1 }
            var toggles: [String: JSONValue] = [:]
            for name in op.fieldToggles { toggles[name] = false }

            let path = "/i/api/graphql/\(op.queryId)/\(operation)"
            let isPOST = usePOST ?? (op.type == "mutation")
            let request: URLRequest
            if isPOST {
                var body: [String: JSONValue] = ["variables": .object(variables), "queryId": .string(op.queryId)]
                if !features.isEmpty { body["features"] = .object(features) }
                if !toggles.isEmpty { body["fieldToggles"] = .object(toggles) }
                request = apiRequest(
                    url: URL(string: "https://x.com\(path)")!, method: "POST",
                    body: Data(JSONValue.object(body).encodedString().utf8),
                    transactionPath: path, generator: catalog.transactionGenerator)
            } else {
                var components = URLComponents(string: "https://x.com\(path)")!
                var items = [URLQueryItem(name: "variables", value: JSONValue.object(variables).encodedString())]
                if !features.isEmpty {
                    items.append(URLQueryItem(name: "features", value: JSONValue.object(features).encodedString()))
                }
                if !toggles.isEmpty {
                    items.append(URLQueryItem(name: "fieldToggles", value: JSONValue.object(toggles).encodedString()))
                }
                components.queryItems = items
                components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(
                    of: "+", with: "%2B")
                request = apiRequest(
                    url: components.url!, method: "GET", body: nil,
                    transactionPath: path, generator: catalog.transactionGenerator)
            }

            let started = Date.now
            let (data, http) = try await send(request)
            let status = http.statusCode
            log.notice(
                "\(operation, privacy: .public) → HTTP \(status) in \(Int(Date.now.timeIntervalSince(started) * 1000))ms"
            )
            if (200..<300).contains(status) { return data }

            let json = try Self.failure(data, http)
            let message = Self.errorMessages(json).first ?? ((json as? [String: Any])?["__message"] as? String ?? "")
            log.error("\(operation, privacy: .public) failed: HTTP \(status) \(message, privacy: .public)")
            if status == 400, let range = message.range(of: "cannot be null:") {
                for name in message[range.upperBound...].split(separator: ",") {
                    extraFeatures[name.trimmingCharacters(in: .whitespaces)] = false
                }
                continue
            }
            if status == 404 || status == 400, !refreshed {
                refreshed = true
                forceRefresh = true
                continue
            }
            throw TwitterError.http(status, message)
        }
        throw TwitterError.api("\(operation) failed after retries")
    }

    func rest(_ path: String) async throws -> Any {
        let request = apiRequest(
            url: URL(string: "https://x.com\(path)")!, method: "GET", body: nil,
            transactionPath: URL(string: "https://x.com\(path)")!.path(),
            generator: catalog?.transactionGenerator)
        let (json, status) = try await perform(request)
        guard (200..<300).contains(status) else {
            throw TwitterError.http(status, (json as? [String: Any])?["__message"] as? String ?? "")
        }
        return json
    }

    /// v1.1 REST POST with a form body (follow, mute, block use these on x.com).
    func restPost(_ path: String, form: [String: String]) async throws -> Any {
        var components = URLComponents()
        components.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        let url = URL(string: "https://x.com\(path)")!
        var request = apiRequest(
            url: url, method: "POST", body: Data((components.percentEncodedQuery ?? "").utf8),
            transactionPath: url.path(), generator: catalog?.transactionGenerator)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let (json, status) = try await perform(request)
        guard (200..<300).contains(status) else {
            throw TwitterError.http(
                status, Self.errorMessages(json).first ?? ((json as? [String: Any])?["__message"] as? String ?? ""))
        }
        return json
    }

    // MARK: - Endpoints

    func viewer() async throws -> User {
        _ = try await currentCatalog()
        let settings = try await rest("/i/api/1.1/account/settings.json") as? [String: Any]
        guard let screenName = settings?["screen_name"] as? String else { throw TwitterError.unauthorized }
        return try await user(screenName: screenName)
    }

    func user(screenName: String) async throws -> User {
        let json = try await graphQL(
            "UserByScreenName",
            variables: [
                "screen_name": .string(screenName), "withGrokTranslatedBio": false
            ])
        guard
            let result = (((json as? [String: Any])?["data"] as? [String: Any])?["user"] as? [String: Any])?["result"]
                as? [String: Any],
            let user = TimelineParser.user(from: result)
        else { throw TwitterError.api("Couldn't find @\(screenName).") }
        return user
    }

    func homeTimeline(following: Bool, cursor: String?) async throws -> FeedPage {
        var variables: [String: JSONValue] = [
            "count": 20, "includePromotedContent": false, "latestControlAvailable": true,
            "requestContext": cursor == nil ? "launch" : "ptr", "withCommunity": true
        ]
        if let cursor { variables["cursor"] = .string(cursor) }
        if !following { variables["seenTweetIds"] = [] }
        return try await graphQLPage(
            following ? "HomeLatestTimeline" : "HomeTimeline", variables: variables, usePOST: true)
    }

    func tweetDetail(id: String, cursor: String?) async throws -> FeedPage {
        var variables: [String: JSONValue] = [
            "focalTweetId": .string(id), "with_rux_injections": false, "rankingMode": "Relevance",
            "includePromotedContent": false, "withCommunity": true, "withQuickPromoteEligibilityTweetFields": true,
            "withBirdwatchNotes": true, "withVoice": true
        ]
        if let cursor {
            variables["cursor"] = .string(cursor)
            variables["referrer"] = "tweet"
        }
        return try await graphQLPage("TweetDetail", variables: variables)
    }

    func userTweets(userID: String, cursor: String?) async throws -> FeedPage {
        var variables: [String: JSONValue] = [
            "userId": .string(userID), "count": 20, "includePromotedContent": false,
            "withQuickPromoteEligibilityTweetFields": true, "withVoice": true
        ]
        if let cursor { variables["cursor"] = .string(cursor) }
        return try await graphQLPage("UserTweets", variables: variables)
    }

    func userReplies(userID: String, cursor: String?) async throws -> FeedPage {
        var variables: [String: JSONValue] = [
            "userId": .string(userID), "count": 20, "includePromotedContent": false, "withCommunity": true,
            "withVoice": true
        ]
        if let cursor { variables["cursor"] = .string(cursor) }
        return try await graphQLPage("UserTweetsAndReplies", variables: variables)
    }

    func userMedia(userID: String, cursor: String?) async throws -> FeedPage {
        var variables: [String: JSONValue] = [
            "userId": .string(userID), "count": 20, "includePromotedContent": false,
            "withClientEventToken": false, "withBirdwatchNotes": false, "withVoice": true
        ]
        if let cursor { variables["cursor"] = .string(cursor) }
        return try await graphQLPage("UserMedia", variables: variables)
    }

    func likes(userID: String, cursor: String?) async throws -> FeedPage {
        var variables: [String: JSONValue] = [
            "userId": .string(userID), "count": 20, "includePromotedContent": false,
            "withClientEventToken": false, "withBirdwatchNotes": false, "withVoice": true
        ]
        if let cursor { variables["cursor"] = .string(cursor) }
        return try await graphQLPage("Likes", variables: variables)
    }

    func deleteTweet(id: String) async throws {
        _ = try await graphQL("DeleteTweet", variables: ["tweet_id": .string(id), "dark_request": false])
    }

    func setPinned(_ pinned: Bool, tweetID: String) async throws {
        _ = try await graphQL(pinned ? "PinTweet" : "UnpinTweet", variables: ["tweet_id": .string(tweetID)])
    }

    func setFollowing(_ follow: Bool, userID: String) async throws {
        _ = try await restPost(
            follow ? "/i/api/1.1/friendships/create.json" : "/i/api/1.1/friendships/destroy.json",
            form: ["user_id": userID])
    }

    func setMuted(_ muted: Bool, userID: String) async throws {
        _ = try await restPost(
            muted ? "/i/api/1.1/mutes/users/create.json" : "/i/api/1.1/mutes/users/destroy.json",
            form: ["user_id": userID])
    }

    func setBlocked(_ blocked: Bool, userID: String) async throws {
        _ = try await restPost(
            blocked ? "/i/api/1.1/blocks/create.json" : "/i/api/1.1/blocks/destroy.json", form: ["user_id": userID])
    }

    /// `product` is the web client's tab: Top, Latest or Media (People lists accounts; see `users(_:cursor:)`).
    func search(_ query: String, product: String, cursor: String?) async throws -> FeedPage {
        var variables: [String: JSONValue] = [
            "rawQuery": .string(query), "count": 20, "querySource": "typed_query", "product": .string(product),
            "withGrokTranslatedBio": false
        ]
        if let cursor { variables["cursor"] = .string(cursor) }
        return try await graphQLPage("SearchTimeline", variables: variables)
    }

    func listTimeline(id: String, cursor: String?) async throws -> FeedPage {
        var variables: [String: JSONValue] = ["listId": .string(id), "count": 20]
        if let cursor { variables["cursor"] = .string(cursor) }
        return try await graphQLPage("ListLatestTweetsTimeline", variables: variables)
    }

    /// The Lists someone made or follows, as their profile's Lists page shows them.
    func lists(userID: String, cursor: String?) async throws -> ListPage {
        var variables: [String: JSONValue] = ["userId": .string(userID), "count": 100]
        if let cursor { variables["cursor"] = .string(cursor) }
        return TimelineParser.listPage(from: try await graphQL("CombinedLists", variables: variables))
    }

    /// What's trending, from the web client's Explore page.
    func trends() async throws -> [Trend] {
        TimelineParser.trends(from: try await graphQL("ExplorePage", variables: [:]))
    }

    func bookmarks(cursor: String?) async throws -> FeedPage {
        var variables: [String: JSONValue] = ["count": 20, "includePromotedContent": false]
        if let cursor { variables["cursor"] = .string(cursor) }
        return try await graphQLPage("Bookmarks", variables: variables)
    }

    func notifications(type: String = "All", cursor: String?) async throws -> FeedPage {
        var variables: [String: JSONValue] = ["timeline_type": .string(type), "count": 20]
        if let cursor { variables["cursor"] = .string(cursor) }
        return try await graphQLPage("NotificationsTimeline", variables: variables)
    }

    func setLiked(_ liked: Bool, tweetID: String) async throws {
        _ = try await graphQL(liked ? "FavoriteTweet" : "UnfavoriteTweet", variables: ["tweet_id": .string(tweetID)])
    }

    func setReposted(_ reposted: Bool, tweetID: String) async throws {
        if reposted {
            _ = try await graphQL("CreateRetweet", variables: ["tweet_id": .string(tweetID), "dark_request": false])
        } else {
            _ = try await graphQL(
                "DeleteRetweet", variables: ["source_tweet_id": .string(tweetID), "dark_request": false])
        }
    }

    func setBookmarked(_ bookmarked: Bool, tweetID: String) async throws {
        _ = try await graphQL(
            bookmarked ? "CreateBookmark" : "DeleteBookmark", variables: ["tweet_id": .string(tweetID)])
    }

    // MARK: - Media upload

    enum MediaCategory: String, Sendable {
        case image = "tweet_image"
        case gif = "tweet_gif"
        case video = "tweet_video"
    }

    /// Chunked upload to upload.x.com (INIT → APPEND… → FINALIZE → STATUS), the flow x.com uses.

    func uploadMedia(
        _ data: Data, mimeType: String, category: MediaCategory,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> String {
        let base = "https://upload.x.com/i/media/upload.json"
        func url(_ items: [String: String]) -> URL {
            var components = URLComponents(string: base)!
            components.queryItems = items.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            return components.url!
        }

        let initJSON = try await uploadRequest(
            url([
                "command": "INIT", "total_bytes": "\(data.count)",
                "media_type": mimeType, "media_category": category.rawValue
            ]))
        guard let mediaID = (initJSON["media_id_string"] as? String) ?? (initJSON["media_id"] as? Int).map(String.init)
        else {
            throw TwitterError.api("Twitter didn't accept the upload.")
        }

        let chunkSize = 4 << 20
        var offset = 0
        var segment = 0
        while offset < data.count {
            let chunk = data[offset..<min(offset + chunkSize, data.count)]
            let boundary = "----Twitter\(UUID().uuidString)"
            var body = Data()
            body.append(
                "--\(boundary)\r\nContent-Disposition: form-data; name=\"media\"; filename=\"blob\"\r\nContent-Type: application/octet-stream\r\n\r\n"
                    .data(using: .utf8)!)
            body.append(chunk)
            body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
            _ = try await uploadRequest(
                url(["command": "APPEND", "media_id": mediaID, "segment_index": "\(segment)"]),
                body: body, contentType: "multipart/form-data; boundary=\(boundary)")
            offset += chunk.count
            segment += 1
            progress?(Double(offset) / Double(data.count) * (category == .image ? 1 : 0.8))
        }

        var info =
            try await uploadRequest(url(["command": "FINALIZE", "media_id": mediaID]))["processing_info"]
            as? [String: Any]
        // Video and GIF are transcoded server-side; wait until Twitter reports success.
        while let state = info?["state"] as? String, state == "pending" || state == "in_progress" {
            if let percent = info?["progress_percent"] as? Int { progress?(0.8 + Double(percent) / 500) }
            let wait = min(max(info?["check_after_secs"] as? Int ?? 1, 1), 10)
            try await Task.sleep(for: .seconds(wait))
            info =
                try await uploadRequest(url(["command": "STATUS", "media_id": mediaID]), method: "GET")[
                    "processing_info"] as? [String: Any]
        }
        if let state = info?["state"] as? String, state == "failed" {
            let message = (info?["error"] as? [String: Any])?["message"] as? String
            throw TwitterError.api(message ?? "Twitter couldn't process this media.")
        }
        progress?(1)
        return mediaID
    }

    private func uploadRequest(_ url: URL, method: String = "POST", body: Data? = nil, contentType: String? = nil)
        async throws -> [String: Any]
    {
        var request = apiRequest(url: url, method: method, body: body, transactionPath: url.path(), generator: nil)
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        if body == nil { request.setValue(nil, forHTTPHeaderField: "Content-Type") }
        request.timeoutInterval = 120
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TwitterError.http(0, "No response") }
        absorbCookies(from: http)
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw TwitterError.unauthorized }
            let json = try? JSONSerialization.jsonObject(with: data)
            throw TwitterError.http(
                http.statusCode, Self.errorMessages(json).first ?? String(decoding: data.prefix(200), as: UTF8.self))
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// Creates a post and returns its ID (needed to chain thread replies).
    @discardableResult
    func post(text: String, replyTo: String?, mediaIDs: [String] = [], quoteURL: URL? = nil) async throws -> String {
        let entities: [JSONValue] = mediaIDs.map { ["media_id": .string($0), "tagged_users": []] }
        var variables: [String: JSONValue] = [
            "tweet_text": .string(text), "dark_request": false,
            "media": ["media_entities": .array(entities), "possibly_sensitive": false],
            "semantic_annotation_ids": [], "disallowed_reply_options": nil
        ]
        if let replyTo { variables["reply"] = ["in_reply_to_tweet_id": .string(replyTo), "exclude_reply_user_ids": []] }
        if let quoteURL { variables["attachment_url"] = .string(quoteURL.absoluteString) }
        let json = try await graphQL("CreateTweet", variables: variables)
        let result =
            ((((json as? [String: Any])?["data"] as? [String: Any])?["create_tweet"] as? [String: Any])?[
                "tweet_results"] as? [String: Any])?["result"] as? [String: Any]
        let unwrapped = result.flatMap(TimelineParser.unwrapTweet)
        guard
            let id = (unwrapped?["rest_id"] as? String)
                ?? ((unwrapped?["legacy"] as? [String: Any])?["id_str"] as? String)
        else {
            throw TwitterError.api("Twitter didn't confirm the Tweet.")
        }
        return id
    }
}
