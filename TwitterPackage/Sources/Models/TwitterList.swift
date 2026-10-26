import Foundation

/// A Twitter List: a timeline of the accounts someone put on it.
package struct TwitterList: Identifiable, Hashable, Codable, Sendable {
    package var id: String
    package var name: String
    package var description: String = ""
    package var memberCount = 0
    package var subscriberCount = 0
    package var isPrivate = false
    /// Who made it.
    package var owner: User?

    package init(
        id: String, name: String, description: String = "", memberCount: Int = 0, subscriberCount: Int = 0,
        isPrivate: Bool = false, owner: User? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.memberCount = memberCount
        self.subscriberCount = subscriberCount
        self.isPrivate = isPrivate
        self.owner = owner
    }
}

/// One page of lists, and the cursor for the next.
package struct ListPage: Sendable {
    package var lists: [TwitterList]
    package var bottomCursor: String?

    package init(lists: [TwitterList], bottomCursor: String?) {
        self.lists = lists
        self.bottomCursor = bottomCursor
    }
}

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
