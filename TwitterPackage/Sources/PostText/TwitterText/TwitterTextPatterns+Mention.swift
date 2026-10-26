import RegexBuilder

extension TwitterTextPatterns {
    /// `validMentionOrList`: `@name` or `@name/list`, and what's before it; and `validReply`, a mention leading the
    /// text.
    struct MentionPattern {
        let regex: Regex<AnyRegexOutput>
        let before = Reference(Substring.self)
        let screenName = Reference(Substring.self)
        /// `/slug`, or empty.
        let list = Reference(Substring.self)

        let reply: Regex<AnyRegexOutput>
        let replyScreenName = Reference(Substring.self)

        init() {
            // The builders capture the references, not `self`, which isn't initialized yet.
            let (before, screenName, list, replyScreenName) = (
                self.before, self.screenName, self.list, self.replyScreenName
            )
            regex = Regex(
                Regex {
                    Capture(as: before) {
                        ChoiceOf {
                            Anchor.startOfSubject
                            asciiAlphanumerics.union(ScalarSet("_!#$%&*@＠")).inverted
                            // A retweet's "RT @name" or "RT:@name".
                            Regex {
                                ChoiceOf {
                                    Anchor.startOfSubject
                                    asciiAlphanumerics.union(ScalarSet("_+~.-")).inverted
                                }
                                ChoiceOf {
                                    "rt"
                                    "RT"
                                    "rT"
                                    "Rt"
                                }
                                Optionally(":")
                            }
                        }
                    }
                    atSigns
                    Capture(as: screenName) { Self.screenName }
                    Capture(as: list) {
                        Optionally {
                            "/"
                            asciiLetters
                            Repeat(0...24) { asciiAlphanumerics.union(ScalarSet("_-")) }
                        }
                    }
                }
                .matchingSemantics(.unicodeScalar)
            )
            reply = Regex(
                Regex {
                    Anchor.startOfSubject
                    ZeroOrMore(spaces)
                    atSigns
                    Capture(as: replyScreenName) { Self.screenName }
                }
                .matchingSemantics(.unicodeScalar)
            )
        }

        /// Up to 20 of `[A-Za-z0-9_]`: longer than any account's name (15), as twitter-text allows.
        private static var screenName: Regex<Substring> {
            Regex { Repeat(1...20) { mentionNameCharacters } }
        }
    }
}
