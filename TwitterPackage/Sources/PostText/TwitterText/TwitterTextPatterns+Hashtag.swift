import RegexBuilder

extension TwitterTextPatterns {
    /// `validHashtag`: `#` and a run of letters, marks, digits and joiners with at least one letter or mark, after a
    /// boundary that isn't part of a word or an `&` (so `C#7` and `&#39;` aren't tags).
    struct HashtagPattern {
        let regex: Regex<AnyRegexOutput>
        let before = Reference(Substring.self)
        /// The tag without its `#`.
        let tag = Reference(Substring.self)

        init() {
            // The builders capture the references, not `self`, which isn't initialized yet.
            let (before, tag) = (self.before, self.tag)
            regex = Regex(
                Regex {
                    Capture(as: before) {
                        ChoiceOf {
                            Anchor.startOfSubject
                            "\u{FE0E}"
                            "\u{FE0F}"
                            Anchor.endOfSubject
                            Regex {
                                NegativeLookahead {
                                    ChoiceOf {
                                        Self.letterOrNumber
                                        "&"
                                    }
                                }
                                ScalarSet("\u{0}"..."\u{10FFFF}")
                            }
                        }
                    }
                    hashSigns
                    // A keycap (#️⃣) isn't a tag.
                    NegativeLookahead {
                        ChoiceOf {
                            "\u{FE0F}"
                            "\u{20E3}"
                        }
                    }
                    Capture(as: tag) {
                        ZeroOrMore(Self.letterOrNumber)
                        Self.letter
                        ZeroOrMore(Self.letterOrNumber)
                    }
                }
                .ignoresCase()
                .matchingSemantics(.unicodeScalar)
            )
        }

        /// `hashtagAlpha`.
        private static var letter: Regex<Substring> { /[\p{L}\p{M}]/ }

        /// `hashtagAlphaNumeric`: letters, marks, decimal digits, and `hashtagSpecialChars` (`_`, the zero-width
        /// joiners, and punctuation that joins words in Hebrew, Japanese, Tibetan and others).
        private static var letterOrNumber: Regex<Substring> {
            Regex {
                ChoiceOf {
                    /[\p{L}\p{M}\p{Nd}]/
                    ScalarSet("_\u{200C}\u{200D}\u{A67E}\u{05BE}\u{05F3}\u{05F4}\u{00B7}")
                    ScalarSet("\u{FF5E}\u{301C}\u{309B}\u{309C}\u{30A0}\u{30FB}\u{3003}\u{0F0B}\u{0F0C}")
                }
            }
        }
    }
}
