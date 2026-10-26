import RegexBuilder

/// An emoji as twitter-text's v3 weighting counts one (once, however many code points it takes), from the grammar of
/// UTS #51 and the Unicode emoji properties rather than twemoji's generated list.
///
/// Like twemoji, a pictograph counts without its variation selector (☺ as much as ☺️), except the ASCII and Latin-1
/// ones and the two twemoji also requires it on (™, ♟): `1`, `#` and `©` are text unless asked to be emoji.
enum EmojiSequence {
    /// One emoji at the start of what it's matched against.
    nonisolated(unsafe) static let regex = Regex {
        ChoiceOf {
            // Keycap: 1️⃣, and the bare 1⃣ twitter-text also takes.
            Regex {
                ScalarSet("#*0123456789")
                Optionally("\u{FE0F}")
                "\u{20E3}"
            }
            // Flag: two regional indicators.
            Repeat(count: 2) { ScalarSet("\u{1F1E6}"..."\u{1F1FF}") }
            // Subdivision flag: 🏴 and tag characters (🏴󠁧󠁢󠁳󠁣󠁴󠁿).
            Regex {
                "\u{1F3F4}"
                OneOrMore(ScalarSet("\u{E0020}"..."\u{E007E}"))
                "\u{E007F}"
            }
            // An element, or several joined (👨‍👩‍👧‍👦).
            Regex {
                element
                ZeroOrMore {
                    "\u{200D}"
                    element
                }
            }
        }
    }
    .matchingSemantics(.unicodeScalar)

    /// A pictograph with its presentation selector or skin tone, or alone.
    private static var element: Regex<Substring> {
        Regex {
            ChoiceOf {
                Regex {
                    /\p{Emoji_Modifier_Base}/
                    /\p{Emoji_Modifier}/
                }
                Regex {
                    /\p{Emoji}/
                    "\u{FE0F}"
                }
                Regex {
                    NegativeLookahead { ScalarSet("#*0123456789©®™♟") }
                    /\p{Emoji}/
                }
            }
        }
    }
}
