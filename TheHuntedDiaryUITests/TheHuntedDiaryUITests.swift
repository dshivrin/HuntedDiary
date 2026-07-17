import XCTest

final class TheHuntedDiaryUITests: XCTestCase {
    func testAppLaunchesIntoDiary() {
        let app = XCUIApplication()

        app.launch()

        XCTAssertTrue(app.buttons["Clear handwriting"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Settings"].exists)
    }
}
