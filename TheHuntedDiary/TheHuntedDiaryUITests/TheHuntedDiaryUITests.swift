import XCTest

final class TheHuntedDiaryUITests: XCTestCase {
    func testAppLaunchesIntoDiary() {
        let app = XCUIApplication()

        app.launch()

        XCTAssertTrue(app.buttons["Clear handwriting"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Settings"].exists)
    }

    func testCallbackURLReactivatesAnInactiveDiaryScene() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Clear handwriting"].waitForExistence(timeout: 5))

        XCUIDevice.shared.press(.home)
        let reachedBackground = app.wait(for: .runningBackground, timeout: 5)
            || app.state == .runningBackgroundSuspended
        XCTAssertTrue(reachedBackground, "Expected the diary scene to become inactive")

        var callback = URLComponents()
        callback.scheme = "toms-diary"
        callback.host = "shortcut-cancel"
        callback.queryItems = [
            URLQueryItem(name: "id", value: "01234567-89ab-cdef-0123-456789abcdef"),
            URLQueryItem(name: "token", value: String(repeating: "A", count: 43)),
        ]
        let url = try XCTUnwrap(callback.url)

        app.open(url)

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertTrue(app.buttons["Clear handwriting"].exists)
    }
}
