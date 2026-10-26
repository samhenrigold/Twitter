import Foundation
import PostText
import Routing

struct EntityTarget: Equatable {
    /// Its segment, which tells apart two mentions of the same account.
    let index: Int
    let entity: PostEntity
    let rects: [CGRect]

    /// Where a tap goes.
    var url: URL? { entity.destination }

    /// The account it previews: a mention, or a link to a profile.
    var screenName: String? {
        switch entity {
        case .mention(let screenName):
            return screenName
        case .url(let url):
            if case .profileHandle(let screenName) = Route(url: url) { return screenName }
            return nil
        case .hashtag, .cashtag:
            return nil
        }
    }

    /// Its page on Twitter, to copy or share.
    var webURL: URL? {
        switch entity {
        case .mention(let screenName):
            return URL(string: "https://x.com/\(screenName)")
        case .hashtag(let tag):
            var components = URLComponents(string: "https://x.com/hashtag")
            components?.path += "/\(tag.trimmingPrefix("#"))"
            return components?.url
        case .cashtag(let tag):
            var components = URLComponents(string: "https://x.com/search")
            components?.queryItems = [URLQueryItem(name: "q", value: tag)]
            return components?.url
        case .url(let url):
            return url
        }
    }

    /// In-app destinations open in a window of their own; web links open in a web panel window.
    var route: Route? { url.flatMap(Route.forLink) }
}
