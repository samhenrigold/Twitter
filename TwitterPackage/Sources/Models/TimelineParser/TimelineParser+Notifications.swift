import Foundation

extension TimelineParser {
    static func notification(from content: JSON, fallbackID: String) -> TwitterNotification? {
        let rich = (content["rich_message"] as? JSON) ?? (content["message"] as? JSON)
        guard let message = rich?["text"] as? String else { return nil }

        // Current shape: template.from_users / target_objects. Older: template.aggregateUserActionsV1.fromUsers / targetObjects.
        let template = content["template"] as? JSON
        let aggregate = (template?["aggregateUserActionsV1"] as? JSON) ?? template
        let userRefs = (aggregate?["from_users"] as? [JSON]) ?? (aggregate?["fromUsers"] as? [JSON]) ?? []
        let users = userRefs.compactMap { ((($0["user_results"] as? JSON)?["result"]) as? JSON).flatMap(user(from:)) }

        var tweet: Tweet?
        let targets = (aggregate?["target_objects"] as? [JSON]) ?? (aggregate?["targetObjects"] as? [JSON]) ?? []
        for target in targets {
            if let result = (target["tweet_results"] as? JSON)?["result"] as? JSON,
                let parsed = Self.tweet(from: result, includeQuote: false)
            {
                tweet = parsed
                break
            }
        }
        var tweetID = tweet?.id
        if tweetID == nil, let url = (content["notification_url"] as? JSON)?["url"] as? String,
            let match = url.range(of: #"status/(\d+)"#, options: .regularExpression)
        {
            tweetID = String(url[match].dropFirst("status/".count))
        }

        let bold = (rich?["entities"] as? [JSON] ?? []).compactMap { entity -> Range<Int>? in
            guard let from = entity["fromIndex"] as? Int, let to = entity["toIndex"] as? Int, from < to else {
                return nil
            }
            return from..<to
        }

        var date: Date?
        if let raw = content["timestamp_ms"] as? String {
            date = Double(raw).map { Date(timeIntervalSince1970: $0 / 1000) } ?? isoDate(raw)
        } else if let raw = content["timestamp_ms"] as? Double {
            date = Date(timeIntervalSince1970: raw / 1000)
        }

        let worded = tweetWording(message, boldRanges: bold)
        return TwitterNotification(
            id: content["id"] as? String ?? fallbackID,
            icon: ((content["notification_icon"] as? String) ?? "").lowercased(),
            message: worded.text,
            boldRanges: worded.boldRanges,
            users: users,
            date: date,
            tweet: tweet,
            tweetID: tweetID
        )
    }

    /// Twitter says "liked your post" and "reposted"; the app says Tweet and Retweet. Bold runs (people's names) are
    /// left alone, and their ranges moved to match.
    static func tweetWording(_ text: String, boldRanges: [Range<Int>]) -> (text: String, boldRanges: [Range<Int>]) {
        let scalars = Array(text.unicodeScalars)
        let bold = boldRanges.map { $0.clamped(to: 0..<scalars.count) }.sorted { $0.lowerBound < $1.lowerBound }
        var result = String.UnicodeScalarView()
        var ranges: [Range<Int>] = []
        var index = 0
        func appendPlain(upTo end: Int) {
            guard index < end else { return }
            result.append(
                contentsOf: tweetWording(String(String.UnicodeScalarView(scalars[index..<end]))).unicodeScalars)
            index = end
        }
        for range in bold where range.lowerBound >= index {
            appendPlain(upTo: range.lowerBound)
            let start = result.count
            result.append(contentsOf: scalars[range])
            ranges.append(start..<result.count)
            index = range.upperBound
        }
        appendPlain(upTo: scalars.count)
        return (String(result), ranges)
    }

    private static var tweetWords: [(Regex<Substring>, String)] {
        [
            (/\b[Rr]eposted\b/, "Retweeted"),
            (/\b[Rr]eposts\b/, "Retweets"),
            (/\b[Rr]epost\b/, "Retweet"),
            (/\b[Pp]osted\b/, "Tweeted"),
            (/\b[Pp]osts\b/, "Tweets"),
            (/\b[Pp]ost\b/, "Tweet")
        ]
    }

    static func tweetWording(_ text: String) -> String {
        tweetWords.reduce(text) { $0.replacing($1.0, with: $1.1) }
    }
}
