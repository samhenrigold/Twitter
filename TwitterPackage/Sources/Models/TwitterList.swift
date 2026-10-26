/// A Twitter List: a timeline of the accounts someone put on it.
package struct TwitterList: Identifiable, Hashable, Codable, Sendable {
    package var id: String
    package var name: String
    package var description: String = ""
    package var memberCount = 0
    package var subscriberCount = 0
    package var isPrivate = false
    /// Who made it.
    package var owner: User?

    package init(
        id: String, name: String, description: String = "", memberCount: Int = 0, subscriberCount: Int = 0,
        isPrivate: Bool = false, owner: User? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.memberCount = memberCount
        self.subscriberCount = subscriberCount
        self.isPrivate = isPrivate
        self.owner = owner
    }
}
