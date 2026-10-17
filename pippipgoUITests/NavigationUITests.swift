import XCTest

/// Real signed-out screens, without account credentials or backend writes.
/// Run on a dedicated simulator with no saved PipPipGo sign-in.
@MainActor
final class NavigationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-pip.language", "en", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["login.guest"].waitForExistence(timeout: 20),
                      "Use a dedicated signed-out simulator for UI tests.")
    }

    override func tearDownWithError() throws {
        if let app {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = name
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.terminate()
        }
        app = nil
    }

    func testWelcomeOffersSignInAndGuestExploration() {
        XCTAssertTrue(app.buttons["login.signIn"].isEnabled)
        XCTAssertTrue(app.buttons["login.guest"].isEnabled)
        XCTAssertTrue(app.staticTexts["PipPipGo"].exists)
    }

    func testGuestDisclosureCanBeCancelledAndOpenedAgain() {
        app.buttons["login.guest"].tap()
        let cancel = app.buttons["guestNotice.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["guestNotice.continue"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["guestNotice.privacy"].exists)
        cancel.tap()
        XCTAssertTrue(app.buttons["login.signIn"].waitForExistence(timeout: 5))
        app.buttons["login.guest"].tap()
        XCTAssertTrue(app.buttons["guestNotice.continue"].waitForExistence(timeout: 5))
    }
}
/// Uses the existing debug home preview to exercise the real map and tour sheet
/// without signing in, creating a tour, or changing organizer data.
@MainActor
final class TourBuilderUITests: XCTestCase {
    func testTransportChoicesAllowMultipleSelection() {
        let app = XCUIApplication()
        app.launchArguments = ["-pip.language", "en", "-AppleLanguages", "(en)",
                               "-AppleLocale", "en_US", "-PipPreviewHome", "-PipHomeTab", "guide"]
        app.launch()
        defer { app.terminate() }
        let openBuilder = app.buttons["liveGuide.createTour"]
        XCTAssertTrue(openBuilder.waitForExistence(timeout: 20))
        openBuilder.tap()
        let walking = app.buttons["tourBuilder.transport.walking"]
        XCTAssertTrue(walking.waitForExistence(timeout: 5))
        XCTAssertTrue(walking.isSelected)
        for id in ["driving", "rideshare", "transit"] {
            let choice = app.buttons["tourBuilder.transport.\(id)"]
            if !choice.isHittable { app.scrollViews.firstMatch.swipeUp() }
            choice.tap()
            XCTAssertTrue(choice.isSelected)
            XCTAssertTrue(walking.isSelected, "Selecting another option must keep Walking selected.")
        }
        for id in ["walking", "driving", "rideshare", "transit"] {
            XCTAssertTrue(app.buttons["tourBuilder.transport.\(id)"].isSelected)
        }
        let driving = app.buttons["tourBuilder.transport.driving"]
        driving.tap()
        XCTAssertFalse(driving.isSelected)
        XCTAssertTrue(app.buttons["tourBuilder.transport.rideshare"].isSelected)
        XCTAssertTrue(app.buttons["tourBuilder.transport.transit"].isSelected)
        XCTAssertTrue(walking.isSelected)
        walking.tap()
        app.buttons["tourBuilder.transport.rideshare"].tap()
        app.buttons["tourBuilder.transport.transit"].tap()
        app.scrollViews.firstMatch.swipeUp()
        XCTAssertFalse(app.buttons["tourBuilder.create"].isEnabled,
                       "At least one transport option is required.")
    }

    func testAreaOrParkTypingKeepsTourBuilderResponsive() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-pip.language", "en", "-AppleLanguages", "(en)",
                               "-AppleLocale", "en_US", "-PipPreviewHome", "-PipHomeTab", "guide"]
        app.launch()
        defer { app.terminate() }

        let openBuilder = app.buttons["liveGuide.createTour"]
        XCTAssertTrue(openBuilder.waitForExistence(timeout: 20))
        openBuilder.tap()

        let area = app.textFields["tourBuilder.area"]
        XCTAssertTrue(area.waitForExistence(timeout: 5))
        if !area.isHittable { app.scrollViews.firstMatch.swipeUp() }
        area.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        area.typeText("Balboa Park")
        XCTAssertEqual((area.value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), "Balboa Park")

        // Switching fields and returning exercises repeated keyboard layout,
        // rather than merely checking that the sheet initially appeared.
        let activities = app.descendants(matching: .any)["tourBuilder.activities"].firstMatch
        if !activities.isHittable { app.scrollViews.firstMatch.swipeUp() }
        activities.tap()
        activities.typeText("Walk through the gardens")
        XCTAssertEqual((activities.value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), "Walk through the gardens")
        area.tap()
        XCTAssertEqual((area.value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), "Balboa Park")
        XCTAssertTrue(app.keyboards.firstMatch.exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Tour area entered with keyboard open"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.navigationBars.buttons["Done"].tap()
        XCTAssertTrue(openBuilder.waitForExistence(timeout: 5),
                      "The sheet must dismiss and return to a responsive Guide screen.")
        openBuilder.tap()
        XCTAssertTrue(area.waitForExistence(timeout: 5))
    }
}
