import XCTest

@MainActor
final class VitaEpochUITests: XCTestCase {
    func testEmptyStateAndNavigation() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Building your baseline"].exists)
        XCTAssertTrue(app.buttons["Connect your band"].exists)
        app.tabBars.buttons["Trends"].tap()
        XCTAssertTrue(app.staticTexts["Your story starts with a sync"].waitForExistence(timeout: 3))
        app.tabBars.buttons["Age"].tap()
        XCTAssertTrue(app.staticTexts["Insufficient data · model pending"].waitForExistence(timeout: 3))
        app.tabBars.buttons["Device"].tap()
        XCTAssertTrue(app.buttons["Find my band"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Not read yet")).firstMatch.exists)
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.navigationBars["Today"].exists)
    }
}
