/// A run of parsed post text: uniform styling, and at most one entity.
package struct PostTextPiece: Hashable, Sendable {
    package var text: String
    package var entity: PostEntity?
    package var emphasis: PostTextEmphasis

    package init(text: String, entity: PostEntity? = nil, emphasis: PostTextEmphasis = []) {
        self.text = text
        self.entity = entity
        self.emphasis = emphasis
    }
}

/// Post text → pieces. Pure and synchronous; ``PostTextTypesetter`` decides where it runs and caches the result.
///
/// The passes, in order:
/// 1. **Entities**: the text is tokenized into URLs, mentions, hashtags and cashtags. Entities are atomic: nothing
///    later splits or restyles part of one, except Twitter's own bold/italic ranges.
/// 2. **Twitter styles**: the Unicode-scalar bold/italic ranges cut pieces at their edges. They're the only styling:
///    no punctuation is read as Markdown.
/// 3. **Character references**: `&amp;`-style escapes left in plain text are decoded.
/// 4. **Truncation**, when a character limit is set, at a word boundary and never inside an entity.
package enum PostTextParser {
    package static func pieces(for input: PostTextInput) -> [PostTextPiece] {
        var pieces = styledPieces(input)
        if let limit = input.characterLimit {
            pieces = truncate(pieces, limit: limit)
        }
        return coalesce(pieces)
    }

    // MARK: Entities and styles

    private static func styledPieces(_ input: PostTextInput) -> [PostTextPiece] {
        let text = input.text
        let scalars = text.unicodeScalars
        let tokens = EntityScanner.tokens(in: text, links: input.links, tags: input.tags)
        guard !input.styles.isEmpty else {
            return tokens.map { token in
                piece(String(scalars[token.range]), entity: token.entity, emphasis: [])
            }
        }

        let count = scalars.count
        let styled: [(range: Range<String.Index>, emphasis: PostTextEmphasis)] = input.styles.compactMap { style in
            let lower = min(max(style.range.lowerBound, 0), count)
            let upper = min(max(style.range.upperBound, lower), count)
            guard lower < upper, style.isBold || style.isItalic else { return nil }
            let start = scalars.index(scalars.startIndex, offsetBy: lower)
            let end = scalars.index(start, offsetBy: upper - lower)
            var emphasis: PostTextEmphasis = []
            if style.isBold { emphasis.insert(.bold) }
            if style.isItalic { emphasis.insert(.italic) }
            return (start..<end, emphasis)
        }
        let boundaries = Set(styled.flatMap { [$0.range.lowerBound, $0.range.upperBound] }).sorted()

        var pieces: [PostTextPiece] = []
        for token in tokens {
            let inner = boundaries.filter { $0 > token.range.lowerBound && $0 < token.range.upperBound }
            let cuts = [token.range.lowerBound] + inner + [token.range.upperBound]
            for (start, end) in zip(cuts, cuts.dropFirst()) {
                let emphasis = styled.reduce(into: PostTextEmphasis()) { emphasis, style in
                    if style.range.lowerBound <= start, end <= style.range.upperBound {
                        emphasis.formUnion(style.emphasis)
                    }
                }
                pieces.append(piece(String(scalars[start..<end]), entity: token.entity, emphasis: emphasis))
            }
        }
        return pieces
    }

    // MARK: Shared passes

    private static func piece(_ text: String, entity: PostEntity?, emphasis: PostTextEmphasis) -> PostTextPiece {
        PostTextPiece(text: entity == nil ? CharacterReferences.decode(text) : text, entity: entity, emphasis: emphasis)
    }

    /// Keeps whole pieces up to `limit` characters, cuts the plain piece that crosses it at a nearby word boundary,
    /// and drops an entity that crosses it rather than show half of one.
    private static func truncate(_ pieces: [PostTextPiece], limit: Int) -> [PostTextPiece] {
        var result: [PostTextPiece] = []
        var used = 0
        for piece in pieces {
            let count = piece.text.count
            if used + count <= limit {
                result.append(piece)
                used += count
                continue
            }
            if piece.entity == nil {
                var prefix = piece.text.prefix(limit - used)
                if let space = prefix.lastIndex(where: \.isWhitespace),
                    prefix.distance(from: space, to: prefix.endIndex) < 40
                {
                    prefix = prefix[..<space]
                }
                var cut = piece
                cut.text = String(prefix)
                result.append(cut)
            }
            break
        }
        while var last = result.popLast() {
            let trimmed = String(last.text.reversed().drop(while: \.isWhitespace).reversed())
            guard !trimmed.isEmpty else { continue }
            last.text = trimmed
            result.append(last)
            break
        }
        result.append(PostTextPiece(text: "…"))
        return result
    }

    /// Joins neighbours that render identically and drops empty pieces.
    private static func coalesce(_ pieces: [PostTextPiece]) -> [PostTextPiece] {
        var result: [PostTextPiece] = []
        result.reserveCapacity(pieces.count)
        for piece in pieces where !piece.text.isEmpty {
            if let last = result.last, last.entity == piece.entity, last.emphasis == piece.emphasis {
                result[result.count - 1].text += piece.text
            } else {
                result.append(piece)
            }
        }
        return result
    }
}
