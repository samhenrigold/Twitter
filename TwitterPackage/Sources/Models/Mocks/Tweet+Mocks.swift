import Foundation

extension Tweet {
    package static func mock(
        id: String,
        author: User = .mockFriend,
        text: String,
        secondsAgo: TimeInterval = 60
    ) -> Tweet {
        Tweet(
            id: id,
            author: author,
            text: text,
            createdAt: Date(timeIntervalSinceNow: -secondsAgo),
            replyCount: 12,
            repostCount: 34,
            likeCount: 560,
            viewCount: 12_345
        )
    }

    /// Two photos, for the media viewer (`--mock-media`).
    package static var mockPhotos: Tweet {
        var tweet = Tweet.mock(id: "150", text: "Two pages, one fold.", secondsAgo: 300)
        tweet.media = [
            Media(
                id: "150-1",
                photoURL: URL(string: "https://picsum.photos/id/1015/1200/800")!,
                width: 1200,
                height: 800
            ),
            Media(
                id: "150-2",
                photoURL: URL(string: "https://picsum.photos/id/1016/800/1200")!,
                width: 800,
                height: 1200
            )
        ]
        return tweet
    }

    /// A video, for playback inline and in the viewer (`--mock-media`). Public samples stand in for `video.twimg.com`:
    /// Apple's HLS example as the full-screen variant with sound, a short MP4 as the inline one.
    package static var mockVideo: Tweet {
        var tweet = Tweet.mock(id: "151", text: "Tap to watch with sound.", secondsAgo: 420)
        tweet.media = [
            Media(
                id: "151-1",
                kind: .video,
                previewURL: URL(string: "https://picsum.photos/id/1018/1280/720")!,
                videoURL: URL(
                    string:
                        "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/bipbop_16x9_variant.m3u8"
                ),
                inlineVideoURL: URL(
                    string: "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/360/Big_Buck_Bunny_360_10s_1MB.mp4"),
                width: 1280,
                height: 720,
                altText: "A test pattern counting up the seconds.",
                durationMillis: 1_800_000
            )
        ]
        return tweet
    }

    /// A GIF, which Twitter serves as a silent MP4 that loops (`--mock-media`).
    package static var mockGIF: Tweet {
        var tweet = Tweet.mock(id: "152", text: "GIFs loop, silently.", secondsAgo: 480)
        let flower = URL(string: "https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4")
        tweet.media = [
            Media(
                id: "152-1",
                kind: .gif,
                previewURL: URL(string: "https://picsum.photos/id/1080/1280/720")!,
                videoURL: flower,
                inlineVideoURL: flower,
                width: 1280,
                height: 720
            )
        ]
        return tweet
    }

    package static let mocks: [Tweet] = [
        .mock(
            id: "100",
            text:
                "The Composable Architecture 1.26 is out, with first-class support for Swift 6.4. https://pointfree.co",
            secondsAgo: 120
        ),
        .mock(
            id: "101",
            author: .mock,
            text: "Unfold the phone and the timeline turns into two columns: feed on the left, thread on the right.",
            secondsAgo: 3_600
        ),
        .mock(
            id: "102",
            text: "Swipe actions now work in any scrollable container on iOS 27, not just List.",
            secondsAgo: 86_400
        )
    ]
}

extension Tweet {
    package static let mockLongText = """
        Some notes on building for a phone that unfolds into two screens.

        First, never read the screen size. Read the size of the window you were given, because on a foldable \
        that changes while the app runs and it is never the whole display.

        Second, keep state in the reducer, not in the view. When the layout flips from one column to two, \
        every view is rebuilt, and anything that lived in @State goes with it.

        Third, test it folded, unfolded, and halfway in between. #SwiftUI $AAPL
        """

    package static let mockLongPost: Tweet = {
        var tweet = Tweet.mock(id: "103", author: .mockAffiliate, text: mockLongText, secondsAgo: 7_200)
        let scalars = Array(mockLongText.unicodeScalars)
        func range(of word: String) -> Range<Int> {
            let needle = Array(word.unicodeScalars)
            let start =
                (0...(scalars.count - needle.count)).first { scalars[$0..<($0 + needle.count)].elementsEqual(needle) }
                ?? 0
            return start..<(start + needle.count)
        }
        tweet.styles = [
            TextStyleRange(range: range(of: "First"), isBold: true),
            TextStyleRange(range: range(of: "Second"), isBold: true),
            TextStyleRange(range: range(of: "Third"), isBold: true),
            TextStyleRange(range: range(of: "the window you were given"), isItalic: true)
        ]
        tweet.hashtags = ["#SwiftUI"]
        tweet.cashtags = ["$AAPL"]
        return tweet
    }()

