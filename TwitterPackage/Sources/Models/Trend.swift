import Foundation

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

extension TimelineParser {
    /// Twitter says "12.4K posts"; the app says Tweets.
    static func tweetsWording(_ text: String) -> String {
        text.replacingOccurrences(of: " posts", with: " Tweets").replacingOccurrences(of: " post", with: " Tweet")
    }

    /// Every `TimelineTrend` in a timeline (Explore's), on its own or in modules, in order.
    package static func trends(from root: Any) -> [Trend] {
        var trends: [Trend] = []
        var seen = Set<String>()

        func add(_ itemContent: JSON?) {
            guard let itemContent,
                itemContent["__typename"] as? String == "TimelineTrend"
                    || itemContent["itemType"] as? String == "TimelineTrend",
                let name = itemContent["name"] as? String
            else { return }
            let url = ((itemContent["trend_url"] as? JSON)?["url"] as? String).flatMap(URL.init(string:))
            let query = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
                .queryItems?.first { $0.name == "query" || $0.name == "q" }?.value
            let metadata = itemContent["trend_metadata"] as? JSON
            let trend = Trend(
                name: name,
                query: query,
                context: (metadata?["domain_context"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                volume: (metadata?["meta_description"] as? String).flatMap { $0.isEmpty ? nil : tweetsWording($0) }
            )
            guard seen.insert(trend.id).inserted else { return }
            trends.append(trend)
        }

        for instruction in findInstructions(in: root) ?? [] {
            var entries = instruction["entries"] as? [JSON] ?? []
            if let entry = instruction["entry"] as? JSON { entries.append(entry) }
            for entry in entries {
                guard let content = entry["content"] as? JSON else { continue }
                add(content["itemContent"] as? JSON)
                for wrapper in content["items"] as? [JSON] ?? [] {
                    add((wrapper["item"] as? JSON)?["itemContent"] as? JSON)
                }
            }
        }
        return trends
    }
}
