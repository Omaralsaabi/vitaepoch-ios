import XCTest

@MainActor
final class VitaEpochUITests: XCTestCase {
    func testEmptyStateAndNavigation() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
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
    private func launchCapture(constructedHistories: Bool = false) throws -> XCUIApplication {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "device-2026-09-26", withExtension: "json"))
        var archive = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        if constructedHistories {
            // Explicitly constructed page fixture, not a physical-device capture.
            var packets = archive["packets"] as! [[String: Any]]
            let reference = packets.last!
            for (feature, values) in [(UInt8(0x10), [UInt16(11),14,12,13,10]), (UInt8(0x16), [UInt16(363),362,364])] {
                for page: UInt8 in [0,1,2,3] {
                    var bytes: [UInt8] = [0xFD,0xDA,0x10,152,2,feature,0,page] + Array(repeating: 0, count: 144)
                    if page == 2 {
                        for (slot,value) in values.enumerated() { bytes[8+slot*2] = UInt8(value & 255); bytes[9+slot*2] = UInt8(value >> 8) }
                    }
                    packets.append(["id": UUID().uuidString, "timestamp": reference["timestamp"]!,
                        "deviceID": reference["deviceID"]!, "characteristic": "FDD3", "direction": "rx",
                        "bytes": Data(bytes).base64EncodedString(), "timeZoneID": "Asia/Amman"])
                }
            }
            archive["packets"] = packets
        }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["VITAEPOCH_TEST_ARCHIVE"] = try JSONSerialization.data(withJSONObject: archive).base64EncodedString()
        app.launch()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "1 day with heart data")).firstMatch.waitForExistence(timeout: 10))
        return app
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }
    func testCapturedDayWeekChartAndNativeBackNavigation() throws {
        let app = try launchCapture()
        let heart = app.buttons["metric-heartRate"]
        reveal(heart, in: app); heart.tap()
        XCTAssertTrue(app.staticTexts["Intraday readings"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.firstMatch.isHittable)
        app.segmentedControls["metric-range"].buttons["Week"].tap()
        XCTAssertTrue(app.staticTexts["Daily median"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.segmentedControls["metric-range"].buttons["Week"].isSelected)
        app.segmentedControls["metric-range"].buttons["Day"].tap()
        XCTAssertTrue(app.staticTexts["Intraday readings"].exists)
        XCTAssertGreaterThan(app.otherElements["metric-chart"].firstMatch.frame.height, 0)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 3))
        app.tabBars.buttons["Device"].tap()
        let diagnostics = app.buttons["Developer diagnostics"]
        reveal(diagnostics, in: app)
        XCTAssertLessThanOrEqual(diagnostics.frame.maxY, app.tabBars.firstMatch.frame.minY)
    }
    func testConstructedNonzeroHistoryRendersAndChartRangesStayConsistent() throws {
        let app = try launchCapture(constructedHistories: true)
        let hrv = app.buttons["metric-hrv"]
        reveal(hrv, in: app); hrv.tap()
        XCTAssertTrue(app.staticTexts["Intraday readings"].waitForExistence(timeout: 5))
        app.segmentedControls["metric-range"].buttons["Week"].tap()
        XCTAssertTrue(app.staticTexts["Daily median"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        let temperature = app.buttons["metric-wristTemperature"]
        reveal(temperature, in: app); temperature.tap()
        XCTAssertTrue(app.navigationBars["Wrist Temperature"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Intraday readings"].exists)
        XCTAssertTrue(app.staticTexts["36.4"].exists)
    }
}
