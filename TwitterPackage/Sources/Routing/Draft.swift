import Models

package struct Draft: Equatable {
    package var quoting: Tweet?
    package var replyingTo: Tweet?

    package init(quoting: Tweet? = nil, replyingTo: Tweet? = nil) {
        self.quoting = quoting
        self.replyingTo = replyingTo
    }
}
