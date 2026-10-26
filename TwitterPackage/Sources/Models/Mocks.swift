import Foundation

extension User {
    package static let mock = User(
        id: "1",
        name: "Sam Henri Gold",
        screenName: "samhenrigold",
        avatarURL: nil,
        bio: "Building a Twitter client for the iPhone Duo.",
        location: "Brooklyn",
        followersCount: 4_210,
        followingCount: 512,
        postsCount: 9_876,
        isVerified: true,
        joined: Date(timeIntervalSince1970: 1_230_000_000)
    )

    package static let mockFriend = User(
        id: "2",
        name: "Point-Free",
        screenName: "pointfreeco",
        bio: "A video series exploring advanced programming topics in Swift.",
        followersCount: 31_000,
        followingCount: 12,
        postsCount: 4_000,
        isFollowing: true
    )
}

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

extension User {
    package static let mockBusiness = User(
        id: "3",
        name: "Apple",
        screenName: "apple",
        followersCount: 9_800_000,
        isVerified: true,
        verifiedType: "Business"
    )

    package static let mockGovernment = User(
        id: "4",
        name: "NASA",
        screenName: "nasa",
        followersCount: 88_000_000,
        isVerified: true,
        verifiedType: "Government"
    )

    package static let mockAffiliate = User(
        id: "5",
        name: "Tim Cook",
        screenName: "tim_cook",
        followersCount: 14_000_000,
        isVerified: true,
        affiliate: AffiliateLabel(description: "Apple", url: URL(string: "https://x.com/apple"))
    )

    package static let mockBlocked = User(
        id: "6",
        name: "Reply Guy",
        screenName: "replyguy",
        bio: "Well, actually…",
        followersCount: 12,
        followingCount: 4_800,
        isBlocking: true
    )

    package static let mockBlockedBy = User(
        id: "7",
        name: "Not a Fan",
        screenName: "notafan",
        followersCount: 300,
        blocksViewer: true
    )

