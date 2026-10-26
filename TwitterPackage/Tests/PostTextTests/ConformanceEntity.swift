/// An entity as the `*_with_indices` sections write it: its text under the key for its kind, and UTF-16 indices.
struct ConformanceEntity: Decodable, Hashable, Sendable, CustomStringConvertible {
    var text: String
    /// `@name/slug`'s `/slug`, empty for a plain mention; `nil` outside `mentions_or_lists_with_indices`.
    var listSlug: String?
    var indices: [Int]

    var description: String { "\(text)\(listSlug ?? "") \(indices)" }

    init(text: String, listSlug: String? = nil, indices: [Int]) {
        self.text = text
        self.listSlug = listSlug
        self.indices = indices
    }

    private enum CodingKeys: String, CodingKey {
        case url, hashtag, cashtag
        case screenName = "screen_name"
        case listSlug = "list_slug"
        case indices
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kinds: [CodingKeys] = [.url, .hashtag, .cashtag, .screenName]
        guard let key = kinds.first(where: container.contains) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "No entity text"))
        }
        text = try container.decode(String.self, forKey: key)
        listSlug = try container.decodeIfPresent(String.self, forKey: .listSlug)
        indices = try container.decode([Int].self, forKey: .indices)
    }
}
