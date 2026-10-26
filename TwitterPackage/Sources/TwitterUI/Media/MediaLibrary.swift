import Foundation
import ImagePipeline
import Models
import Photos
import UIKit

/// Saving and copying media at full size.
enum MediaLibrary {
    /// Saving needs the app's add-only Photos usage description; without it the request would crash, so the action
    /// isn't offered.
    static let canSave = Bundle.main.object(forInfoDictionaryKey: "NSPhotoLibraryAddUsageDescription") != nil

    /// The upload as a JPEG, whatever it was uploaded as.
    static func originalURL(of media: Media) -> URL {
        guard var components = URLComponents(url: media.previewURL(variant: "orig"), resolvingAgainstBaseURL: false)
        else { return media.previewURL }
        var items = (components.queryItems ?? []).filter { $0.name != "format" }
        items.append(URLQueryItem(name: "format", value: "jpg"))
        components.queryItems = items
        return components.url ?? media.previewURL
    }

    /// The video as one MP4 to download; a video that only streams (an HLS playlist) has none.
    static func videoFile(of media: Media) -> URL? {
        [media.videoURL, media.inlineVideoURL].lazy.compactMap { $0 }.first { $0.pathExtension.lowercased() == "mp4" }
    }

    /// Adds the photo, or the video (a GIF is one too), to the library, asking for add-only access the first time.
    @concurrent static func save(_ media: Media) async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return }
        do {
            switch media.kind {
            case .photo:
                let (data, _) = try await URLSession.images.data(from: originalURL(of: media))
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
                }
            case .gif, .video:
                guard let videoURL = videoFile(of: media) else { return }
                let (download, _) = try await URLSession.shared.download(from: videoURL)
                // Photos reads the type from the extension.
                let file = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).mp4")
                try FileManager.default.moveItem(at: download, to: file)
                try await PHPhotoLibrary.shared().performChanges {
                    let options = PHAssetResourceCreationOptions()
                    options.shouldMoveFile = true
                    PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: file, options: options)
                }
            }
            await UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            await UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    @concurrent static func copy(_ media: Media) async {
        guard let (data, _) = try? await URLSession.images.data(from: originalURL(of: media)),
            let image = UIImage(data: data)
        else { return }
        await MainActor.run { UIPasteboard.general.image = image }
    }
}
