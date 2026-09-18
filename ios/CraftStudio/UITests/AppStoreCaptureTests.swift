import XCTest

/// Real native screens with existing public sample assets. No generation calls,
/// purchase actions, private account content, or external sharing.
final class AppStoreCaptureTests: XCTestCase {
    @MainActor func testCaptureListingScreens() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-craftChinese", "NO", "-craftAppearance", "emerald",
                               "-craftAPI", "https://3d-craft.web.app", "-craftShowPriceDetails", "NO"]
        app.launch()
        let cat = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@", "creation.asset.a-", "Lantern Explorer")).firstMatch
        XCTAssertTrue(cat.waitForExistence(timeout: 35))
        Thread.sleep(forTimeInterval: 4)
        try capture(app, "01-discover")
        cat.tap()
        XCTAssertTrue(app.buttons["asset.gameHandoff"].waitForExistence(timeout: 15))
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.staticTexts["Loading your 3D asset…"])
        waitForExpectations(timeout: 30)
        Thread.sleep(forTimeInterval: 3)
        try capture(app, "02-model")
        app.buttons["lighting.adjust"].tap()
        XCTAssertTrue(app.staticTexts["Lighting studio"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1)
        try capture(app, "03-lighting")
        app.buttons["Done"].tap()
        app.buttons["studio.openConcept"].tap()
        XCTAssertTrue(app.buttons["concept.inspector.close"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 2)
        try capture(app, "04-concept")
        app.buttons["concept.inspector.close"].tap()
        app.buttons["asset.gameHandoff"].tap()
        XCTAssertTrue(app.textViews["handoff.prompt"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1)
        try capture(app, "05-game-brief")
        app.buttons["Done"].tap()
        app.buttons["studio.back"].tap()
        app.buttons["Objects"].tap()
        Thread.sleep(forTimeInterval: 4)
        try capture(app, "06-objects")
        app.terminate()
        app.launchArguments = ["-craftChinese", "NO", "-craftAppearance", "lavender",
                               "-craftAPI", "https://3d-craft.web.app", "-craftShowPriceDetails", "NO"]
        app.launch()
        XCTAssertTrue(cat.waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 3)
        try capture(app, "07-lavender")
    }

    /// Replacement listing shots 03 and 05 with the existing Cloud Dragon example
    /// selected. Same theme and flow as the originals; written to a separate
    /// folder so the approved captures are never overwritten.
    @MainActor func testCaptureDragonLightingAndGameBrief() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-craftChinese", "NO", "-craftAppearance", "emerald",
                               "-craftAPI", "https://3d-craft.web.app", "-craftShowPriceDetails", "NO"]
        app.launch()
        let dragon = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@", "creation.asset.a-", "Cloud Dragon")).firstMatch
        XCTAssertTrue(dragon.waitForExistence(timeout: 35))
        Thread.sleep(forTimeInterval: 2)
        dragon.tap()
        XCTAssertTrue(app.buttons["asset.gameHandoff"].waitForExistence(timeout: 15))
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.staticTexts["Loading your 3D asset…"])
        waitForExpectations(timeout: 30)
        Thread.sleep(forTimeInterval: 3)
        app.buttons["lighting.adjust"].tap()
        XCTAssertTrue(app.staticTexts["Lighting studio"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1)
        try capture(app, "03-lighting", folder: "/tmp/craft-appstore-captures-dragon")
        app.buttons["Done"].tap()
        app.buttons["asset.gameHandoff"].tap()
        XCTAssertTrue(app.textViews["handoff.prompt"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1)
        try capture(app, "05-game-brief", folder: "/tmp/craft-appstore-captures-dragon")
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String,
                                    folder path: String = "/tmp/craft-appstore-captures") throws {
        let folder = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let screenshot = app.screenshot()
        try screenshot.pngRepresentation.write(to: folder.appendingPathComponent(name + ".png"))
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