    package static let mocks: [User] = [
        .mock, .mockFriend, .mockBusiness, .mockGovernment, .mockAffiliate, .mockBlocked, .mockBlockedBy
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

extension FeedPage {
    package static let mockShowMoreCursor = "mock-show-more"
    /// The rest of ``Tweet/mockReply``'s conversation, above what its thread first sends.
    package static let mockEarlierCursor = "mock-earlier"

    package static func mock(_ source: FeedSource) -> FeedPage {
        mock(source, cursor: nil)
    }

    package static func mock(_ source: FeedSource, cursor: String?) -> FeedPage {
        func item(_ tweet: Tweet) -> FeedItem { .tweet(FeedTweet(id: tweet.id, tweet: tweet)) }
        if cursor == mockShowMoreCursor {
            return FeedPage(
                items: [
                    .tweet(
                        FeedTweet(id: "203", tweet: .mock(id: "203", text: "Late to the party, but this is great."))),
                    .tombstone(Tombstone(id: "tweet-204", text: "This Tweet is unavailable."))
                ],
                bottomCursor: nil,
                topCursor: nil
            )
        }
        if cursor == mockEarlierCursor {
            return FeedPage(items: Tweet.mockReplyAncestors.dropLast().map(item), bottomCursor: nil, topCursor: nil)
        }
        if case .thread(let tweetID) = source {
            // The opened post is the thread's focus, so mock threads show it focused like real ones.
            let focused = (Tweet.mocks + [.mockRestricted, .mockReply]).first { $0.id == tweetID } ?? .mockRestricted
            var replies = Tweet.mockReplies.map { FeedTweet(id: $0.id, tweet: $0) }
            replies[0].connectsBelow = true
            replies[1].connectsAbove = true
            // A reply's thread starts with the conversation above it: like a long conversation, only the nearest of
            // it, with a cursor for the rest.
            let ancestors = tweetID == Tweet.mockReply.id ? Array(Tweet.mockReplyAncestors.suffix(1)) : []
            return FeedPage(
                items: ancestors.map(item) + [
                    item(focused),
                    .tweet(replies[0]),
                    .tweet(replies[1]),
                    .tombstone(Tombstone(id: "tweet-209", text: "This Tweet was hidden by the Tweet author.")),
                    .showMore(ShowMoreCursor(id: "cursor-showmorethreads-1", cursor: mockShowMoreCursor))
                ],
                bottomCursor: nil,
                topCursor: ancestors.isEmpty ? nil : mockEarlierCursor
            )
        }
        if source == .notifications(.all) {
            // What arrived since they were last read is marked unread, as Twitter marks it.
            let users = Array(User.mockCrowd.prefix(3))
            let notifications = [
                TwitterNotification(
                    id: "n1", icon: "heart_icon", message: "\(users[0].name) and 2 others liked your Tweet",
                    boldRanges: [0..<users[0].name.unicodeScalars.count], users: users,
                    date: .now.addingTimeInterval(-300),
                    tweet: Tweet.mocks[0], tweetID: Tweet.mocks[0].id, isUnread: true),
                TwitterNotification(
                    id: "n2", icon: "person_icon", message: "\(users[1].name) followed you",
                    boldRanges: [0..<users[1].name.unicodeScalars.count], users: [users[1]],
                    date: .now.addingTimeInterval(-7200))
            ]
            var mention = FeedTweet(id: Tweet.mockReply.id, tweet: .mockReply)
            mention.isUnread = true
            return FeedPage(
                items: [.tweet(mention)] + notifications.map(FeedItem.notification), bottomCursor: nil,
                topCursor: "mock-top")
        }
        if case .searchMedia = source {
            // A search's photos and videos: only posts with media.
            return FeedPage(items: [item(.mockPhotos)], bottomCursor: nil, topCursor: nil)
        }
        if case .search(let query, _) = source, query.hasPrefix(FeedSource.quotesQueryPrefix) {
            // Quotes of the post the search names, as a post's Quotes list shows them.
            let quotedID = String(query.dropFirst(FeedSource.quotesQueryPrefix.count))
            let quoted = (Tweet.mocks + [.mockRestricted]).first { $0.id == quotedID } ?? Tweet.mocks[0]
            let quotes = zip(User.mockCrowd.prefix(3), ["This is the one.", "Finally!", "Saving this for later."])
            return FeedPage(
                items: quotes.enumerated().map { index, quote in
                    var tweet = Tweet.mock(
                        id: "q\(index)-\(quotedID)", author: quote.0, text: quote.1, secondsAgo: Double(index + 1) * 900
                    )
                    tweet.quoted = [quoted]
                    return item(tweet)
                },
                bottomCursor: nil,
                topCursor: nil
            )
        }
        var items = Tweet.mocks.map(item)
        items.insert(item(.mockLongPost), at: 1)
        items.insert(item(.mockPoll), at: 2)
        items.insert(item(.mockReply), at: 3)
        items.insert(item(.mockJapanese), at: 4)
        items.insert(item(.mockOpenPoll), at: 5)
        items.insert(.tombstone(Tombstone(id: "tweet-109", text: "This Tweet was deleted by the Tweet author.")), at: 6)
        items += [item(.mockCommunityNote), item(.mockRestricted), item(.mockQuotingDeleted), item(.mockFinalPoll)]
        // `--mock-media`: photos to open in the viewer, kept out of the default set so snapshots stay put.
        if ProcessInfo.processInfo.arguments.contains("--mock-media") {
            items.insert(item(.mockPhotos), at: 0)
        }
        return FeedPage(items: items, bottomCursor: nil, topCursor: nil)
    }
}

extension User {
    /// Enough accounts for a user list to page once: `UserPage.mock` serves them `UserPage.mockPageSize` at a time.
    package static let mockCrowd: [User] = {
        let people: [(name: String, screenName: String, bio: String)] = [
            ("Loren Brichter", "lorenb", "Made Tweetie. Pull to refresh was my fault."),
            ("Craig Hockenberry", "chockenberry", "Iconfactory. Twitterrific since 2007."),
            ("Mike Rundle", "flyosity", "Designer and developer. Pixels, mostly."),
            ("Becky Hansmeyer", "bhansmeyer", "Indie iOS developer."),
            ("Brandon Williams", "mbrandonw", "Point-Free co-host. Composable things."),
            ("Stephen Celis", "stephencelis", "Point-Free co-host."),
            ("Marco Arment", "marcoarment", "Overcast. ATP. Coffee."),
            ("Federico Viticci", "viticci", "MacStories. iPad everything."),
            ("John Gruber", "gruber", "Daring Fireball."),
            ("Sebastiaan de With", "sdw", "Halide. Kino. Icons."),
            ("Neven Mrgan", "mrgan", "Designer at Panic. Puns available on request."),
            ("Cabel Sasser", "cabel", "Panic co-founder. Playdate."),
            ("Steve Troughton-Smith", "stroughtonsmith", "Apps on every platform there is."),
            ("Jordan Morgan", "jordanmorgan10", "Spend Stack. Swift and SwiftUI."),
            ("Natalia Panferova", "natpanferova", "SwiftUI books and talks."),
            ("Majid Jabrayilov", "mecid", "Writing about Swift and SwiftUI weekly."),
            ("Paul Hudson", "twostraws", "Hacking with Swift."),
            ("Donny Wals", "donnywals", "Swift concurrency, Core Data, and books."),
            ("Antoine van der Lee", "twannl", "SwiftLee. RocketSim."),
            ("Kaya Thomas", "kthomas901", "Engineer. We Read Too."),
            ("James Thomson", "jamesthomson", "PCalc. Dice by PCalc."),
            ("Rosyna Keller", "rosyna", "Bugs, mostly."),
            ("Ish ShaBazz", "ishabazz", "Indie developer."),
            ("Casey Liss", "caseyliss", "Callsheet. ATP.")
        ]
        return people.enumerated().map { index, person in
            User(
                id: "\(1_000 + index)",
                name: person.name,
                screenName: person.screenName,
                bio: person.bio,
                followersCount: 1_000 * (index + 3),
                followingCount: 100 + index * 7,
                isVerified: index.isMultiple(of: 5),
                isFollowing: index.isMultiple(of: 3),
                followsViewer: index.isMultiple(of: 4)
            )
        }
    }()
}

extension UserPage {
    package static let mockPageSize = 12

    /// `User.mockCrowd`, a page at a time, with Point-Free first so a list always starts with an account the viewer
    /// follows. Lists of who liked or reposted a post are shorter than lists of followers.
    package static func mock(_ source: UserListSource, cursor: String?) -> UserPage {
        var everyone = [User.mockFriend, .mockBusiness, .mockGovernment] + User.mockCrowd
        switch source {
        case .followers, .following: break
        case .likers, .reposters: everyone = Array(everyone.prefix(8))
        case .searchPeople(let query):
            // Whoever's name or handle has the query in it, as a people search finds them.
            everyone = everyone.filter {
                $0.name.localizedCaseInsensitiveContains(query) || $0.screenName.localizedCaseInsensitiveContains(query)
            }
        }
        let start = cursor.flatMap(Int.init) ?? 0
        let end = min(start + mockPageSize, everyone.count)
        guard start < end else { return UserPage(users: [], bottomCursor: nil) }
        return UserPage(users: Array(everyone[start..<end]), bottomCursor: end < everyone.count ? "\(end)" : nil)
    }
}

extension TwitterList {
    package static let mocks: [TwitterList] = [
        TwitterList(
            id: "l1", name: "Swift", description: "People building with Swift.", memberCount: 48,
            subscriberCount: 1_204,
            owner: .mock),
        TwitterList(
            id: "l2", name: "Design", description: "Interface designers worth following.", memberCount: 31,
            subscriberCount: 302, owner: .mock),
        TwitterList(id: "l3", name: "Friends", memberCount: 12, isPrivate: true, owner: .mock)
    ]
}

extension ListPage {
    package static let mock = ListPage(lists: TwitterList.mocks, bottomCursor: nil)
}

extension Trend {
    package static let mocks: [Trend] = [
        Trend(name: "#WWDC", context: "Trending in Technology", volume: "52.1K Tweets"),
        Trend(name: "iPhone Duo", context: "Technology · Trending", volume: "18.7K Tweets"),
        Trend(name: "Swift 6.4", context: "Trending in Programming"),
        Trend(name: "Point-Free", context: "Trending in United States", volume: "2,140 Tweets"),
        Trend(name: "#TCA", context: "Programming · Trending")
    ]
}
