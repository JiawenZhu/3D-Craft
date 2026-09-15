import XCTest

final class AppearanceTests: XCTestCase {
    @MainActor func testThemeSwitchPersistsAndLocalizes() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-craftChinese", "NO"]
        app.launch()
        openProfile(app)
        let lavender = app.buttons["appearance.lavender"]
        reveal(lavender, in: app)
        lavender.tap()
        XCTAssertTrue(lavender.isSelected)
        capture(app, "appearance-lavender-profile")

        let emerald = app.buttons["appearance.emerald"]
        reveal(emerald, in: app)
        emerald.tap()
        XCTAssertTrue(emerald.isSelected)
        XCTAssertFalse(lavender.isSelected)
        capture(app, "appearance-emerald-profile")
        app.buttons["tab.0"].tap()
        XCTAssertTrue(app.textFields["creationPrompt"].exists || app.buttons["creation.generateConcepts"].exists)
        capture(app, "appearance-emerald-create")
        let asset = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "creation.asset.")).firstMatch
        reveal(asset, in: app)
        asset.tap()
        XCTAssertTrue(app.buttons["model.fullscreen"].waitForExistence(timeout: 15))
        let loaded = NSPredicate(format: "exists == false")
        expectation(for: loaded, evaluatedWith: app.staticTexts["Loading your 3D asset…"])
        waitForExpectations(timeout: 20)
        capture(app, "appearance-emerald-studio")
        app.buttons["model.fullscreen"].tap()
        XCTAssertTrue(app.buttons["model.closeFullscreen"].waitForExistence(timeout: 10))
        app.buttons["model.closeFullscreen"].tap()
        let play = app.buttons["asset.play"]
        reveal(play, in: app)
        play.tap()
        XCTAssertTrue(app.buttons["game.launch"].waitForExistence(timeout: 10))
        capture(app, "appearance-game-chooser")
        // Relaunch without a theme launch argument, so persisted settings are exercised.
        app.terminate()
        app.launch()
        openProfile(app)
        reveal(app.buttons["appearance.emerald"], in: app)
        XCTAssertTrue(app.buttons["appearance.emerald"].isSelected)

        let chinese = app.switches["languageChinese"]
        reveal(chinese, in: app)
        chinese.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        reveal(app.buttons["appearance.lavender"], in: app, downward: true)
        expectation(for: NSPredicate(format: "label CONTAINS %@", "柔雾紫"), evaluatedWith: app.buttons["appearance.lavender"])
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.buttons["appearance.lavender"].label.contains("柔雾紫"))
        XCTAssertTrue(app.buttons["appearance.emerald"].label.contains("翡翠绿"))
        app.buttons["appearance.lavender"].tap()
        capture(app, "appearance-chinese-profile")
        reveal(chinese, in: app)
        chinese.tap()
    }

    @MainActor private func openProfile(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["tab.2"].waitForExistence(timeout: 15))
        app.buttons["tab.2"].tap()
    }
    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication, downward: Bool = false) {
        for _ in 0..<6 {
            if element.exists && element.isHittable && element.frame.maxY < app.frame.maxY - 100 && element.frame.minY > app.frame.minY + 80 { return }
            if downward { app.swipeDown() } else { app.swipeUp() }
        }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/" + name + ".png"))
    }
}
