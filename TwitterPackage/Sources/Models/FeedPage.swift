package struct FeedPage: Sendable {
    package var items: [FeedItem]
    package var bottomCursor: String?
    package var topCursor: String?
}
