import Foundation

extension TimelineParser {
    static func feedTweet(from result: JSON) -> FeedTweet? {
        guard let outer = unwrapTweet(result), let legacy = outer["legacy"] as? JSON else { return nil }
        if let retweeted = ((legacy["retweeted_status_result"] as? JSON)?["result"] as? JSON),
            let inner = tweet(from: retweeted)
        {
            let reposter = user(fromResult: outer["core"])
            return FeedTweet(id: "rt-\(outer["rest_id"] as? String ?? inner.id)", tweet: inner, repostedBy: reposter)
        }
        guard let tweet = tweet(from: outer) else { return nil }
        return FeedTweet(id: tweet.id, tweet: tweet)
    }

    package static func unwrapTweet(_ result: JSON) -> JSON? {
        switch result["__typename"] as? String {
        case "TweetWithVisibilityResults": return result["tweet"] as? JSON
        case "TweetTombstone", "TweetUnavailable": return nil
        default: return result
        }
    }

    static func tweet(from raw: JSON, includeQuote: Bool = true) -> Tweet? {
        guard let result = unwrapTweet(raw),
            let legacy = result["legacy"] as? JSON,
            let id = (result["rest_id"] as? String) ?? (legacy["id_str"] as? String),
            let author = user(fromResult: result["core"])
        else { return nil }

        let noteResult = ((result["note_tweet"] as? JSON)?["note_tweet_results"] as? JSON)?["result"] as? JSON
        let mediaEntities =
            ((legacy["extended_entities"] as? JSON)?["media"] as? [JSON])
            ?? ((legacy["entities"] as? JSON)?["media"] as? [JSON]) ?? []
        let quoted = includeQuote ? (result["quoted_status_result"] as? JSON)?["result"] as? JSON : nil

        var entities = legacy["entities"] as? JSON
        var source = legacy["full_text"] as? String ?? ""
        var styles: [TextStyleRange] = []
        if let note = noteResult, let noteText = note["text"] as? String {
            entities = (note["entity_set"] as? JSON) ?? entities
            source = noteText
            let tags = ((note["richtext"] as? JSON)?["richtext_tags"] as? [JSON]) ?? []
            styles = tags.compactMap(textStyle(from:))
        } else if let range = legacy["display_text_range"] as? [Int], range.count == 2 {
            let scalars = Array(source.unicodeScalars)
            let lower = min(max(range[0], 0), scalars.count)
            let upper = min(max(range[1], lower), scalars.count)
            var view = String.UnicodeScalarView()
            view.append(contentsOf: scalars[lower..<upper])
            source = String(view)
        }

        // One pass over the text: t.co links become their display text (and links), media links and the quote's
        // permalink go, and character references decode, so a link's range is known from the edit that made it.
        let urls = (entities?["urls"] as? [JSON]) ?? []
        var replacements = urls.compactMap { entry -> Replacement? in
            guard let short = entry["url"] as? String else { return nil }
            let expanded = (entry["expanded_url"] as? String).flatMap(URL.init(string:))
            return Replacement(short, with: (entry["display_url"] as? String) ?? short, link: expanded)
        }
        replacements += mediaEntities.compactMap { ($0["url"] as? String).map { Replacement($0, with: "") } }
        if quoted != nil, let permalink = (legacy["quoted_status_permalink"] as? JSON)?["url"] as? String,
            !urls.contains(where: { $0["url"] as? String == permalink })
        {
            replacements.append(Replacement(permalink, with: ""))
        }
        replacements += htmlEntities
        let rewritten = rewrite(source, replacing: replacements, styles: styles)

        var tweet = Tweet(id: id, author: author, text: rewritten.text, links: rewritten.links)
        tweet.styles = rewritten.styles
        tweet.hashtags = ((entities?["hashtags"] as? [JSON]) ?? []).compactMap {
            ($0["text"] as? String).map { "#\($0)" }
        }
        tweet.cashtags = ((entities?["symbols"] as? [JSON]) ?? []).compactMap {
            ($0["text"] as? String).map { "$\($0)" }
        }
        tweet.communityNote = communityNote(
            from: (result["birdwatch_pivot"] as? JSON) ?? (raw["birdwatch_pivot"] as? JSON))
        tweet.poll = poll(from: result["card"] as? JSON)
        tweet.replyRestriction = replyRestriction(raw: raw, result: result, legacy: legacy, author: author)
        tweet.createdAt = (legacy["created_at"] as? String).flatMap(parseDate)
        tweet.language = legacy["lang"] as? String
        tweet.replyCount = int(legacy["reply_count"])
        tweet.repostCount = int(legacy["retweet_count"])
        tweet.likeCount = int(legacy["favorite_count"])
        tweet.quoteCount = int(legacy["quote_count"])
        tweet.bookmarkCount = int(legacy["bookmark_count"])
        tweet.viewCount = ((result["views"] as? JSON)?["count"] as? String).flatMap(Int.init)
        tweet.isLiked = legacy["favorited"] as? Bool ?? false
        tweet.isReposted = legacy["retweeted"] as? Bool ?? false
        tweet.isBookmarked = legacy["bookmarked"] as? Bool ?? false
        tweet.conversationID = legacy["conversation_id_str"] as? String
        tweet.media = mediaEntities.compactMap(media(from:))
        tweet.card = card(from: result["card"] as? JSON)

        // Only a reply to a Tweet: Twitter also names the account a standalone Tweet starts by mentioning
        // ("@X hey"), with no Tweet to reply to.
        if legacy["in_reply_to_status_id_str"] is String, let replyTo = legacy["in_reply_to_screen_name"] as? String {
            let mentions = ((legacy["entities"] as? JSON)?["user_mentions"] as? [JSON] ?? []).compactMap {
                $0["screen_name"] as? String
            }
            var names = [replyTo] + mentions.filter { $0 != replyTo && !tweet.text.contains("@\($0)") }
            names = Array(NSOrderedSet(array: names)) as? [String] ?? names
            tweet.replyingTo = Array(names.prefix(3))
        }

        if let quoted {
            if let quotedTweet = Self.tweet(from: quoted, includeQuote: false) {
                tweet.quoted = [quotedTweet]
            } else {
                let quotedID = (quoted["rest_id"] as? String) ?? "\(tweet.id)-quote"
                tweet.quotedTombstone =
                    tombstone(from: quoted, id: quotedID) ?? Tombstone(id: quotedID, reason: .unavailable)
            }
        }
        if tweet.card != nil || !tweet.quoted.isEmpty || tweet.quotedTombstone != nil {
            dropTrailingTwitterLink(from: &tweet)
        }
        return tweet
    }

