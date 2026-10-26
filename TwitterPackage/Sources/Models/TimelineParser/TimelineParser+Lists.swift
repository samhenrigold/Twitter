extension TimelineParser {
    /// A timeline of lists (`CombinedLists`, `ListsManagementPageTimeline`): `TimelineTwitterList` items, on their own
    /// or in modules, and a bottom cursor (dropped on the last page, whose value starts with `0|`).
    package static func listPage(from root: Any) -> ListPage {
        var lists: [TwitterList] = []
        var seen = Set<String>()
        var bottom: String?

        func add(_ itemContent: JSON?) {
            guard let itemContent,
                itemContent["__typename"] as? String == "TimelineTwitterList"
                    || itemContent["itemType"] as? String == "TimelineTwitterList",
                let list = twitterList(from: itemContent["list"] as? JSON),
                seen.insert(list.id).inserted
            else { return }
            lists.append(list)
        }

        for instruction in findInstructions(in: root) ?? [] {
            for entry in instruction["entries"] as? [JSON] ?? [] {
                guard let content = entry["content"] as? JSON else { continue }
                if content["cursorType"] as? String == "Bottom" {
                    bottom = content["value"] as? String
                    continue
                }
                add(content["itemContent"] as? JSON)
                for wrapper in content["items"] as? [JSON] ?? [] {
                    add((wrapper["item"] as? JSON)?["itemContent"] as? JSON)
                }
            }
        }
        if let cursor = bottom, cursor.hasPrefix("0|") { bottom = nil }
        return ListPage(lists: lists, bottomCursor: bottom)
    }

    static func twitterList(from json: JSON?) -> TwitterList? {
        guard let json, let id = (json["id_str"] as? String) ?? (json["id"] as? String),
            let name = json["name"] as? String
        else { return nil }
        return TwitterList(
            id: id,
            name: name,
            description: json["description"] as? String ?? "",
            memberCount: json["member_count"] as? Int ?? 0,
            subscriberCount: json["subscriber_count"] as? Int ?? 0,
            isPrivate: (json["mode"] as? String)?.lowercased() == "private",
            owner: user(fromResult: json["user_results"])
        )
    }
}
