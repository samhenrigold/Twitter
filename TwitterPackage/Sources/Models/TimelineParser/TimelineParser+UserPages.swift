extension TimelineParser {
    /// A user timeline (`Followers`, `Following`, `Retweeters`, `Favoriters`): `TimelineUser` items and a bottom cursor.
    ///
    /// These timelines always end with a bottom cursor, even on their last page, where its value starts with `0|`;
    /// that one is dropped so paging stops there instead of asking for an empty page.
    package static func userPage(from root: Any) -> UserPage {
        var users: [User] = []
        var seen = Set<String>()
        var bottom: String?

        for instruction in findInstructions(in: root) ?? [] {
            let entries: [JSON] =
                switch instruction["type"] as? String {
                case "TimelineAddEntries": instruction["entries"] as? [JSON] ?? []
                case "TimelineReplaceEntry": (instruction["entry"] as? JSON).map { [$0] } ?? []
                default: []
                }
            for entry in entries {
                let entryID = entry["entryId"] as? String ?? ""
                guard !entryID.hasPrefix("promoted"), let content = entry["content"] as? JSON else { continue }
                if content["cursorType"] as? String == "Bottom" {
                    bottom = content["value"] as? String
                    continue
                }
                guard let itemContent = content["itemContent"] as? JSON,
                    itemContent["promotedMetadata"] == nil,
                    let user = user(fromResult: itemContent),
                    seen.insert(user.id).inserted
                else { continue }
                users.append(user)
            }
        }
        if let cursor = bottom, cursor.hasPrefix("0|") { bottom = nil }
        return UserPage(users: users, bottomCursor: bottom)
    }
}
