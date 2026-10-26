import ComposableArchitecture
import DependenciesTestSupport
import SnapshotTesting
import SwiftUI
import Testing

@testable import FeedFeature
@testable import ImagePipeline
@testable import MainFeature
@testable import Models
@testable import ProfileFeature
@testable import TabStackFeature
@testable import TwitterClient
@testable import TwitterDatabase
@testable import TwitterUI

/// Renders the main screens with canned data at iPhone Duo's sizes, for reviewing layout and polish. Delete
/// `__Snapshots__` and run to re-record after an intentional visual change.
@MainActor
@Suite(
    .dependencies {
        $0[TwitterClient.self] = .previewValue
        $0[TimelineCache.self] = .previewValue
        $0[ImageLoader.self] = ImageLoader(cached: { _ in nil }, image: { _ in nil }, prefetch: { _ in })
    }
)
struct DuoSnapshotTests {
    init() {
        TwitterFont.register()
    }

    @Test(arguments: Pose.allCases, Appearance.allCases)
    func homeTimeline(pose: Pose, appearance: Appearance) async {
        let view = TabStackView(store: Store(initialState: .loadedHome) { TabStack() }, title: "Home")
        await assertDuoSnapshot(of: view, pose: pose, appearance: appearance)
    }

    @Test(arguments: Pose.allCases, Appearance.allCases)
    func threadOpenFromHome(pose: Pose, appearance: Appearance) async {
        var state = TabStack.State.loadedHome
        state.path.append(.thread(.loaded(.thread(tweetID: Tweet.mocks[0].id))))
        let view = TabStackView(store: Store(initialState: state) { TabStack() }, title: "Home")
        await assertDuoSnapshot(of: view, pose: pose, appearance: appearance)
    }

    @Test(arguments: [Pose.closed, .innerLandscape], Appearance.allCases)
    func profile(pose: Pose, appearance: Appearance) async {
        var profile = ProfileFeature.State(user: .mock, isViewer: false)
        profile.feeds?.feeds[id: .userPosts(userID: User.mock.id)] = .loaded(.userPosts(userID: User.mock.id))
        let view = NavigationStack {
            ProfileView(store: Store(initialState: profile) { ProfileFeature() })
        }
        await assertDuoSnapshot(of: view, pose: pose, appearance: appearance)
    }

    @Test(arguments: Appearance.allCases)
    func mainWithTabBar(appearance: Appearance) async {
        var state = MainFeature.State(viewer: .mock)
        state.home = .loadedHome
        let view = MainView(store: Store(initialState: state) { MainFeature() })
        await assertDuoSnapshot(of: view, pose: .closed, appearance: appearance)
    }

    /// Hosts the view in a real window and lets it settle for a few frames, so geometry-driven layout (columns,
    /// metrics) has measured itself before the image is taken.
    private func assertDuoSnapshot(
        of view: some View,
        pose: Pose,
        appearance: Appearance,
        testName: String = #function,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) async {
        // Hostless tests have no scene for `init(windowScene:)`.
        let window = UIWindow()
        window.frame = CGRect(origin: .zero, size: pose.size)
        window.overrideUserInterfaceStyle = appearance == .dark ? .dark : .light
        window.rootViewController = UIHostingController(rootView: view)
        window.isHidden = false
        try? await Task.sleep(for: .milliseconds(1500))
        assertSnapshot(
            of: window as UIView,
            // Mock posts are dated relative to now and a focused post spells out its clock time, so a few
            // glyphs differ from run to run.
            as: .image(precision: 0.99),
            named: "\(pose.rawValue)-\(appearance.rawValue)",
            fileID: fileID,
            file: filePath,
            testName: testName,
            line: line,
            column: column
        )
        // Scene-less test windows crash UIKit when they deallocate mid-run; keep them for the process's lifetime.
        Self.retainedWindows.append(window)
    }

    private static var retainedWindows: [UIWindow] = []
}

enum Pose: String, CaseIterable, Sendable {
    case closed, innerLandscape, innerPortrait

    var size: CGSize {
        switch self {
        case .closed: CGSize(width: 466, height: 678)
        case .innerLandscape: CGSize(width: 951, height: 669)
        case .innerPortrait: CGSize(width: 669, height: 951)
        }
    }
}

enum Appearance: String, CaseIterable, Sendable {
    case dark, light

}

extension FeedFeature.State {
    static func loaded(_ source: FeedSource) -> Self {
        var state = Self(
            source: source,
            items: IdentifiedArray(FeedPage.mock(source).items, uniquingIDsWith: { first, _ in first })
        )
        state.hasLoaded = true
        return state
    }
}

extension TabStack.State {
    static var loadedHome: Self {
        var feeds = FeedsFeature.State(sources: [.home(following: false), .home(following: true)])
        feeds.feeds[id: .home(following: false)] = .loaded(.home(following: false))
        var state = TabStack.State.home
        state.root = .feeds(feeds)
        return state
    }
}