    /// The card or quote already shows a trailing link to a Tweet; the text drops it when it is the last thing there.
    private static func dropTrailingTwitterLink(from tweet: inout Tweet) {
        let scalarCount = tweet.text.unicodeScalars.count
        guard
            let index = tweet.links.firstIndex(where: {
                $0.range.upperBound == scalarCount
                    && ($0.url.host?.contains("x.com") == true || $0.url.host?.contains("twitter.com") == true)
            })
        else { return }
        let start = tweet.links[index].range.lowerBound
        var view = String.UnicodeScalarView()
        view.append(contentsOf: tweet.text.unicodeScalars.prefix(start))
        while let last = view.last, last.properties.isWhitespace { view.removeLast() }
        let end = view.count
        tweet.text = String(view)
        tweet.links.remove(at: index)
        tweet.styles = tweet.styles.compactMap { style in
            guard style.range.lowerBound < end else { return nil }
            var style = style
            style.range = style.range.lowerBound..<min(style.range.upperBound, end)
            return style
        }
    }

    /// A substring of the API's text to replace, and the link the replacement shows, if it is one.
    private struct Replacement {
        let target: String
        let replacement: String
        let link: URL?

        init(_ target: String, with replacement: String, link: URL? = nil) {
            self.target = target
            self.replacement = replacement
            self.link = link
        }
    }

