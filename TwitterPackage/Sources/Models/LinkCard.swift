import Foundation

package struct LinkCard: Hashable, Codable, Sendable {
    package var title: String
    package var domain: String
    package var url: URL
    package var imageURL: URL?
}
