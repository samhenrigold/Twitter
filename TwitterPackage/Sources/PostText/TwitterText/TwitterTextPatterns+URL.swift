import RegexBuilder

extension TwitterTextPatterns {
    /// `extractUrl`: a URL, with or without its scheme, and the character before it.
    struct URLPattern {
        let regex: Regex<AnyRegexOutput>
        let before = Reference(Substring.self)
        let url = Reference(Substring.self)
        /// `http://`, `https://`, or empty.
        let scheme = Reference(Substring.self)
        let domain = Reference(Substring.self)
        /// From the first `/` after the domain, or empty.
        let path = Reference(Substring.self)

        /// `validTcoUrl`: a t.co link, which ends at its slug and query whatever follows.
        let shortLink: Regex<AnyRegexOutput>
        let slug = Reference(Substring.self)

        /// `validAsciiDomain`: the ASCII domains within a domain, which is all of a URL without a scheme that links.
        let asciiDomain: Regex<Substring>

        init() {
            // The builders capture the references, not `self`, which isn't initialized yet.
            let (before, url, scheme, domain, path, slug) = (
                self.before, self.url, self.scheme, self.domain, self.path, self.slug
            )
            regex = Regex(
                Regex {
                    Capture(as: before) {
                        ChoiceOf {
                            Self.precedingCharacter
                            Anchor.startOfSubject
                        }
                    }
                    Capture(as: url) {
                        Capture(as: scheme) { Optionally { Self.scheme } }
                        Capture(as: domain) { Self.domain }
                        Optionally { Self.port }
                        Capture(as: path) { Optionally { Self.path } }
                        Optionally { Self.query }
                    }
                }
                .ignoresCase()
                .matchingSemantics(.unicodeScalar)
            )
            shortLink = Regex(
                Regex {
                    Anchor.startOfSubject
                    Self.scheme
                    "t.co/"
                    Capture(as: slug) { OneOrMore(asciiAlphanumerics) }
                    Optionally { Self.query }
                }
                .ignoresCase()
                .matchingSemantics(.unicodeScalar)
            )
            asciiDomain = Regex {
                OneOrMore {
                    OneOrMore(asciiAlphanumerics.union(latinAccents).union(ScalarSet("-")))
                    "."
                }
                Self.topLevelDomain
            }
            .ignoresCase()
            .matchingSemantics(.unicodeScalar)
        }

        /// `validUrlPrecedingChars`: anything but a letter, digit, `@`, `$` or `#` (or a character a Tweet can't hold).
        private static let precedingCharacter = asciiAlphanumerics.union(ScalarSet("@＠$#＃")).union(invalidCharacters)
            .inverted

        private static var scheme: Regex<Substring> {
            Regex {
                "http"
                Optionally("s")
                "://"
            }
        }

        /// `validPortNumber`, after its colon.
        private static var port: Regex<Substring> {
            Regex {
                ":"
                OneOrMore(asciiDigits)
            }
        }

        /// The path: a `/` and its segments.
        private static var path: Regex<Substring> {
            Regex {
                "/"
                ZeroOrMore { pathSegment }
            }
        }

        /// `validDomainChars`: anything but punctuation, spaces, controls and directional marks.
        static let domainCharacter = punctuation.union(spaces).union(controlCharacters).union(invalidCharacters)
            .union(directionalMarks).inverted

        /// `validDomain`: subdomains (which may hold `_`), a name (which may hold `-`), and a known TLD.
        private static var domain: Regex<Substring> {
            Regex {
                ZeroOrMore { label(joinedBy: "_-") }
                label(joinedBy: "-")
                topLevelDomain
            }
        }

        /// `validSubdomain` and `validDomainName`: a label and its dot. A label starts and ends with a domain character
        /// and may join them with `joiners` inside. Matched atomically: its end is fixed by the dot that must follow.
        private static func label(joinedBy joiners: String) -> Regex<Substring> {
            Regex {
                Local {
                    domainCharacter
                    ZeroOrMore {
                        ZeroOrMore(ScalarSet(joiners))
                        domainCharacter
                    }
                }
                "."
            }
        }

        /// `validGTLD`, `validCCTLD` and `validPunycode`.
        static var topLevelDomain: Regex<Substring> {
            Regex {
                ChoiceOf {
                    TopLevelDomain()
                    Regex {
                        "xn--"
                        OneOrMore(asciiAlphanumerics.union(ScalarSet("-")))
                    }
                }
            }
        }

        /// `validUrlPath`: path characters ending in one that can end a URL, or an `@name/` segment. Parentheses
        /// count when balanced, two levels deep (Wikipedia's `/Primer_(film)`).
        private static var pathSegment: Regex<Substring> {
            Regex {
                ChoiceOf {
                    Regex {
                        ZeroOrMore(pathCharacter)
                        ZeroOrMore {
                            balancedParentheses
                            ZeroOrMore(pathCharacter)
                        }
                        ChoiceOf {
                            pathEndingCharacter
                            balancedParentheses
                        }
                    }
                    Regex {
                        "@"
                        OneOrMore(pathCharacter)
                        "/"
                    }
                }
            }
        }

        /// `validUrlBalancedParens`.
        private static var balancedParentheses: Regex<Substring> {
            Regex {
                "("
                ChoiceOf {
                    OneOrMore(pathCharacter)
                    Regex {
                        ZeroOrMore(pathCharacter)
                        "("
                        OneOrMore(pathCharacter)
                        ")"
                        ZeroOrMore(pathCharacter)
                    }
                }
                ")"
            }
        }

        /// `validUrlQueryChars` ending in one of `validUrlQueryEndingChars`, after a `?`.
        private static var query: Regex<Substring> {
            Regex {
                "?"
                ZeroOrMore(asciiAlphanumerics.union(ScalarSet("!?*'@();:&=+$/%#[]-_.,~|")))
                asciiAlphanumerics.union(ScalarSet("-_&=#/"))
            }
        }

        /// `validGeneralUrlPathChars`.
        private static let pathCharacter = asciiAlphanumerics.union(cyrillic).union(latinAccents)
            .union(ScalarSet("!*';:=+,.$/%#[]-\u{2013}_~@|&"))

        /// `validUrlPathEndingChars`, less the balanced parentheses: a URL's last character isn't sentence punctuation.
        private static let pathEndingCharacter = asciiAlphanumerics.union(cyrillic).union(latinAccents)
            .union(ScalarSet("+-=_#/"))
    }
}
