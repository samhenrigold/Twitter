import PhotosUI
import SwiftUI
import TwitterClient

extension MediaUpload {
    /// Loads picked library items for upload: photos as JPEG, GIFs and videos as they are. Items that fail to load are
    /// left out.
    static func load(_ items: [PhotosPickerItem]) async -> [MediaUpload] {
        var uploads: [MediaUpload] = []
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let types = item.supportedContentTypes
            if types.contains(where: { $0.conforms(to: .movie) }) {
                uploads.append(MediaUpload(data: data, mimeType: "video/mp4"))
            } else if types.contains(where: { $0.conforms(to: .gif) }) {
                uploads.append(MediaUpload(data: data, mimeType: "image/gif"))
            } else if let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.9) {
                uploads.append(MediaUpload(data: jpeg, mimeType: "image/jpeg"))
            }
        }
        return uploads
    }
}