    package static let mockCommunityNote: Tweet = {
        var tweet = Tweet.mock(
            id: "104", author: .mockGovernment, text: "The Moon is made of cheese. Confirmed. #space",
            secondsAgo: 10_800)
        tweet.hashtags = ["#space"]
        tweet.communityNote = CommunityNote(
            title: "Readers added context they thought people might want to know",
            shortTitle: "Readers added context",
            text: "Lunar samples returned by Apollo missions are made of rock, not cheese. nasa.gov/moon",
            links: ["nasa.gov/moon": URL(string: "https://www.nasa.gov/moon")!],
            footer: "Context is written by people who use Twitter, and they choose which notes appear.",
            destinationURL: URL(string: "https://x.com/i/birdwatch")
        )
        return tweet
    }()

    package static let mockPoll: Tweet = {
        var tweet = Tweet.mock(id: "105", author: .mockBusiness, text: "Which layout do you prefer?", secondsAgo: 1_800)
        tweet.poll = Poll(
            choices: [
                .init(label: "One column", count: 1_204),
                .init(label: "Two columns", count: 3_870),
                .init(label: "It depends", count: 512)
            ],
            endsAt: Date(timeIntervalSinceNow: 5 * 3_600),
            selectedChoiceIndex: 1
        )
        return tweet
    }()

    /// An open poll the viewer hasn't voted in.
    package static let mockOpenPoll: Tweet = {
        var tweet = Tweet.mock(id: "113", author: .mockFriend, text: "Tabs or spaces?", secondsAgo: 2_400)
        var poll = Poll(
            choices: [.init(label: "Tabs", count: 340), .init(label: "Spaces", count: 1_022)],
            endsAt: Date(timeIntervalSinceNow: 20 * 3_600)
        )
        poll.cardURI = "card://113"
        poll.cardName = "poll2choice_text_only"
        tweet.poll = poll
        return tweet
    }()

    package static let mockFinalPoll: Tweet = {
        var tweet = Tweet.mock(id: "106", text: "Tabs or spaces?", secondsAgo: 172_800)
        tweet.poll = Poll(
            choices: [.init(label: "Tabs", count: 410), .init(label: "Spaces", count: 1_590)],
            endsAt: Date(timeIntervalSinceNow: -86_400),
            countsAreFinal: true
        )
        return tweet
    }()

    package static let mockRestricted: Tweet = {
        var tweet = Tweet.mock(
            id: "107", author: .mockBusiness, text: "Talking with @pointfreeco about the future of Swift.",
            secondsAgo: 900)
        tweet.replyRestriction = ReplyRestriction(policy: .mentioned, ownerScreenName: "apple", viewerCanReply: false)
        return tweet
    }()

    package static let mockQuotingDeleted: Tweet = {
        var tweet = Tweet.mock(id: "108", author: .mock, text: "Wish I'd screenshotted this one.", secondsAgo: 20_000)
        tweet.quotedTombstone = Tombstone(id: "108-quote", text: "This Tweet was deleted by the Tweet author.")
        return tweet
    }()

    /// A post in Japanese, to translate.
    package static let mockJapanese: Tweet = {
        var tweet = Tweet.mock(
            id: "112", author: .mockAffiliate, text: "折りたたみのiPhoneで、タイムラインが二列になるのが最高です。",
            secondsAgo: 1_800)
        tweet.language = "ja"
        return tweet
    }()

    /// A reply in the timeline, whose thread opens with the conversation it replies to above it.
    package static let mockReply: Tweet = {
        var tweet = Tweet.mock(
            id: "110", author: .mockAffiliate, text: "Mine did too. The column view is the best part.", secondsAgo: 300)
        tweet.replyingTo = ["samhenrigold", "pointfreeco"]
        return tweet
    }()

    /// What ``mockReply`` replies to, oldest first.
    package static let mockReplyAncestors: [Tweet] = [
        mocks[0],
        {
            var tweet = Tweet.mock(
                id: "111", author: .mock, text: "Just upgraded the whole app. Everything compiles!", secondsAgo: 900)
            tweet.replyingTo = ["pointfreeco"]
            return tweet
        }()
    ]

    package static let mockReplies: [Tweet] = [
        .mock(id: "201", author: .mockFriend, text: "Congrats on the launch!", secondsAgo: 600),
        .mock(id: "202", author: .mock, text: "Thank you! More to come.", secondsAgo: 500)
    ]
}
