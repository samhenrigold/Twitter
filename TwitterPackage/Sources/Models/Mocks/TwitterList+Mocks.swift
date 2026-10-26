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
