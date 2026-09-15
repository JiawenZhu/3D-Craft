import XCTest

/// Reviews an already generated reference project; never submits provider work.
final class SourceFlowReviewTests:XCTestCase {
    @MainActor func testSelectedPlantConceptConfirmation() throws {
        continueAfterFailure=false
        let app=XCUIApplication();app.launch()
        let library=app.buttons.matching(NSPredicate(format:"label CONTAINS %@","Library")).firstMatch
        // An active background project may open on launch.
        if !library.waitForExistence(timeout:5) {app.navigationBars.buttons.firstMatch.tap()}
        XCTAssertTrue(library.waitForExistence(timeout:10));library.tap()
        let project=app.buttons.matching(NSPredicate(format:"label CONTAINS %@","Leaf Study · Photo workflow check")).firstMatch
        guard project.waitForExistence(timeout:10) else {throw XCTSkip("Run the explicit plant reference smoke review first.")}
        project.tap()
        let choices=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","concept.select."))
        XCTAssertTrue(choices.firstMatch.waitForExistence(timeout:20),app.debugDescription)
        for _ in 0..<5 {if choices.count>=3 && choices.element(boundBy:2).isHittable{break};app.scrollViews["concept.carousel"].swipeLeft()}
        XCTAssertGreaterThanOrEqual(choices.count,3)
        let chosen=choices.element(boundBy:2)
        XCTAssertTrue(chosen.isHittable);let id=chosen.identifier;chosen.tap();XCTAssertTrue(chosen.isSelected)
        capture(app,"plant-concept-selection")
        let model=app.buttons["concept.make3D"]
        for _ in 0..<8 {if model.isHittable{break};app.swipeUp()}
        XCTAssertTrue(model.isHittable);XCTAssertTrue(model.isEnabled);model.tap()
        let confirm=app.buttons["confirmModelGeneration"]
        XCTAssertTrue(confirm.waitForExistence(timeout:15))
        XCTAssertTrue(confirm.isEnabled)
        capture(app,"plant-selected-source-confirmation")
        XCTAssertFalse(app.staticTexts["Lantern Explorer"].exists)
        app.buttons["Cancel"].tap()
        app.terminate();app.launch()
        XCTAssertTrue(library.waitForExistence(timeout:15));library.tap();project.tap()
        let restored=app.buttons[id]
        XCTAssertTrue(restored.waitForExistence(timeout:15));XCTAssertTrue(restored.isSelected)
        capture(app,"plant-selection-restored")
    }
    @MainActor func testGeneratedPlantModelViewer() throws {
        continueAfterFailure=false
        let app=XCUIApplication();app.launch()
        let library=app.buttons.matching(NSPredicate(format:"label CONTAINS %@","Library")).firstMatch
        XCTAssertTrue(library.waitForExistence(timeout:15));library.tap()
        let plant=app.buttons["asset.a-2309359572"]
        for _ in 0..<8 {if plant.isHittable{break};app.swipeUp()}
        guard plant.isHittable else {throw XCTSkip("Generate the explicit plant smoke model first.")}
        plant.tap()
        XCTAssertTrue(app.buttons["lighting.studio"].waitForExistence(timeout:15))
        XCTAssertTrue(app.otherElements["model"].firstMatch.waitForExistence(timeout:20))
        // UI availability is checked here; the captured mesh is reviewed visually.
        capture(app,"plant-generated-model")
    }
    @MainActor private func capture(_ app:XCUIApplication,_ name:String) {
        let attachment=XCTAttachment(screenshot:app.screenshot());attachment.name=name;attachment.lifetime = .keepAlways;add(attachment)
        try?app.screenshot().pngRepresentation.write(to:URL(fileURLWithPath:"/tmp/"+name+".png"))
    }
}
