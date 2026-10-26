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
