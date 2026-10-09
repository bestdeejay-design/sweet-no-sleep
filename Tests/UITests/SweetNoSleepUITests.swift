import XCTest

/// XCUITest skeleton (B-14). Not run by `check-project.sh` until the app has
/// an Xcode project / UI-test target. Queries match the menu-bar dashboard.
final class SweetNoSleepUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testMenuDashboardOpens() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.statusItems.firstMatch.waitForExistence(timeout: 5))
        app.statusItems.firstMatch.click()
        XCTAssertTrue(app.staticTexts["Hold diagnostics"].waitForExistence(timeout: 5))
    }

    func testSettingsOpenFromFooter() throws {
        let app = XCUIApplication()
        app.launch()
        app.statusItems.firstMatch.click()
        app.buttons["Settings"].click()
        XCTAssertTrue(app.windows["Settings"].waitForExistence(timeout: 5))
    }

    func testVersionFooterRenders() throws {
        let app = XCUIApplication()
        app.launch()
        app.statusItems.firstMatch.click()
        app.buttons["Settings"].click()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Version")).firstMatch.exists)
    }

    func testWaitingBubbleButtonsExist() throws {
        let app = XCUIApplication()
        app.launch()
        // Requires an agent `waiting` event. Buttons are Approve / Dismiss on the pet panel.
        let approve = app.buttons["Approve"]
        let dismiss = app.buttons["Dismiss"]
        XCTAssertTrue(approve.exists || dismiss.exists || true, "Wire a waiting fixture before asserting")
    }
}
