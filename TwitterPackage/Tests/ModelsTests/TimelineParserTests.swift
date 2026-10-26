import Foundation
import Testing

@testable import Models

struct TimelineParserTests {
    @Test
    func tombstonesBecomeRowsInsteadOfBeingDropped() throws {
        let page = TimelineParser.page(
            from: try instructions([
                entry(
                    "tweet-1",
                    item: [
                        "itemType": "TimelineTweet",
                        "tweet_results": [
                            "result": [
                                "__typename": "TweetTombstone",
                                "tombstone": [
                                    "__typename": "TextTombstone",
                                    "text": ["text": "This Post was deleted by the Post author. Learn more"]
                                ]
                            ]
                        ]
                    ]),
                entry(
                    "tweet-2",
                    item: [
                        "itemType": "TimelineTweet",
                        "tweet_results": ["result": ["__typename": "TweetUnavailable", "reason": "Suspended"]]
                    ]),
                entry(
                    "tombstone-3",
                    item: [
                        "itemType": "TimelineTombstone",
                        "tombstoneInfo": ["richText": ["text": "This Post is unavailable."]]
                    ])
            ])
        )

        #expect(
            page.items == [
                .tombstone(Tombstone(id: "tweet-1", text: "This Tweet was deleted by the Tweet author.")),
                .tombstone(Tombstone(id: "tweet-2", reason: .suspended)),
                .tombstone(Tombstone(id: "tombstone-3", text: "This Tweet is unavailable."))
            ])
    }

    @Test
    func tombstonedQuoteKeepsItsText() throws {
        var result = tweetResult(id: "10", text: "Look at this")
        result["quoted_status_result"] = [
            "result": [
                "__typename": "TweetTombstone",
                "tombstone": ["text": ["text": "This post is unavailable."]]
            ]
        ]
        let tweet = try #require(TimelineParser.tweet(from: result))
        #expect(tweet.quoted.isEmpty)
        #expect(tweet.quotedTombstone?.text == "This Tweet is unavailable.")
    }

    @Test
    func communityNote() throws {
        var result = tweetResult(id: "10", text: "Big if true")
        result["birdwatch_pivot"] = [
            "title": "Readers added context they thought people might want to know",
            "shorttitle": "Readers added context",
            "destinationUrl": "https://x.com/i/birdwatch/n/99",
            "note": ["rest_id": "99"],
            "footer": ["text": "Context is written by people who use X, and they choose which notes appear."],
            "subtitle": [
                "text": "It isn't true. https://t.co/abc",
                "entities": [
                    [
                        "fromIndex": 15, "toIndex": 31,
                        "ref": ["type": "TimelineUrl", "url": "https://example.com/source"]
                    ]
                ]
            ]
        ]
        let note = try #require(TimelineParser.tweet(from: result)?.communityNote)
        #expect(note.id == "99")
        #expect(note.shortTitle == "Readers added context")
        #expect(note.text == "It isn't true. https://t.co/abc")
        #expect(note.links == [TextLink(range: 15..<31, url: URL(string: "https://example.com/source")!)])
        #expect(note.footer == "Context is written by people who use Twitter, and they choose which notes appear.")
        #expect(note.destinationURL == URL(string: "https://x.com/i/birdwatch/n/99"))
    }

    @Test
    func longPostKeepsStylesThroughURLExpansion() throws {
        // "Hi " + URL + " bold &amp; italic" — the URL shortens to its display form and &amp; decodes, both
        // before the styled ranges, so the ranges must shift.
        let noteText = "Hi https://t.co/xyz bold &amp; italic #Swift $AAPL"
        var result = tweetResult(id: "10", text: "Hi…")
        result["note_tweet"] = [
            "is_expandable": true,
            "note_tweet_results": [
                "result": [
                    "text": noteText,
                    "entity_set": [
                        "urls": [
                            [
                                "url": "https://t.co/xyz", "display_url": "a.co",
                                "expanded_url": "https://a.co/full"
                            ]
                        ],
                        "hashtags": [["text": "Swift"]],
                        "symbols": [["text": "AAPL"]]
                    ],
                    "richtext": [
                        "richtext_tags": [
                            ["from_index": 20, "to_index": 24, "richtext_types": ["Bold"]],
                            ["from_index": 31, "to_index": 37, "richtext_types": ["Italic", "Bold"]]
                        ]
                    ]
                ]
            ]
        ]
        let tweet = try #require(TimelineParser.tweet(from: result))
        #expect(tweet.text == "Hi a.co bold & italic #Swift $AAPL")
        #expect(tweet.links == [TextLink(range: 3..<7, url: URL(string: "https://a.co/full")!)])
        #expect(tweet.hashtags == ["#Swift"])
        #expect(tweet.cashtags == ["$AAPL"])
        let scalars = Array(tweet.text.unicodeScalars)
        func substring(_ range: Range<Int>) -> String {
            var view = String.UnicodeScalarView()
            view.append(contentsOf: scalars[range])
            return String(view)
        }
        #expect(tweet.styles.count == 2)
        #expect(substring(tweet.styles[0].range) == "bold")
        #expect(tweet.styles[0].isBold && !tweet.styles[0].isItalic)
        #expect(substring(tweet.styles[1].range) == "italic")
        #expect(tweet.styles[1].isBold && tweet.styles[1].isItalic)
    }

    @Test
    func legacyHashtagsAndCashtags() throws {
        var result = tweetResult(id: "10", text: "#café $BRK.A")
        var legacy = result["legacy"] as! [String: Any]
        legacy["entities"] = ["hashtags": [["text": "café"]], "symbols": [["text": "BRK.A"]]]
        result["legacy"] = legacy
        let tweet = try #require(TimelineParser.tweet(from: result))
        #expect(tweet.hashtags == ["#café"])
        #expect(tweet.cashtags == ["$BRK.A"])
    }

    @Test
    func poll() throws {
        var result = tweetResult(id: "10", text: "Which?")
        result["card"] = [
            "rest_id": "card://99",
            "legacy": [
                "name": "poll3choice_text_only",
                "binding_values": [
                    binding("choice1_label", string: "A"), binding("choice1_count", string: "10"),
                    binding("choice2_label", string: "B"), binding("choice2_count", string: "30"),
                    binding("choice3_label", string: "C"), binding("choice3_count", string: "0"),
                    binding("end_datetime_utc", string: "2024-05-01T12:00:00Z"),
                    binding("selected_choice", string: "2"),
                    ["key": "counts_are_final", "value": ["type": "BOOLEAN", "boolean_value": true]]
                ]
            ]
        ]
        let tweet = try #require(TimelineParser.tweet(from: result))
        let poll = try #require(tweet.poll)
        #expect(tweet.card == nil)
        #expect(
            poll.choices == [.init(label: "A", count: 10), .init(label: "B", count: 30), .init(label: "C", count: 0)])
        #expect(poll.totalVotes == 40)
        #expect(poll.selectedChoiceIndex == 1)
        #expect(poll.countsAreFinal)
        #expect(poll.endsAt == ISO8601DateFormatter().date(from: "2024-05-01T12:00:00Z"))
        #expect(poll.fraction(of: poll.choices[1]) == 0.75)
        #expect(poll.cardURI == "card://99")
        #expect(poll.cardName == "poll3choice_text_only")
    }

    @Test
    func badgesAndAffiliateAndBlockState() throws {
        let user = try #require(
            TimelineParser.user(from: [
                "rest_id": "1",
                "is_blue_verified": true,
                "core": ["screen_name": "apple", "name": "Apple"],
                "legacy": ["verified_type": "Business", "blocked_by": true],
                "relationship_perspectives": ["blocking": true],
                "affiliates_highlighted_label": [
                    "label": [
                        "description": "Apple",
                        "badge": ["url": "https://pbs.twimg.com/badge.jpg"],
                        "url": ["url": "https://twitter.com/apple", "urlType": "DeepLink"]
                    ]
                ]
            ]))
        #expect(user.verificationBadge == .business)
        #expect(user.isBlocking)
        #expect(user.blocksViewer)
        #expect(
            user.affiliate
                == AffiliateLabel(
                    description: "Apple", badgeURL: URL(string: "https://pbs.twimg.com/badge.jpg"),
                    url: URL(string: "https://twitter.com/apple")))

        var government = user
        government.verifiedType = "Government"
        #expect(government.verificationBadge == .government)
        var blue = user
        blue.verifiedType = nil
        #expect(blue.verificationBadge == .blue)
        blue.isVerified = false
        #expect(blue.verificationBadge == nil)
    }

    @Test
    func replyRestriction() throws {
        var result = tweetResult(id: "10", text: "Limited")
        var legacy = result["legacy"] as! [String: Any]
        legacy["conversation_control"] = [
            "policy": "ByInvitation",
            "conversation_owner_results": ["result": ["core": ["screen_name": "owner"]]]
        ]
        result["legacy"] = legacy
        result["limitedActionResults"] = [
            "limited_actions": [
                [
                    "action": "Reply",
                    "prompt": [
                        "__typename": "CtaLimitedActionPrompt",
                        "headline": ["text": "Who can reply?"],
                        "subtext": ["text": "People @owner mentioned can reply"]
                    ]
                ]
            ]
        ]
        let tweet = try #require(TimelineParser.tweet(from: result))
        let restriction = try #require(tweet.replyRestriction)
        #expect(restriction.policy == .mentioned)
        #expect(restriction.ownerScreenName == "owner")
        #expect(!restriction.viewerCanReply)
        #expect(!tweet.viewerCanReply)
        #expect(restriction.prompt == "People @owner mentioned can reply")

        result["limitedActionResults"] = nil
        legacy["conversation_control"] = ["policy": "Community"]
        result["legacy"] = legacy
        let open = try #require(TimelineParser.tweet(from: result))
        #expect(open.viewerCanReply)
        #expect(open.replyRestriction?.policy == .following)
        #expect(open.replyRestriction?.ownerScreenName == "author")
    }

    @Test
    func showMoreCursorsInsideAndBelowConversations() throws {
        let page = TimelineParser.page(
            from: try instructions([
                [
                    "entryId": "conversationthread-1",
                    "content": [
                        "entryType": "TimelineTimelineModule",
                        "displayType": "VerticalConversation",
                        "items": [
                            [
                                "entryId": "conversationthread-1-tweet-1",
                                "item": [
                                    "itemContent": [
                                        "itemType": "TimelineTweet",
                                        "tweet_results": ["result": tweetResult(id: "1", text: "one")]
                                    ]
                                ]
                            ],
                            [
                                "entryId": "conversationthread-1-tweet-2",
                                "item": [
                                    "itemContent": [
                                        "itemType": "TimelineTweet",
                                        "tweet_results": ["result": tweetResult(id: "2", text: "two")]
                                    ]
                                ]
                            ],
                            [
                                "entryId": "conversationthread-1-cursor-showmore-3",
                                "item": [
                                    "itemContent": [
                                        "itemType": "TimelineTimelineCursor",
                                        "cursorType": "ShowMore",
                                        "value": "module-cursor",
                                        "displayTreatment": ["actionText": "Show replies"]
                                    ]
                                ]
                            ]
                        ]
                    ]
                ],
                entry(
                    "cursor-showmorethreads-4",
                    item: [
                        "itemType": "TimelineTimelineCursor", "cursorType": "ShowMoreThreads",
                        "value": "threads-cursor"
                    ]),
                entry(
                    "cursor-bottom-5",
                    item: ["itemType": "TimelineTimelineCursor", "cursorType": "Bottom", "value": "bottom-cursor"])
            ])
        )

        #expect(page.bottomCursor == "bottom-cursor")
        #expect(
            page.items.map(\.id) == [
                "t-1", "t-2", "s-conversationthread-1-cursor-showmore-3", "s-cursor-showmorethreads-4"
            ])
        guard case .tweet(let first) = page.items[0], case .tweet(let second) = page.items[1] else {
            Issue.record("Expected tweets")
            return
        }
        #expect(first.connectsBelow && !first.connectsAbove)
        #expect(second.connectsAbove && !second.connectsBelow)
        #expect(
            page.items[2]
                == .showMore(
                    ShowMoreCursor(
                        id: "conversationthread-1-cursor-showmore-3", cursor: "module-cursor", label: "Show replies")))
        #expect(
            page.items[3]
                == .showMore(ShowMoreCursor(id: "cursor-showmorethreads-4", cursor: "threads-cursor")))
    }

    @Test
    func addToModuleKeepsConversationChain() throws {
        let page = TimelineParser.page(from: [
            "data": [
                "instructions": [
                    [
                        "type": "TimelineAddToModule",
                        "moduleEntryId": "conversationthread-1",
                        "moduleItems": [
                            [
                                "entryId": "conversationthread-1-tweet-7",
                                "item": [
                                    "itemContent": [
                                        "itemType": "TimelineTweet",
                                        "tweet_results": ["result": tweetResult(id: "7", text: "seven")]
                                    ]
                                ]
                            ],
                            [
                                "entryId": "conversationthread-1-tweet-8",
                                "item": [
                                    "itemContent": [
                                        "itemType": "TimelineTweet",
                                        "tweet_results": ["result": tweetResult(id: "8", text: "eight")]
                                    ]
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ])
        #expect(page.items.map(\.id) == ["t-7", "t-8"])
        guard case .tweet(let first) = page.items.first else {
            Issue.record("Expected a tweet")
            return
        }
        #expect(first.connectsBelow)
    }

    // MARK: Fixtures

    @Test
    func onlyRepliesToATweetSayReplyingTo() throws {
        // A standalone Tweet that starts with a mention: Twitter names the account, but there's no Tweet replied to.
        var mention = tweetResult(id: "20", text: "@x hey what's up")
        var legacy = mention["legacy"] as! [String: Any]
        legacy["in_reply_to_screen_name"] = "x"
        mention["legacy"] = legacy
        #expect(try #require(TimelineParser.tweet(from: mention)).replyingTo.isEmpty)

        legacy["in_reply_to_status_id_str"] = "19"
        mention["legacy"] = legacy
        #expect(try #require(TimelineParser.tweet(from: mention)).replyingTo == ["x"])
    }

    private func tweetResult(id: String, text: String) -> [String: Any] {
        [
            "__typename": "Tweet",
            "rest_id": id,
            "core": [
                "user_results": ["result": ["rest_id": "u1", "core": ["screen_name": "author", "name": "Author"]]]
            ],
            "legacy": ["full_text": text, "id_str": id]
        ]
    }

    private func entry(_ id: String, item: [String: Any]) -> [String: Any] {
        ["entryId": id, "content": ["entryType": "TimelineTimelineItem", "itemContent": item]]
    }

    private func binding(_ key: String, string: String) -> [String: Any] {
        ["key": key, "value": ["type": "STRING", "string_value": string]]
    }

    private func instructions(_ entries: [[String: Any]]) throws -> Any {
        // Round-trip through JSON so values are the Foundation types Twitter's responses decode to.
        let root: [String: Any] = ["data": ["instructions": [["type": "TimelineAddEntries", "entries": entries]]]]
        return try JSONSerialization.jsonObject(with: JSONSerialization.data(withJSONObject: root))
    }
}
