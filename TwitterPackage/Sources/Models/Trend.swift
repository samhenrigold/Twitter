/// Something trending, as Explore lists it.
package struct Trend: Identifiable, Hashable, Codable, Sendable {
    /// What's trending: a hashtag, a phrase, a name.
    package var name: String
    /// What searching it should ask for.
    package var query: String
    /// Where it's trending, or its category ("Trending in Technology", "Sports · Trending").
    package var context: String?
    /// How much it's being talked about ("12.4K posts").
    package var volume: String?

    package var id: String { query }

    package init(name: String, query: String? = nil, context: String? = nil, volume: String? = nil) {
        self.name = name
        self.query = query ?? name
        self.context = context
        self.volume = volume
    }
}
