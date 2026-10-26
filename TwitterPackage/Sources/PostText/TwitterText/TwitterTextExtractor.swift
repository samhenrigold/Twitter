import RegexBuilder

/// twitter-text's extractors (`extractUrlsWithIndices`, `extractMentionsOrListsWithIndices`,
/// `extractHashtagsWithIndices`, `extractCashtagsWithIndices`, `extractReplies`, `extractEntitiesWithIndices`), so
/// what links in a Tweet here is what Twitter would link, and what counts as a URL toward its length is what Twitter
/// counts.
package enum TwitterTextExtractor {
    /// Every URL, mention, hashtag and cashtag in `text`, in order. Where two overlap, the earlier wins (a URL first
    /// when they start together).
    package static func entities(in text: String) -> [TwitterTextEntity] {
        removingOverlaps(
            urls(in: text) + mentionsOrLists(in: text) + hashtags(in: text, excludingURLs: false) + cashtags(in: text))
    }

    /// URLs, with or without a scheme. Without one, only the ASCII domains in a run of domain-like text link (in
    /// `example.comテスト.jp`, just `example.com`), and none after `-`, `_`, `.` or `/`.
    package static func urls(in text: String, includingWithoutScheme: Bool = true) -> [TwitterTextEntity] {
        guard includingWithoutScheme || text.unicodeScalars.contains(":") else { return [] }
        let pattern = TwitterTextPatterns.url
        var urls: [TwitterTextEntity] = []
        for match in runs(of: text, holding: ScalarSet("."), where: hasInnerDot).flatMap({
            $0.matches(of: pattern.regex)
        }) {
            var url = match[pattern.url]
            let scheme = match[pattern.scheme]
            let domain = match[pattern.domain]
            guard isValid(url, scheme: scheme, domain: domain) else { continue }

            guard scheme.isEmpty else {
                if let shortLink = url.prefixMatch(of: pattern.shortLink) {
                    // A t.co link ends at its slug (and query), whatever follows; an overlong slug isn't one.
                    guard shortLink[pattern.slug].unicodeScalars.count <= 40 else { continue }
                    url = url[..<shortLink.range.upperBound]
                }
                urls.append(TwitterTextEntity(.url(String(url)), range: url.startIndex..<url.endIndex))
                continue
            }
            let followsJoiner = match[pattern.before].unicodeScalars.last.map("-_./".unicodeScalars.contains) ?? false
            guard includingWithoutScheme, !followsJoiner else { continue }
            // Matched on a copy, as twitter-text matches the domain on its own: its TLDs' lookahead ends there.
            let domainText = String(domain)
            func position(_ index: String.Index) -> String.Index {
                text.utf8.index(
                    domain.startIndex, offsetBy: domainText.utf8.distance(from: domainText.startIndex, to: index))
            }
            let asciiDomains = domainText.matches(of: pattern.asciiDomain).map {
                position($0.range.lowerBound)..<position($0.range.upperBound)
            }
            guard let last = asciiDomains.last else { continue }
            urls += asciiDomains.dropLast().map { TwitterTextEntity(.url(String(text[$0])), range: $0) }
            if match[pattern.path].isEmpty {
                urls.append(TwitterTextEntity(.url(String(text[last])), range: last))
            } else {
                // The last one takes the path (and anything after the domain with it).
                let written = String(text[last]) + text[domain.endIndex..<url.endIndex]
                urls.append(TwitterTextEntity(.url(written), range: last.lowerBound..<url.endIndex))
            }
        }
        return urls
    }

    /// The runs of `text` between spaces that could hold a match: every match of a pattern holds one of `triggers`.
    ///
    /// No entity spans a space, and a space before or after one is a boundary just as the start or end of a run is,
    /// so matching each run as its own subject finds what matching the whole text would, without trying a pattern at
    /// every character between them (Swift's `Regex` has no prefilter of its own).
    private static func runs(
        of text: String, holding triggers: ScalarSet,
        where isCandidate: (Substring.UnicodeScalarView) -> Bool = { _ in true }
    ) -> [Substring] {
        text.unicodeScalars
            .split(whereSeparator: { $0.properties.isWhitespace && TwitterTextPatterns.spaces.contains($0) })
            .filter { $0.contains(where: triggers.contains) && isCandidate($0) }
            .map(Substring.init)
    }

    /// Whether `run` has a dot with a domain character after it, as every domain does before its TLD; a sentence's
    /// closing period doesn't.
    private static func hasInnerDot(_ run: Substring.UnicodeScalarView) -> Bool {
        zip(run, run.dropFirst()).contains { $0 == "." && TwitterTextPatterns.URLPattern.domainCharacter.contains($1) }
    }

    /// Mentions, and lists (`@name/slug`).
    package static func mentionsOrLists(in text: String) -> [TwitterTextEntity] {
        let pattern = TwitterTextPatterns.mention
        return runs(of: text, holding: TwitterTextPatterns.atSigns).flatMap { $0.matches(of: pattern.regex) }
            .compactMap { match in
                guard !text[match.range.upperBound...].starts(with: TwitterTextPatterns.invalidMentionSuffix) else {
                    return nil
                }
                let list = match[pattern.list]
                return TwitterTextEntity(
                    .mention(
                        screenName: String(match[pattern.screenName]),
                        listSlug: list.isEmpty ? nil : String(list.dropFirst())),
                    range: match[pattern.before].endIndex..<match.range.upperBound)
            }
    }

    /// Mentions of accounts, lists left out.
    package static func mentions(in text: String) -> [TwitterTextEntity] {
        mentionsOrLists(in: text).filter {
            if case .mention(_, nil) = $0.kind { true } else { false }
        }
    }

    /// The account `text` replies to: a mention before anything but spaces.
    package static func replyScreenName(in text: String) -> String? {
        let pattern = TwitterTextPatterns.mention
        guard let match = text.prefixMatch(of: pattern.reply),
            !text[match.range.upperBound...].starts(with: TwitterTextPatterns.invalidMentionSuffix)
        else { return nil }
        return String(match[pattern.replyScreenName])
    }

    /// Hashtags; with `excludingURLs`, none inside a URL (`example.com/#anchor`).
    package static func hashtags(in text: String, excludingURLs: Bool = true) -> [TwitterTextEntity] {
        let pattern = TwitterTextPatterns.hashtag
        let tags = runs(of: text, holding: TwitterTextPatterns.hashSigns).flatMap { $0.matches(of: pattern.regex) }
            .compactMap { match -> TwitterTextEntity? in
                guard !text[match.range.upperBound...].starts(with: TwitterTextPatterns.invalidHashtagSuffix) else {
                    return nil
                }
                return TwitterTextEntity(
                    .hashtag(String(match[pattern.tag])), range: match[pattern.before].endIndex..<match.range.upperBound
                )
            }
        guard excludingURLs, !tags.isEmpty else { return tags }
        let urls = urls(in: text)
        guard !urls.isEmpty else { return tags }
        return removingOverlaps(tags + urls).filter {
            if case .hashtag = $0.kind { true } else { false }
        }
    }

    package static func cashtags(in text: String) -> [TwitterTextEntity] {
        let pattern = TwitterTextPatterns.cashtag
        return runs(of: text, holding: ScalarSet("$")).flatMap { $0.matches(of: pattern.regex) }.map { match in
            TwitterTextEntity(
                .cashtag(String(match[pattern.symbol])), range: match[pattern.before].endIndex..<match.range.upperBound)
        }
    }

    /// `removeOverlappingEntities`: by start (ties in the given order), each kept unless it overlaps the last kept.
    package static func removingOverlaps(_ entities: [TwitterTextEntity]) -> [TwitterTextEntity] {
        let ordered = entities.enumerated().sorted {
            ($0.element.range.lowerBound, $0.offset) < ($1.element.range.lowerBound, $1.offset)
        }
        var kept: [TwitterTextEntity] = []
        for (_, entity) in ordered {
            if let last = kept.last, last.range.upperBound > entity.range.lowerBound { continue }
            kept.append(entity)
        }
        return kept
    }

    /// `isValidUrl` at extraction: every label of the domain fits DNS's 63 characters once Punycode-encoded, and the
    /// whole URL fits 4,096 (counting the scheme twice when it has one, as twitter-text does).
    private static func isValid(_ url: Substring, scheme: Substring, domain: Substring) -> Bool {
        if domain.hasPrefix("xn--"), !String(domain).contains(TwitterTextPatterns.url.asciiDomain) { return false }
        let labels = domain.unicodeScalars.split(separator: ".", omittingEmptySubsequences: false).map {
            Punycode.ascii($0)
        }
        guard labels.allSatisfy({ (1...63).contains($0.utf16.count) }) else { return false }
        let encodedLength = labels.reduce(labels.count - 1) { $0 + $1.utf16.count }
        let length = url.utf16.count + encodedLength - domain.utf16.count
        return (scheme.isEmpty ? "https://".utf16.count : scheme.utf16.count) + length <= 4_096
    }
}
