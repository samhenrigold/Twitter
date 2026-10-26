import ComposableArchitecture
import Models
import Routing
import TwitterClient

/// The Lists someone made or follows. Opening one shows its timeline as a column after this one.
@Reducer
package struct ListsFeature {
    @ObservableState
    package struct State: Equatable {
        var errorMessage: String?
        var hasLoaded = false
        var isLoading = false
        var lists: IdentifiedArrayOf<TwitterList> = []
        package let userID: String

        package init(userID: String) {
            self.userID = userID
        }
    }

    package enum Action {
        case delegate(ContentDelegate)
        case listTapped(TwitterList)
        case pageResponse(Result<ListPage, any Error>)
        case refreshPulled
        case retryButtonTapped
        case task
    }

    @Dependency(TwitterClient.self) var client

    package init() {}

    package var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .delegate:
                return .none

            case .listTapped(let list):
                return .send(.delegate(.open(.list(list))))

            case .pageResponse(.success(let page)):
                state.isLoading = false
                state.hasLoaded = true
                state.errorMessage = nil
                state.lists = IdentifiedArray(page.lists, uniquingIDsWith: { first, _ in first })
                return .none

            case .pageResponse(.failure(let error)):
                state.isLoading = false
                state.hasLoaded = true
                state.errorMessage = error.localizedDescription
                return .none

            case .refreshPulled, .retryButtonTapped:
                return load(&state)

            case .task:
                guard !state.hasLoaded, !state.isLoading else { return .none }
                return load(&state)
            }
        }
    }

    private func load(_ state: inout State) -> Effect<Action> {
        state.isLoading = true
        return .run { [userID = state.userID] send in
            await send(.pageResponse(Result { try await client.lists(userID, nil) }))
        }
    }
}
