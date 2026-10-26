import Foundation

package struct TwitterNotification: Identifiable, Hashable, Codable, Sendable {
    package var id: String
    package var icon: String
    package var message: String
    /// Unicode-scalar ranges in `message` that Twitter renders bold (the people's names).
    package var boldRanges: [Range<Int>] = []
    package var users: [User]
    package var date: Date?
    package var tweet: Tweet?
    package var tweetID: String?
    /// Arrived since Notifications were last read.
    package var isUnread = false
}
