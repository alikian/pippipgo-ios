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
