import XCTest

final class CloudWelcomeReviewTests: XCTestCase {
    @MainActor func testWelcomeSignInAndLiveGames() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-craftChinese", "NO", "-craftAppearance", "lavender"]
        app.launch()
        XCTAssertTrue(app.buttons["Sign in"].waitForExistence(timeout: 20))
        try capture(app, "welcome")
        app.buttons["Sign in"].tap()
        XCTAssertTrue(app.buttons["Sign in with Apple"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Continue with Google"].exists)
        XCTAssertTrue(app.textFields["Email address"].exists)
        try capture(app, "sign-in")
        app.buttons["Show password"].tap()
        XCTAssertTrue(app.textFields["Password"].exists)
        app.buttons["Hide password"].tap()
        XCTAssertTrue(app.secureTextFields["Password"].exists)
        app.buttons["Close"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Find your next adventure")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["5 games"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.images["community.cover.craft-original-survivor"].firstMatch.waitForExistence(timeout: 20))
        try capture(app, "games")
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) throws {
        let folder = URL(fileURLWithPath: "/tmp/craft-welcome-review")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try app.screenshot().pngRepresentation.write(to: folder.appendingPathComponent(name + ".png"))
    }
}
