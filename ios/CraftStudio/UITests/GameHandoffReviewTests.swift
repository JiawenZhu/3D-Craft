import XCTest

final class GameHandoffReviewTests: XCTestCase {
    @MainActor func testModelHandoffReplacesPlayAndSharesFiles() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-craftChinese", "NO", "-craftAppearance", "emerald", "-craftAPI", "http://127.0.0.1:8001"]
        app.launch()
        let cat = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@", "creation.asset.a-", "Lantern Explorer")).firstMatch
        XCTAssertTrue(cat.waitForExistence(timeout: 30))
        cat.tap()
        let handoff = app.buttons["asset.gameHandoff"]
        XCTAssertTrue(handoff.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["asset.play"].exists)
        handoff.tap()
        XCTAssertTrue(app.textViews["handoff.prompt"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.textViews["handoff.prompt"].value as? String ?? "", "")
        app.buttons["handoff.chooseObjects"].tap()
        let objects = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "handoff.object."))
        XCTAssertGreaterThan(objects.count, 1)
        objects.element(boundBy: 1).tap()
        try app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/craft-handoff-object-picker.png"))
        app.navigationBars["Choose objects"].buttons["Done"].tap()
        let preview = app.staticTexts["handoff.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertTrue(preview.label.contains("01-"))
        XCTAssertTrue(preview.label.contains("02-"))
        XCTAssertTrue(preview.label.contains("browser"))
        XCTAssertFalse(preview.label.contains("Safari"))
        app.segmentedControls["handoff.builder"].buttons["Claude Code"].tap()
        app.swipeUp()
        XCTAssertTrue(app.buttons["handoff.open"].label.contains("Claude Code"))
        let shot = app.screenshot()
        try shot.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/craft-game-handoff.png"))
        let attachment = XCTAttachment(screenshot: shot); attachment.lifetime = .keepAlways; add(attachment)
        app.buttons["handoff.share"].tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertFalse(app.staticTexts["handoff.error"].exists)
        // The native share sheet is the explicit handoff boundary. Do not send
        // assets to a third-party account during UI verification.
    }
}
