import XCTest

final class ImageModelReviewTests: XCTestCase {
    @MainActor func testExactModelChoicesWithoutGenerating() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-craftChinese", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["tab.0"].waitForExistence(timeout: 15))
        app.buttons["tab.0"].tap()
        let picker = app.descendants(matching: .any).matching(identifier: "imageModel.picker").firstMatch
        for _ in 0..<5 {
            if picker.exists && picker.isHittable && picker.frame.maxY < app.frame.maxY - 100 { break }
            app.swipeUp()
        }
        XCTAssertTrue(picker.isHittable)
        picker.tap()
        let openAI = app.buttons["imageModel.codex-gpt-image-2"]
        for _ in 0..<3 { if openAI.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(openAI.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["imageModel.gpt-image-2.5-sunburst"].exists)
        // Inspect the optional account choice without starting sign-in.
        capture(app, "image-model-options")
        let gemini = app.buttons["imageModel.gemini-3-pro-image"]
        for _ in 0..<4 {
            if gemini.isHittable && gemini.frame.minY > 70 && gemini.frame.maxY < app.frame.maxY - 100 { break }
            if gemini.frame.minY < 70 { app.swipeDown() } else { app.swipeUp() }
        }
        gemini.tap()
        XCTAssertTrue(gemini.isSelected)
        capture(app, "image-model-gemini")
        app.buttons["tab.1"].tap()
        capture(app, "image-model-library")
        app.buttons["tab.0"].tap()
    }
    @MainActor func testPricingWithoutGenerating() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-craftChinese", "NO", "-craftShowPriceDetails", "NO"]; app.launch()
        XCTAssertTrue(app.buttons["tab.0"].waitForExistence(timeout: 15))
        app.buttons["tab.0"].tap()
        XCTAssertFalse(app.staticTexts["pricing.concepts.total"].exists)
        app.buttons["pricing.calculator.open"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["pricing.spent"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["pricing.budget.total"].exists)
        XCTAssertFalse(app.otherElements["pricing.calculator.technical"].exists)
        capture(app, "creation-cost-calculator")
        let scroll = app.scrollViews["pricing.calculator.scroll"]
        let toggle = scroll.descendants(matching: .any).matching(identifier: "pricing.details.toggle").firstMatch
        for _ in 0..<4 {
            if toggle.isHittable && toggle.frame.maxY < app.frame.maxY - 70 { break }
            scroll.swipeUp()
        }
        XCTAssertTrue(toggle.isHittable)
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["Provider estimate · USD"].waitForExistence(timeout: 5))
        scroll.swipeUp()
        capture(app, "creation-cost-details")
        for _ in 0..<3 { if toggle.isHittable { break }; scroll.swipeDown() }
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertFalse(app.staticTexts["Provider estimate · USD"].exists)
        app.buttons["pricing.calculator.done"].tap()
        XCTAssertFalse(app.staticTexts["pricing.concepts.total"].exists)
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/" + name + ".png"))
    }
}
