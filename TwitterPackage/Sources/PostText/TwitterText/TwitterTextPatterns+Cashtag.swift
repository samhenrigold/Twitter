import RegexBuilder

extension TwitterTextPatterns {
    /// `validCashtag`: `$` and a ticker (`$AAPL`, `$BRK.B`, `$TSLA_X`) at the start or after a space, ending at a space,
    /// punctuation or the end.
    struct CashtagPattern {
        let regex: Regex<AnyRegexOutput>
        let before = Reference(Substring.self)
        /// The symbol without its `$`.
        let symbol = Reference(Substring.self)

        init() {
            // The builders capture the references, not `self`, which isn't initialized yet.
            let (before, symbol) = (self.before, self.symbol)
            regex = Regex(
                Regex {
                    Capture(as: before) {
                        ChoiceOf {
                            Anchor.startOfSubject
                            spaces
                        }
                    }
                    "$"
                    Capture(as: symbol) {
                        Repeat(1...6) { asciiLetters }
                        Optionally {
                            ScalarSet("._")
                            Repeat(1...2) { asciiLetters }
                        }
                    }
                    Lookahead {
                        ChoiceOf {
                            Anchor.endOfSubject
                            /\s/
                            punctuation
                        }
                    }
                }
                .matchingSemantics(.unicodeScalar)
            )
        }
    }
}
