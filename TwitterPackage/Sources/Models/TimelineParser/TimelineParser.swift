import Foundation

/// Turns Twitter's GraphQL timeline JSON into app models. Twitter's payloads change shape often,
/// so every lookup is optional and tries both the current and the older field locations.
package enum TimelineParser {
    package typealias JSON = [String: Any]

    // MARK: Timelines

    package static func page(from root: Any) -> FeedPage {
        let instructions = findInstructions(in: root) ?? []
        var items: [FeedItem] = []
        var bottom: String?
        var top: String?
        var seen = Set<String>()

        func append(_ item: FeedItem) {
            guard seen.insert(item.id).inserted else { return }
            items.append(item)
        }

        var entries: [JSON] = []
        // Notifications: entries sorted above this are unread.
        var unreadAbove: String?
        for instruction in instructions {
            switch instruction["type"] as? String {
            case "TimelineMarkEntriesUnreadGreaterThanSortIndex":
                unreadAbove = (instruction["sort_index"] ?? instruction["sortIndex"]).map { "\($0)" }
            case "TimelineAddEntries":
                entries += instruction["entries"] as? [JSON] ?? []
            case "TimelinePinEntry", "TimelineReplaceEntry":
                if let entry = instruction["entry"] as? JSON { entries.append(entry) }
            case "TimelineAddToModule":
                // Later pages of a module (the profile media grid, a conversation's "Show more replies") arrive as
                // module items.
                let moduleEntryID = instruction["moduleEntryId"] as? String ?? "module"
                entries.append([
                    "entryId": moduleEntryID,
                    "content": [
                        "entryType": "TimelineTimelineModule",
                        "items": instruction["moduleItems"] as? [JSON] ?? [],
                        "displayType": moduleEntryID.hasPrefix("conversationthread") ? "VerticalConversation" : ""
                    ] as JSON
                ])
            default:
                break
            }
        }

        for entry in entries {
            let entryID = entry["entryId"] as? String ?? ""
            guard !entryID.hasPrefix("promoted"), let content = entry["content"] as? JSON else { continue }
            let kind = (content["entryType"] as? String) ?? (content["__typename"] as? String) ?? ""

            switch kind {
            case "TimelineTimelineCursor":
                let value = content["value"] as? String
                switch content["cursorType"] as? String {
                case "Bottom": bottom = value
                case "Top": top = value
                default:
                    if let showMore = showMoreCursor(from: content, entryID: entryID) { append(.showMore(showMore)) }
                }
            case "TimelineTimelineItem":
                guard let itemContent = content["itemContent"] as? JSON else { continue }
                if var item = feedItem(from: itemContent, entryID: entryID, context: content) {
                    if let unreadAbove, let sortIndex = entry["sortIndex"].map({ "\($0)" }),
                        isSortIndex(sortIndex, above: unreadAbove)
                    {
                        item.markUnread()
                    }
                    append(item)
                }
                if itemContent["itemType"] as? String == "TimelineTimelineCursor"
                    || itemContent["__typename"] as? String == "TimelineTimelineCursor",
                    itemContent["cursorType"] as? String == "Bottom"
                {
                    bottom = itemContent["value"] as? String
                }
            case "TimelineTimelineModule":
                var moduleEntries: [FeedItem] = []
                for (index, wrapper) in (content["items"] as? [JSON] ?? []).enumerated() {
                    guard let moduleItem = wrapper["item"] as? JSON,
                        let itemContent = moduleItem["itemContent"] as? JSON
                    else { continue }
                    let itemID = wrapper["entryId"] as? String ?? "\(entryID)-\(index)"
                    if let item = feedItem(from: itemContent, entryID: itemID, context: moduleItem) {
                        moduleEntries.append(item)
                    }
                }
                let isConversation = (content["displayType"] as? String)?.contains("Conversation") ?? false
                func isTweet(_ index: Int) -> Bool {
                    guard moduleEntries.indices.contains(index), case .tweet = moduleEntries[index] else {
                        return false
                    }
                    return true
                }
                for (index, item) in moduleEntries.enumerated() {
                    guard case .tweet(var tweet) = item else {
                        append(item)
                        continue
                    }
                    if isConversation {
                        tweet.connectsAbove = isTweet(index - 1)
                        tweet.connectsBelow = isTweet(index + 1)
                    }
                    append(.tweet(tweet))
                }
            default:
                break
            }
        }
        return FeedPage(items: items, bottomCursor: bottom, topCursor: top)
    }

    private static func feedItem(from itemContent: JSON, entryID: String, context: JSON) -> FeedItem? {
        if itemContent["promotedMetadata"] != nil { return nil }
        let type = (itemContent["itemType"] as? String) ?? (itemContent["__typename"] as? String)
        switch type {
        case "TimelineTweet":
            guard let result = (itemContent["tweet_results"] as? JSON)?["result"] as? JSON else { return nil }
            guard let feedTweet = feedTweet(from: result) else {
                return tombstone(from: result, id: entryID).map(FeedItem.tombstone)
            }
            var item = feedTweet
            if let context = itemContent["socialContext"] as? JSON, let social = context["text"] as? String,
                item.repostedBy == nil
            {
                item.socialContext = social
                item.socialSymbol =
                    switch (context["contextType"] as? String ?? "").lowercased() {
                    case "pin": "pin"
                    case "like": "heart"
                    case "follow", "following": "person"
                    case "conversation", "reply": "reply_stroke"
                    case "community": "communities"
                    case "list": "lists"
                    case "topic": "number"
                    case "location": "location"
                    case "megaphone", "spaces": "megaphone.fill"
                    default: social.lowercased().contains("pinned") ? "pin" : "sparkles"
                    }
            }
            return .tweet(item)
        case "TimelineNotification":
            return notification(from: itemContent, fallbackID: entryID).map(FeedItem.notification)
        case "TimelineTombstone":
            let info = itemContent["tombstoneInfo"] as? JSON
            let text = ((info?["richText"] as? JSON)?["text"] as? String) ?? (info?["text"] as? String)
            return .tombstone(tombstone(id: entryID, text: text))
        case "TimelineTimelineCursor":
            return showMoreCursor(from: itemContent, entryID: entryID).map(FeedItem.showMore)
        default:
            return nil
        }
    }

    /// "Show more replies" cursors inside conversations (`ShowMore`) and below them (`ShowMoreThreads…`).
    static func showMoreCursor(from content: JSON, entryID: String) -> ShowMoreCursor? {
        guard let type = content["cursorType"] as? String, type.hasPrefix("ShowMore"),
            let value = content["value"] as? String
        else { return nil }
        let treatment = content["displayTreatment"] as? JSON
        let label = (treatment?["actionText"] as? String) ?? (treatment?["labelText"] as? String)
        return ShowMoreCursor(
            id: entryID, cursor: value, label: label.flatMap { $0.isEmpty ? nil : $0 } ?? "Show more replies")
    }

    /// What Twitter shows in place of a post it won't return (deleted, withheld, suspended…): its own text when it
    /// sends some, otherwise the reason code.
    package static func tombstone(from result: JSON, id: String) -> Tombstone? {
        switch result["__typename"] as? String {
        case "TweetTombstone":
            let tombstone = result["tombstone"] as? JSON
            let text = ((tombstone?["text"] as? JSON)?["text"] as? String) ?? (tombstone?["text"] as? String)
            return Self.tombstone(id: id, text: text)
        case "TweetUnavailable":
            let reason: Tombstone.Reason =
                switch (result["reason"] as? String)?.lowercased() {
                case "suspended": .suspended
                case "protected": .protected
                case "nsfwloggedout", "nsfw": .sensitive
                default: .unavailable
                }
            return Tombstone(id: id, reason: reason)
        case "TweetWithVisibilityResults":
            return (result["tweet"] as? JSON).flatMap { tombstone(from: $0, id: id) }
        default:
            return nil
        }
    }

    private static func tombstone(id: String, text: String?) -> Tombstone {
        var text = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = text.range(of: "Learn more", options: [.caseInsensitive, .backwards, .anchored]) {
            text = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Twitter now says "Post"; the app says "Tweet", capitalized as Twitter always wrote it.
        text = text.replacingOccurrences(of: #"\b[Pp]ost(s?)\b"#, with: "Tweet$1", options: .regularExpression)
        return text.isEmpty ? Tombstone(id: id, reason: .unavailable) : Tombstone(id: id, text: text)
    }

    /// Sort indexes are decimal numbers too long for an Int64 to be sure of: compared as digit strings.
    static func isSortIndex(_ index: String, above marker: String) -> Bool {
        index.count != marker.count ? index.count > marker.count : index > marker
    }

    /// Recursively finds the first `instructions` array, whatever the operation's wrapper keys are.
    static func findInstructions(in value: Any, depth: Int = 0) -> [JSON]? {
        guard depth < 12 else { return nil }
        if let object = value as? JSON {
            if let instructions = object["instructions"] as? [JSON] { return instructions }
            for child in object.values {
                if let found = findInstructions(in: child, depth: depth + 1) { return found }
            }
        }
        return nil
    }

    // MARK: Helpers

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM dd HH:mm:ss Z yyyy"
        return formatter
    }()

    static func parseDate(_ string: String) -> Date? { dateFormatter.date(from: string) }

    static func decodeEntities(_ text: String) -> String {
        text.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    static func int(_ value: Any?) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? Double { return Int(value) }
        if let value = value as? String { return Int(value) ?? 0 }
        return 0
    }

    static func isoDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }

    static func double(_ value: Any?) -> Double {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        return 0
    }
}
