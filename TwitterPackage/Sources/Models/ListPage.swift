/// One page of lists, and the cursor for the next.
package struct ListPage: Sendable {
    package var lists: [TwitterList]
    package var bottomCursor: String?

    package init(lists: [TwitterList], bottomCursor: String?) {
        self.lists = lists
        self.bottomCursor = bottomCursor
    }
}
