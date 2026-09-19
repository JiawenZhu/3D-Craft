import XCTest

/// Navigation-only review: never presses Connect, Logout, or Generate.
final class AIAccountReviewTests: XCTestCase {
    /// Requests and cancels a simulator-only code; never completes account authorization.
    @MainActor func testDeviceSignInRecovery() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-craftChinese", "NO"]; app.launch()
        XCTAssertTrue(app.buttons["tab.2"].waitForExistence(timeout: 15))
        app.buttons["tab.2"].tap()
        let account = app.buttons["profile.aiAccount"]
        for _ in 0..<7 {
            if account.exists && account.isHittable && account.frame.maxY < app.frame.maxY - 100 { break }
            app.swipeUp()
        }
        account.tap()
        let security = app.buttons["ai.securitySettings"]
        XCTAssertTrue(security.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["ai.deviceAuthHelp"].exists)
        capture(app, "chatgpt-device-signin-help")
        let connect = app.buttons["ai.connect"]
        for _ in 0..<5 {
            if connect.isHittable && connect.frame.maxY < app.frame.maxY - 100 { break }
            app.swipeUp()
        }
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: connect)
        waitForExpectations(timeout: 20)
        connect.tap()
        XCTAssertTrue(app.staticTexts["ai.userCode"].waitForExistence(timeout: 35))
        let retry = app.buttons["ai.retryLogin"]
        for _ in 0..<5 {
            if retry.isHittable && retry.frame.maxY < app.frame.maxY - 100 { break }
            app.swipeUp()
        }
        retry.tap()
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: retry)
        waitForExpectations(timeout: 35)
        XCTAssertTrue(app.staticTexts["ai.userCode"].exists)
        XCTAssertFalse(app.staticTexts["ai.error"].exists)
        let cancel = app.buttons["ai.cancelLogin"]
        if !cancel.isHittable { app.swipeUp() }
        cancel.tap()
        XCTAssertTrue(connect.waitForExistence(timeout: 15))
        app.terminate()
    }

    @MainActor func testAccountPageAndPlannerChoicesWithoutSigningIn() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-craftChinese", "NO"]; app.launch()
        XCTAssertTrue(app.buttons["tab.2"].waitForExistence(timeout: 15))
        app.buttons["tab.2"].tap()
        let account = app.buttons["profile.aiAccount"]
        for _ in 0..<7 {
            if account.exists && account.isHittable && account.frame.maxY < app.frame.maxY - 100 { break }
            app.swipeUp()
        }
        XCTAssertTrue(account.isHittable); account.tap()
        XCTAssertTrue(app.buttons["ai.done"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["ChatGPT connection"].exists)
        let connect = app.buttons["ai.connect"]
        XCTAssertTrue(connect.waitForExistence(timeout: 15))
        let ready = NSPredicate(format: "enabled == true")
        expectation(for: ready, evaluatedWith: connect)
        waitForExpectations(timeout: 20)
        XCTAssertFalse(app.staticTexts["ai.error"].exists)
        capture(app, "chatgpt-account-page")
        app.buttons["ai.done"].tap()
        app.buttons["tab.0"].tap()
        let planner = app.buttons["planner.picker"]
        for _ in 0..<6 {
            if planner.exists && planner.isHittable && planner.frame.maxY < app.frame.maxY - 100 { break }
            app.swipeUp()
        }
        XCTAssertTrue(planner.isHittable); planner.tap()
        XCTAssertTrue(app.buttons["planner.model.gemini-3.5-flash-lite"].waitForExistence(timeout: 10))
        capture(app, "prompt-planning-models")
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/" + name + ".png"))
    }
}
