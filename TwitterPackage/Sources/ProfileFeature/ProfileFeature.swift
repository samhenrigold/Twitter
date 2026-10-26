import ComposableArchitecture
import FeedFeature
import Models
import Routing
import TwitterClient
import TwitterDatabase
import TwitterUI

@Reducer
package struct ProfileFeature {
    @ObservableState
    package struct State: Equatable {
        var errorMessage: String?
        var feeds: FeedsFeature.State?
        var hasFetchedUser = false
        /// The user is being fetched: a view appearing again meanwhile doesn't fetch it twice.
        var isFetchingUser = false
        var isViewer = false
        /// The viewer asked to see the posts of someone they blocked.
        var isShowingBlockedPosts = false
        var isShowingSettings = false
        package let screenName: String
        var user: User?

        package init(user: User, isViewer: Bool = false) {
            screenName = user.screenName
            self.isViewer = isViewer
            self.user = user
            feeds = Self.feeds(for: user, isViewer: isViewer)
        }

        package init(screenName: String) {
            self.screenName = screenName
        }

        static func feeds(for user: User, isViewer: Bool) -> FeedsFeature.State {
            var sources: [FeedSource] = [
                .userPosts(userID: user.id), .userReplies(userID: user.id), .userMedia(userID: user.id)
            ]
            if isViewer { sources.append(.userLikes(userID: user.id)) }
            return FeedsFeature.State(sources: sources)
        }
    }

    package enum Action {
        case blockButtonTapped
        /// Carries the value to restore, so a failure that lands after another tap can't flip the wrong way.
        case blockFailed(isBlocking: Bool)
        case muteButtonTapped
        case muteFailed(isMuting: Bool)
        case cachedUserLoaded(User)
        case delegate(ContentDelegate)
        case feeds(FeedsFeature.Action)
        case followButtonTapped
        case listsButtonTapped
        case followFailed(isFollowing: Bool)
        case followersButtonTapped
        case followingButtonTapped
        case signOutButtonTapped
        case settingsButtonTapped
        case settingsDismissed
        case task
        case userResponse(Result<User, any Error>)
        case viewPostsButtonTapped
    }

    @Dependency(TwitterClient.self) var client
    @Dependency(TimelineCache.self) var timelineCache

    package init() {}

    package var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .blockButtonTapped:
                guard var user = state.user else { return .none }
                user.isBlocking.toggle()
                state.user = user
                state.isShowingBlockedPosts = false
                return .run { [user] _ in
                    try await client.setBlocking(user.isBlocking, user.id)
                } catch: { [user] _, send in
                    await send(.blockFailed(isBlocking: !user.isBlocking))
                }

            case .blockFailed(let isBlocking):
                state.user?.isBlocking = isBlocking
                return .none

            case .muteButtonTapped:
                guard var user = state.user else { return .none }
                user.isMuting.toggle()
                state.user = user
                return .run { [user] _ in
                    try await client.setMuting(user.isMuting, user.id)
                } catch: { [user] _, send in
                    await send(.muteFailed(isMuting: !user.isMuting))
                }

            case .muteFailed(let isMuting):
                state.user?.isMuting = isMuting
                return .none

            case .viewPostsButtonTapped:
                state.isShowingBlockedPosts = true
                return .none

            case .cachedUserLoaded(let user):
                // A profile opened by handle draws its header from the last visit until the network answers.
                guard state.user == nil else { return .none }
                state.user = user
                state.feeds = State.feeds(for: user, isViewer: state.isViewer)
                return .none

            case .delegate:
                return .none

            case .feeds(.delegate(let delegate)):
                return .send(.delegate(delegate))

            case .feeds:
                return .none

            case .followButtonTapped:
                guard var user = state.user else { return .none }
                user.isFollowing.toggle()
                user.followersCount += user.isFollowing ? 1 : -1
                state.user = user
                return .run { [user] _ in
                    try await client.setFollowing(user.isFollowing, user.id)
                } catch: { [user] _, send in
                    await send(.followFailed(isFollowing: !user.isFollowing))
                }

            case .followFailed(let isFollowing):
                guard var user = state.user, user.isFollowing != isFollowing else { return .none }
                user.isFollowing = isFollowing
                user.followersCount += isFollowing ? 1 : -1
                state.user = user
                return .none

            case .followersButtonTapped:
                guard let user = state.user else { return .none }
                return .send(.delegate(.open(.userList(.followers(userID: user.id)))))

            case .followingButtonTapped:
                guard let user = state.user else { return .none }
                return .send(.delegate(.open(.userList(.following(userID: user.id)))))

            case .listsButtonTapped:
                guard let user = state.user else { return .none }
                return .send(.delegate(.open(.lists(userID: user.id))))

            case .settingsButtonTapped:
                state.isShowingSettings = true
                return .none

            case .settingsDismissed:
                state.isShowingSettings = false
                return .none

            case .signOutButtonTapped:
                return .send(.delegate(.signOut))

            case .task:
                guard !state.hasFetchedUser, !state.isFetchingUser else { return .none }
                state.isFetchingUser = true
                let screenName = state.screenName
                let readsCache = state.user == nil
                return .run { send in
                    if readsCache, let cached = try? await timelineCache.user(screenName) {
                        await send(.cachedUserLoaded(cached))
                    }
                    await send(.userResponse(Result { try await client.user(screenName) }))
                }

            case .userResponse(.success(let user)):
                state.isFetchingUser = false
                state.errorMessage = nil
                state.hasFetchedUser = true
                state.user = user
                if state.feeds == nil {
                    state.feeds = State.feeds(for: user, isViewer: state.isViewer)
                }
                return .run { _ in
                    await withErrorReporting { try await timelineCache.saveUser(user) }
                }

            case .userResponse(.failure(let error)):
                state.isFetchingUser = false
                if state.user == nil {
                    state.errorMessage = error.localizedDescription
                }
                return .none
            }
        }
        .ifLet(\.feeds, action: \.feeds) {
            FeedsFeature()
        }
    }
}
