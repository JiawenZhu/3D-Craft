import XCTest

final class VisualPolishTests: XCTestCase {
    @MainActor func testRealCatPresentationAndNativeControls() throws {
        continueAfterFailure = false
        let app=XCUIApplication()
        app.launchArguments=["-craftChinese","NO"]
        app.launch()
        XCTAssertTrue(app.buttons["tab.0"].waitForExistence(timeout:15))
        app.buttons["tab.0"].tap()
        XCTAssertTrue(app.buttons["creation.sampleDetails"].waitForExistence(timeout:10), "Sample preview requires the current empty input draft; do not delete a user reference for this test.")
        capture(app,"polish-home")
        app.buttons["creation.sampleDetails"].tap()
        XCTAssertTrue(app.buttons["model.fullscreen"].waitForExistence(timeout:10))
        expectation(for:NSPredicate(format:"exists == false"),evaluatedWith:app.staticTexts["Loading your 3D asset…"])
        waitForExpectations(timeout:20)
        capture(app,"polish-cat-studio")
        app.buttons["Solid"].tap()
        app.buttons["Material"].tap()
        app.buttons["model.fullscreen"].tap()
        XCTAssertTrue(app.buttons["model.closeFullscreen"].waitForExistence(timeout:10))
        capture(app,"polish-cat-fullscreen")
        app.buttons["model.closeFullscreen"].tap()
        app.buttons["lighting.adjust"].tap()
        capture(app,"polish-lighting")
        app.buttons["Done"].tap()
        app.buttons["studio.back"].tap()
        app.buttons["tab.2"].tap()
        XCTAssertTrue(app.buttons["appearance.emerald"].waitForExistence(timeout:10))
        app.buttons["appearance.emerald"].tap()
        capture(app,"polish-profile-emerald")
        app.buttons["tab.0"].tap()
        capture(app,"polish-home-emerald")
        app.buttons["tab.2"].tap()
        app.buttons["appearance.lavender"].tap()
        capture(app,"polish-profile-lavender")
        app.buttons["tab.0"].tap()
    }
    @MainActor private func capture(_ app:XCUIApplication,_ name:String) {
        let shot=app.screenshot()
        let attachment=XCTAttachment(screenshot:shot);attachment.name=name;attachment.lifetime = .keepAlways
        add(attachment)
        try? shot.pngRepresentation.write(to:URL(fileURLWithPath:"/tmp/"+name+".png"))
    }
}
