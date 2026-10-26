import Foundation
import Models

extension User {
    /// The avatar as uploaded, without a size suffix, as a photo for the viewer.
    package var avatarMedia: Media? {
        guard let avatarURL,
            let original = URL(string: avatarURL.absoluteString.replacingOccurrences(of: "_normal.", with: "."))
        else { return nil }
        return Media(
            id: "avatar-\(id)", photoURL: original, width: 400, height: 400,
            altText: String(localized: "\(name)'s profile photo"))
    }

    /// The header photo at its largest size (1500×500), as a photo for the viewer.
    package var bannerMedia: Media? {
        bannerURL.map {
            Media(
                id: "banner-\(id)", photoURL: $0, width: 1500, height: 500,
                altText: String(localized: "\(name)'s header photo"))
        }
    }
}
