import Foundation

package struct Media: Identifiable, Hashable, Codable, Sendable {
    package enum Kind: String, Codable, Sendable { case photo, video, gif }
    package var id: String
    package var kind: Kind
    package var previewURL: URL
    package var videoURL: URL?
    /// A lighter variant (≤ ~2 Mbps) for muted inline autoplay.
    package var inlineVideoURL: URL?
    package var width: Double
    package var height: Double
    package var altText: String?
    package var durationMillis: Int?

    package var aspectRatio: Double { width > 0 && height > 0 ? width / height : 16 / 9 }

    package var fullSizeURL: URL {
        guard kind == .photo else { return previewURL }
        return URL(string: previewURL.absoluteString + "?name=orig") ?? previewURL
    }
}

extension Media {
    /// A photo, for images the viewer shows that aren't a post's, such as a profile's avatar.
    package init(id: String, photoURL: URL, width: Double, height: Double, altText: String? = nil) {
        self.init(id: id, kind: .photo, previewURL: photoURL, width: width, height: height, altText: altText)
    }
}
