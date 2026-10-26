import Foundation
import Models

extension Tweet {
    /// The address of one of this post's photos or videos, as Twitter links them: `…/status/1/photo/2`.
    package func mediaURL(of item: Media) -> URL? {
        guard let index = media.firstIndex(where: { $0.id == item.id }) else { return nil }
        return url.appending(path: "\(item.kind == .photo ? "photo" : "video")/\(index + 1)")
    }
}