    /// Character references Twitter leaves in text. Decoded here, once: the typesetter shows text as it is.
    private static let htmlEntities = [
        Replacement("&lt;", with: "<"), Replacement("&gt;", with: ">"), Replacement("&quot;", with: "\""),
        Replacement("&#39;", with: "'"), Replacement("&amp;", with: "&")
    ]

    /// Replaces substrings of `text` while keeping `styles` and `links` (Unicode-scalar ranges) on the same
    /// characters, links each replacement that carries one, then trims surrounding whitespace.
    private static func rewrite(
        _ text: String, replacing replacements: [Replacement], styles: [TextStyleRange] = [], links: [TextLink] = []
    ) -> (text: String, styles: [TextStyleRange], links: [TextLink]) {
        let scalars = Array(text.unicodeScalars)
        var edits: [(range: Range<Int>, replacement: Replacement)] = []
        for replacement in replacements.sorted(by: {
            $0.target.unicodeScalars.count > $1.target.unicodeScalars.count
        }) where !replacement.target.isEmpty {
            let needle = Array(replacement.target.unicodeScalars)
            var index = 0
            while index + needle.count <= scalars.count {
                let range = index..<(index + needle.count)
                if scalars[range].elementsEqual(needle), !edits.contains(where: { $0.range.overlaps(range) }) {
                    edits.append((range, replacement))
                    index += needle.count
                } else {
                    index += 1
                }
            }
        }
        edits.sort { $0.range.lowerBound < $1.range.lowerBound }

        var output: [Unicode.Scalar] = []
        var applied: [(old: Range<Int>, new: Range<Int>, link: URL?)] = []
        var cursor = 0
        for edit in edits {
            output += scalars[cursor..<edit.range.lowerBound]
            let start = output.count
            output += edit.replacement.replacement.unicodeScalars
            applied.append((edit.range, start..<output.count, edit.replacement.link))
            cursor = edit.range.upperBound
        }
        output += scalars[cursor...]

        func map(_ index: Int, isUpper: Bool) -> Int {
            var delta = 0
            for edit in applied {
                if index >= edit.old.upperBound {
                    delta = edit.new.upperBound - edit.old.upperBound
                } else if index > edit.old.lowerBound {
                    return isUpper ? edit.new.upperBound : edit.new.lowerBound
                } else {
                    break
                }
            }
            return index + delta
        }

        let leading = output.prefix { $0.properties.isWhitespace }.count
        let trailing = output.count == leading ? 0 : output.reversed().prefix { $0.properties.isWhitespace }.count
        let trimmed = Array(output[leading..<(output.count - trailing)])
        /// A range of the output, in the trimmed text; `nil` when nothing of it is left.
        func clamp(_ range: Range<Int>) -> Range<Int>? {
            let lower = min(max(range.lowerBound - leading, 0), trimmed.count)
            let upper = min(max(range.upperBound - leading, lower), trimmed.count)
            return lower < upper ? lower..<upper : nil
        }
        let mappedStyles = styles.compactMap { style -> TextStyleRange? in
            guard
                let range = clamp(
                    map(style.range.lowerBound, isUpper: false)..<map(style.range.upperBound, isUpper: true))
            else { return nil }
            var style = style
            style.range = range
            return style
        }
        let carried = links.compactMap { link in
            clamp(map(link.range.lowerBound, isUpper: false)..<map(link.range.upperBound, isUpper: true)).map {
                TextLink(range: $0, url: link.url)
            }
        }
        let made = applied.compactMap { edit in
            edit.link.flatMap { url in clamp(edit.new).map { TextLink(range: $0, url: url) } }
        }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: trimmed)
        return (String(view), mappedStyles, (carried + made).sorted { $0.range.lowerBound < $1.range.lowerBound })
    }

    private static func textStyle(from tag: JSON) -> TextStyleRange? {
        let from = int(tag["from_index"])
        let to = int(tag["to_index"])
        let types = (tag["richtext_types"] as? [String] ?? []).map { $0.lowercased() }
        guard from >= 0, to > from, types.contains("bold") || types.contains("italic") else { return nil }
        return TextStyleRange(range: from..<to, isBold: types.contains("bold"), isItalic: types.contains("italic"))
    }

    /// `birdwatch_pivot`: the "Readers added context" note shown under a post.
    static func communityNote(from pivot: JSON?) -> CommunityNote? {
        guard let pivot else { return nil }
        let subtitle = pivot["subtitle"] as? JSON
        guard let text = (subtitle?["text"] as? String) ?? (pivot["subtitle"] as? String), !text.isEmpty else {
            return nil
        }
        let scalarCount = text.unicodeScalars.count
        let links = (subtitle?["entities"] as? [JSON] ?? []).compactMap { entity -> TextLink? in
            let from = int(entity["fromIndex"])
            let to = int(entity["toIndex"])
            guard from >= 0, to > from, to <= scalarCount,
                let url = ((entity["ref"] as? JSON)?["url"] as? String).flatMap(URL.init(string:))
            else { return nil }
            return TextLink(range: from..<to, url: url)
        }
        let rewritten = rewrite(text, replacing: htmlEntities, links: links)
        let footer = pivot["footer"] as? JSON
        return CommunityNote(
            id: (pivot["note"] as? JSON)?["rest_id"] as? String,
            title: (pivot["title"] as? String) ?? "Readers added context they thought people might want to know",
            shortTitle: pivot["shorttitle"] as? String,
            text: rewritten.text,
            links: rewritten.links,
            // The footer names the service ("people who use X"); the app always says Twitter.
            footer: ((footer?["text"] as? String) ?? (pivot["footer"] as? String))?.replacingOccurrences(
                of: #"\bX\b"#, with: "Twitter", options: .regularExpression),
            destinationURL: ((pivot["destinationUrl"] as? String) ?? (footer?["destinationUrl"] as? String))
                .flatMap(URL.init(string:))
        )
    }

    /// Text-only and image polls (`poll2choice_text_only` … `poll4choice_image`).
    static func poll(from card: JSON?) -> Poll? {
        guard let legacy = card?["legacy"] as? JSON,
            let name = legacy["name"] as? String,
            name.hasPrefix("poll"), name.contains("choice"),
            let bindings = legacy["binding_values"] as? [JSON]
        else { return nil }
        var values: [String: JSON] = [:]
        for binding in bindings {
            if let key = binding["key"] as? String, let value = binding["value"] as? JSON { values[key] = value }
        }
        var choices: [Poll.Choice] = []
        for index in 1...4 {
            guard let label = values["choice\(index)_label"]?["string_value"] as? String else { break }
            choices.append(Poll.Choice(label: label, count: int(values["choice\(index)_count"]?["string_value"])))
        }
        guard !choices.isEmpty else { return nil }
        let selected = (values["selected_choice"]?["string_value"] as? String).flatMap(Int.init)
        var poll = Poll(
            choices: choices,
            endsAt: (values["end_datetime_utc"]?["string_value"] as? String).flatMap(isoDate),
            countsAreFinal: values["counts_are_final"]?["boolean_value"] as? Bool ?? false,
            selectedChoiceIndex: selected.flatMap { (1...choices.count).contains($0) ? $0 - 1 : nil },
            imageURL: ((values["image_large"]?["image_value"] as? JSON)?["url"] as? String)
                .flatMap(URL.init(string:))
        )
        poll.cardURI = (legacy["url"] as? String) ?? (card?["rest_id"] as? String)
        poll.cardName = name
        return poll
    }

    /// `conversation_control` (the author's reply policy) and `limitedActionResults` (whether the viewer may reply).
    static func replyRestriction(raw: JSON, result: JSON, legacy: JSON, author: User) -> ReplyRestriction? {
        let control = (legacy["conversation_control"] as? JSON) ?? (result["conversation_control"] as? JSON)
        let limited =
            ((raw["limitedActionResults"] as? JSON) ?? (result["limitedActionResults"] as? JSON))?["limited_actions"]
            as? [JSON] ?? []
        let replyLimit = limited.first { ($0["action"] as? String) == "Reply" }
        guard control != nil || replyLimit != nil else { return nil }

        let policy: ReplyRestriction.Policy =
            switch (control?["policy"] as? String)?.lowercased() {
            case "byinvitation", "mentioned": .mentioned
            case "community", "following", "followers": .following
            case "verified": .verified
            case "subscribers", "superfollowers": .subscribers
            default: .other
            }
        let ownerResult = (control?["conversation_owner_results"] as? JSON)?["result"] as? JSON
        let ownerCore = ownerResult?["core"] as? JSON
        let ownerLegacy = ownerResult?["legacy"] as? JSON
        let owner =
            (ownerCore?["screen_name"] as? String) ?? (ownerLegacy?["screen_name"] as? String) ?? author.screenName
        let prompt = replyLimit?["prompt"] as? JSON
        let promptText =
            ((prompt?["subtext"] as? JSON)?["text"] as? String) ?? ((prompt?["headline"] as? JSON)?["text"] as? String)
        return ReplyRestriction(
            policy: policy, ownerScreenName: owner, viewerCanReply: replyLimit == nil, prompt: promptText)
    }

    private static func media(from entry: JSON) -> Media? {
        guard let preview = (entry["media_url_https"] as? String).flatMap(URL.init(string:)) else { return nil }
        let size = entry["original_info"] as? JSON
        let kind: Media.Kind =
            switch entry["type"] as? String {
            case "video": .video
            case "animated_gif": .gif
            default: .photo
            }
        let videoInfo = entry["video_info"] as? JSON
        let allVariants = videoInfo?["variants"] as? [JSON] ?? []
        let variants = allVariants.filter { ($0["content_type"] as? String) == "video/mp4" }
        let best = variants.max { int($0["bitrate"]) < int($1["bitrate"]) }
        let sorted = variants.sorted { int($0["bitrate"]) < int($1["bitrate"]) }
        let inline = sorted.last { int($0["bitrate"]) <= 2_200_000 } ?? sorted.first
        // Some videos (broadcasts, some newer uploads) come only as an HLS playlist, which AVPlayer plays as well.
        let stream = allVariants.first { ($0["content_type"] as? String) == "application/x-mpegURL" }
        let videoURL = ((best ?? stream)?["url"] as? String).flatMap(URL.init(string:))
        return Media(
            id: entry["id_str"] as? String ?? preview.absoluteString,
            kind: kind,
            previewURL: preview,
            videoURL: videoURL,
            inlineVideoURL: (inline?["url"] as? String).flatMap(URL.init(string:)) ?? videoURL,
            width: double(size?["width"]),
            height: double(size?["height"]),
            altText: entry["ext_alt_text"] as? String,
            durationMillis: videoInfo?["duration_millis"] as? Int
        )
    }

    private static func card(from card: JSON?) -> LinkCard? {
        guard let legacy = card?["legacy"] as? JSON, let bindings = legacy["binding_values"] as? [JSON] else {
            return nil
        }
        var values: [String: JSON] = [:]
        for binding in bindings {
            if let key = binding["key"] as? String, let value = binding["value"] as? JSON { values[key] = value }
        }
        func string(_ key: String) -> String? { values[key]?["string_value"] as? String }
        func image(_ keys: [String]) -> URL? {
            for key in keys {
                if let url = ((values[key]?["image_value"] as? JSON)?["url"] as? String).flatMap(URL.init(string:)) {
                    return url
                }
            }
            return nil
        }
        guard let title = string("title"),
            let url = (string("card_url") ?? legacy["url"] as? String).flatMap(URL.init(string:))
        else { return nil }
        return LinkCard(
            title: title,
            domain: string("vanity_url") ?? string("domain") ?? url.host ?? "",
            url: url,
            imageURL: image([
                "summary_photo_image_large", "thumbnail_image_large", "photo_image_full_size_large",
                "summary_photo_image"
            ])
        )
    }
}
