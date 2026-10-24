import XCTest

/// Drives the column stack's gestures on whichever display the app is on, with mock data, so they can be recorded and
/// checked by eye: Simulator's own pointer only reaches iPhone Duo's outer display. Runs against the installed app
/// (install it first), since the test bundle isn't hosted by it.
final class ColumnGestureUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Opens a thread as a column, then pulls it down by its bar until it closes.
    @MainActor
    func testPullColumnDown() throws {
        let app = launch("--open-thread")
        let frame = app.windows.firstMatch.frame
        // In the newest column's bar: the trailing card, just below its top edge.
        let start = point(in: app, x: frame.width * 0.6, y: 60)
        start.press(forDuration: 0.05, thenDragTo: point(in: app, x: frame.width * 0.6, y: 460), withVelocity: 900,
            thenHoldForDuration: 0)
        sleep(2)
    }

    /// Opens a thread, then pulls the strip past its start and lets go, throwing the column away.
    @MainActor
    func testThrowColumnsAway() throws {
        let app = launch("--open-thread")
        let frame = app.windows.firstMatch.frame
        let start = point(in: app, x: frame.width * 0.3, y: frame.height * 0.5)
        start.press(forDuration: 0.05, thenDragTo: point(in: app, x: frame.width * 0.3 + 320, y: frame.height * 0.5),
            withVelocity: 600, thenHoldForDuration: 0.1)
        sleep(2)
    }

    /// Slides the strip back to show the column under the newest one, and forward again.
    @MainActor
    func testSlideColumns() throws {
        let app = launch("--open-thread", "--open-profile")
        let frame = app.windows.firstMatch.frame
        let y = frame.height * 0.5
        point(in: app, x: frame.width * 0.3, y: y)
            .press(forDuration: 0.05, thenDragTo: point(in: app, x: frame.width * 0.3 + 260, y: y),
                withVelocity: 1200, thenHoldForDuration: 0)
        sleep(1)
        point(in: app, x: frame.width * 0.6, y: y)
            .press(forDuration: 0.05, thenDragTo: point(in: app, x: frame.width * 0.6 - 260, y: y),
                withVelocity: 1200, thenHoldForDuration: 0)
        sleep(1)
    }

    /// Turns the device to the orientation named in the `UITEST_ORIENTATION` environment variable (portrait,
    /// portraitUpsideDown, landscapeLeft, landscapeRight) and launches with the arguments in `UITEST_ARGS`, then waits
    /// for a screenshot to be taken from outside.
    @MainActor
    func testPose() throws {
        let environment = ProcessInfo.processInfo.environment
        let orientations: [String: UIDeviceOrientation] = [
            "portrait": .portrait, "portraitUpsideDown": .portraitUpsideDown,
            "landscapeLeft": .landscapeLeft, "landscapeRight": .landscapeRight,
        ]
        if let name = environment["UITEST_ORIENTATION"], let orientation = orientations[name] {
            XCUIDevice.shared.orientation = orientation
        }
        let arguments = (environment["UITEST_ARGS"] ?? "").split(separator: " ").map(String.init)
        let app = XCUIApplication(bundleIdentifier: "gold.samhenri.Twitter")
        app.launchArguments = ["--mock-twitter"] + arguments
        app.launch()
        sleep(8)
    }

    private func launch(_ arguments: String...) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "gold.samhenri.Twitter")
        app.launchArguments = ["--mock-twitter"] + arguments
        app.launch()
        sleep(3)
        return app
    }

    private func point(in app: XCUIApplication, x: CGFloat, y: CGFloat) -> XCUICoordinate {
        app.windows.firstMatch.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y))
    }
}
