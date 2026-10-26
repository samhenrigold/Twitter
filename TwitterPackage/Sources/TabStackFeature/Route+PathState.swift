import FeedFeature
import ListsFeature
import Models
import ProfileFeature
import Routing
import SearchFeature
import UserListFeature
import WebFeature

extension Route {
    package var pathState: TabStackPath.State {
        switch self {
        case .list(let list):
            .list(FeedFeature.State(source: .list(id: list.id, name: list.name)))
        case .lists(let userID):
            .lists(ListsFeature.State(userID: userID))
        case .profile(let user):
            .profile(ProfileFeature.State(user: user))
        case .profileHandle(let screenName):
            .profile(ProfileFeature.State(screenName: screenName))
        case .quotes(let tweetID):
            .quotes(FeedFeature.State(source: .quotes(of: tweetID)))
        case .search(let query):
            .search(SearchFeature.State(submitting: query))
        case .thread(let tweet):
            .thread(.thread(opening: tweet))
        case .threadID(let id):
            .thread(FeedFeature.State(source: .thread(tweetID: id)))
        case .userList(let source):
            .userList(UserListFeature.State(source: source))
        case .web(let url):
            .web(WebFeature.State(url: url))
        }
    }
}
