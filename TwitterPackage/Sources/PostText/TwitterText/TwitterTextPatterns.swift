import RegexBuilder

/// twitter-text's patterns (`js/src/regexp/` and `rb/lib/twitter-text/regex.rb` at twitter/twitter-text 30e2430),
/// in RegexBuilder.
///
/// They match Unicode scalars, as the originals match code points, and each consumes the character before an entity
/// as the originals do (Swift's `Regex` has no lookbehind either), so walking `matches(of:)` visits the text as their
/// global `exec` loops do. Unicode properties stand in for the generated letter, mark and digit tables, which predate
/// the Unicode versions the properties track.
///
/// `Regex` isn't `Sendable`, but the patterns are built once and shared, which is safe: a built regex is immutable,
/// and its compiled program is published atomically on first use.
enum TwitterTextPatterns {
    nonisolated(unsafe) static let url = URLPattern()
    nonisolated(unsafe) static let mention = MentionPattern()
    nonisolated(unsafe) static let hashtag = HashtagPattern()
    nonisolated(unsafe) static let cashtag = CashtagPattern()

    /// `endMentionMatch`: what may not follow a mention (another `@`, an accented letter, or a scheme's `://`).
    nonisolated(unsafe) static let invalidMentionSuffix = Regex {
        ChoiceOf {
            atSigns
            latinAccents
            "://"
        }
    }
    .matchingSemantics(.unicodeScalar)

    /// `endHashtagMatch`: what may not follow a hashtag.
    nonisolated(unsafe) static let invalidHashtagSuffix = Regex {
        ChoiceOf {
            hashSigns
            "://"
        }
    }
    .matchingSemantics(.unicodeScalar)

    // MARK: Character sets

    /// `spaces`: Unicode White_Space, as twitter-text lists it.
    static let spaces = ScalarSet("\u{09}"..."\u{0D}", "\u{2000}"..."\u{200A}")
        .union(ScalarSet("\u{20}\u{85}\u{A0}\u{1680}\u{180E}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}"))

    /// `directionalMarkersGroup`: bidi marks, embeddings, overrides and isolates.
    static let directionalMarks = ScalarSet("\u{202A}"..."\u{202E}", "\u{2066}"..."\u{2069}")
        .union(ScalarSet("\u{061C}\u{200E}\u{200F}"))

    /// `invalidCharsGroup`: what a Tweet may not hold at all.
    static let invalidCharacters = ScalarSet("\u{FFFE}\u{FEFF}\u{FFFF}")

    /// ASCII punctuation (Ruby's `PUNCTUATION_CHARS`; the JavaScript `punct` omits `"` and `` ` ``).
    static let punctuation = ScalarSet(##"!"#$%&'()*+,-./:;<=>?@[\]^_`{|}~"##)

    static let controlCharacters = ScalarSet("\u{00}"..."\u{1F}", "\u{7F}"..."\u{7F}")

    static let asciiLetters = ScalarSet("a"..."z", "A"..."Z")

    static let asciiDigits = ScalarSet("0"..."9")

    static let asciiAlphanumerics = asciiLetters.union(asciiDigits)

    /// `latinAccentChars`: Latin-1 and Latin Extended letters, IPA letters some languages use, combining diacritics.
    static let latinAccents = ScalarSet(
        "\u{C0}"..."\u{D6}", "\u{D8}"..."\u{F6}", "\u{F8}"..."\u{FF}", "\u{0100}"..."\u{024F}",
        "\u{0300}"..."\u{036F}", "\u{1E00}"..."\u{1EFF}"
    )
    .union(
        ScalarSet(
            "\u{0253}\u{0254}\u{0256}\u{0257}\u{0259}\u{025B}\u{0263}\u{0268}\u{026F}\u{0272}\u{0289}\u{028B}\u{02BB}"))

    /// `cyrillicLettersAndMarks`.
    static let cyrillic = ScalarSet("\u{0400}"..."\u{04FF}")

    /// What a screen name is made of.
    static let mentionNameCharacters = asciiAlphanumerics.union(ScalarSet("_"))

    static let atSigns = ScalarSet("@＠")

    static let hashSigns = ScalarSet("#＃")
}
