import ComposableArchitecture
import Foundation
import Testing
import UIKit

@testable import Models
@testable import Routing
@testable import TabStackFeature
@testable import TwitterClient

@MainActor
struct TabStackControllerTests {
    /// Laid out as columns, a column the store closes lets go of its content at once, before it animates away: moved
    /// between the strip's cards on the way, its views would otherwise appear again and send actions (`.task`, rows
    /// appearing) for a screen no longer in the path.
    @Test
    func aColumnClosedByTheStoreLetsGoOfItsContent() async throws {
        let threadLoads = LockIsolated(0)
        let store = Store(initialState: TabStack.State.home) {
            TabStack()
        } withDependencies: {
            $0[TwitterClient.self].feed = { source, _ in
                if case .thread = source { threadLoads.withValue { $0 += 1 } }
                try await Task.sleep(for: .seconds(60))
                return FeedPage(items: [], bottomCursor: nil, topCursor: nil)
            }
            $0[TwitterClient.self].trends = { [] }
            $0.date.now = Date(timeIntervalSince1970: 0)
        }
        let stack = TabStackController(store: store, title: "Home")
        // Wide enough for columns. (Tests have no window scene to show it in: it's laid out by hand.)
        let navigation = stack.navigationController
        navigation.traitOverrides.horizontalSizeClass = .regular
        navigation.view.frame = CGRect(x: 0, y: 0, width: 1194, height: 834)

        store.send(.root(.feeds(.delegate(.open(.thread(Tweet.mocks[0]))))))
        let column = try await #require(
            eventually {
                navigation.view.layoutIfNeeded()
                return navigation.viewControllers.dropFirst().first as? ColumnHostingController<TabStackPathView>
            }
        )
        let id = try #require(store.path.ids.first)
        store.send(.path(.element(id: id, action: .thread(.task))))
        // Laid out as a column, and its timeline loading (the effect has started, so closing the column cancels it).
        try #require(
            await eventually {
                navigation.view.layoutIfNeeded()
                column.view.layoutIfNeeded()
                return column.isLaidOutAsColumn && threadLoads.value > 0 ? true : nil
            } == true
        )
        #expect(!column.isContentRemoved)

        store.send(.tabReselected)
        #expect(await eventually { column.isContentRemoved ? true : nil } == true)
    }

    /// Polls the main run loop until `value` isn't `nil`, for a few seconds at most.
    private func eventually<T>(_ value: () -> T?) async -> T? {
        for _ in 0..<300 {
            if let value = value() { return value }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return nil
    }
}
