import XCTest

final class ModelPromptUITests: XCTestCase {
    @MainActor func testPromptEntryAndImageOnlyCapabilityMessage() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview-model-prompt", "-craftChinese", "NO"]
        app.launch()
        let field = app.descendants(matching: .any)["modelPromptField"].firstMatch
        for _ in 0..<5 {
            if field.exists && field.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(field.isHittable)
        field.tap()
        field.typeText("Preserve the face shape and glasses.")
        app.buttons["Done"].tap()
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "image-plus-prompt"; shot.lifetime = .keepAlways; add(shot)
        let picker = app.buttons["modelEnginePicker"]
        for _ in 0..<5 {
            if picker.isHittable { break }
            app.swipeDown()
        }
        picker.tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "TRELLIS.2")).firstMatch.tap()
        let switchBack = app.buttons["modelUsePromptEngine"]
        for _ in 0..<5 {
            if switchBack.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(switchBack.isHittable)
        XCTAssertFalse(app.buttons["confirmModelGeneration"].isEnabled)
        switchBack.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertEqual(field.value as? String, "Preserve the face shape and glasses.")
    }
}
