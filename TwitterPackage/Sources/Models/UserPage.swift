/// One page of a user list, and the cursor for the next.
package struct UserPage: Sendable {
    package var users: [User]
    package var bottomCursor: String?

    package init(users: [User], bottomCursor: String?) {
        self.users = users
        self.bottomCursor = bottomCursor
    }
}
