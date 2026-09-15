import XCTest

final class ThumbnailReviewTests: XCTestCase {
    @MainActor func testDogLibraryLightThemeBackdrops() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-craftChinese", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["tab.1"].waitForExistence(timeout: 15))
        app.buttons["tab.1"].tap()
        let search = app.textFields["Search your creations"]
        search.tap(); search.typeText("A cut dog\n")
        let dog = app.buttons["asset.a-77f731a340"]
        XCTAssertTrue(dog.waitForExistence(timeout: 15), "Review the existing user-reported dog.")
        let subject = dog.descendants(matching: .any).matching(identifier: "thumbnail.subject").firstMatch
        XCTAssertTrue(subject.waitForExistence(timeout: 45))
        reveal(dog, in: app)
        capture(app, "thumbnail-dog-emerald")
        app.buttons["tab.2"].tap()
        let lavender = app.buttons["appearance.lavender"]
        for _ in 0..<4 { if lavender.isHittable { break }; app.swipeUp() }
        lavender.tap()
        app.buttons["tab.1"].tap()
        XCTAssertTrue(subject.waitForExistence(timeout: 10))
        reveal(dog, in: app)
        capture(app, "thumbnail-dog-lavender")
        app.buttons["tab.2"].tap()
        let emerald = app.buttons["appearance.emerald"]
        for _ in 0..<4 { if emerald.isHittable { break }; app.swipeUp() }
        emerald.tap()
        app.buttons["tab.1"].tap()
    }
    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<4 {
            if element.isHittable && element.frame.maxY < app.frame.maxY - 115 { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/" + name + ".png"))
    }
}
