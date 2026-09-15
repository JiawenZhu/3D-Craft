import XCTest

final class ReviewFlowTests: XCTestCase {
    @MainActor func testFreeReviewAndNativeGameEntry() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["DYLD_FRAMEWORK_PATH"] = "/Applications/Xcode-beta.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/Library/Frameworks:/Applications/Xcode-beta.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/Library/PrivateFrameworks"
        app.launch()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format:"label CONTAINS %@", "Profile")).firstMatch.waitForExistence(timeout:20), app.debugDescription)
        app.buttons.matching(NSPredicate(format:"label CONTAINS %@", "Profile")).firstMatch.tap()
        let credits = app.buttons.matching(NSPredicate(format:"label CONTAINS %@", "Free generation testing")).firstMatch
        XCTAssertTrue(credits.waitForExistence(timeout:10)); credits.tap()
        let refill = app.buttons["refillTestCredits"]
        XCTAssertTrue(refill.waitForExistence(timeout:10)); XCTAssertTrue(refill.isEnabled)
        capture(app, "free-generation-testing")
        refill.tap()
        XCTAssertTrue(credits.waitForExistence(timeout:10))
        let chinese = app.switches["languageChinese"]
        XCTAssertTrue(chinese.waitForExistence(timeout:10)); chinese.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format:"label CONTAINS %@", "资产库")).firstMatch.waitForExistence(timeout:5))
        capture(app, "chinese-profile")
        chinese.tap()
        app.buttons.matching(NSPredicate(format:"label CONTAINS %@", "Library")).firstMatch.tap()
        // This is the model produced by the real local concept-to-3D smoke run.
        let generated = app.buttons["asset.a-2181c954df"]
        for _ in 0..<6 { if generated.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(generated.isHittable, app.debugDescription); generated.tap()
        // Target the stable identifier, not an English label. The app has always
        // labelled this "Try in a game" / "带入游戏试玩", so the old string matched
        // nothing and also could never pass in the Chinese interface.
        let play = app.buttons["asset.play"]
        for _ in 0..<3 { if play.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(play.waitForExistence(timeout:20))
        capture(app, "generated-model-viewer")
        play.tap()
        let launch = app.buttons["game.launch"]
        for _ in 0..<6 { if launch.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(launch.isHittable, app.debugDescription)
        capture(app, "compatible-game-selection")
        launch.tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout:30), app.debugDescription)
        XCTAssertTrue(app.buttons["Back to model"].exists)
        capture(app, "native-game-webview-entry")
        // Rendered game and movement are inspected separately; existence of a
        // WKWebView alone is not proof of loaded assets or a running game.
    }
    @MainActor func testPhotoImportAndSubjectReview() throws {
        continueAfterFailure = false
        let app=XCUIApplication();app.launch()
        let photos=app.buttons.matching(NSPredicate(format:"label CONTAINS %@", "Photos")).firstMatch
        XCTAssertTrue(photos.waitForExistence(timeout:15),app.debugDescription);photos.tap()
        let photo=app.images.matching(NSPredicate(format:"label BEGINSWITH %@", "Photo,")).firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout:10),app.debugDescription);photo.tap()
        let use=app.buttons["photoReviewUse"]
        XCTAssertTrue(use.waitForExistence(timeout:15),app.debugDescription)
        XCTAssertFalse(use.isEnabled)
        app.buttons["photoReviewRotate"].tap()
        app.buttons["photoReviewSquareCrop"].tap()
        let subject=app.switches["photoReviewOneSubject"]
        for _ in 0..<4 {if subject.isHittable{break};app.swipeUp()}
        subject.tap();XCTAssertTrue(use.isEnabled)
        capture(app,"photo-subject-review")
        app.buttons["Cancel"].tap()
    }
    @MainActor func testLightingPresetsAndControls() throws {
        continueAfterFailure=false
        let app=XCUIApplication();app.launch()
        let library=app.buttons.matching(NSPredicate(format:"label CONTAINS %@","Library")).firstMatch
        XCTAssertTrue(library.waitForExistence(timeout:20));library.tap()
        let cat=app.buttons["asset.a-2181c954df"]
        for _ in 0..<7 {if cat.isHittable{break};app.swipeUp()}
        XCTAssertTrue(cat.isHittable);cat.tap()
        let studio=app.buttons["lighting.studio"]
        XCTAssertTrue(studio.waitForExistence(timeout:15))
        XCTAssertTrue(app.otherElements["model"].firstMatch.waitForExistence(timeout:15),app.debugDescription)
        capture(app,"lighting-studio")
        app.buttons["lighting.sunset"].tap();XCTAssertTrue(app.buttons["lighting.sunset"].isSelected);capture(app,"lighting-sunset")
        app.buttons["lighting.night"].tap();XCTAssertTrue(app.buttons["lighting.night"].isSelected);capture(app,"lighting-night")
        app.buttons["lighting.studio"].tap()
        app.buttons["lighting.adjust"].tap()
        let slider=app.sliders["lighting.directional"]
        XCTAssertTrue(slider.waitForExistence(timeout:5));slider.adjust(toNormalizedSliderPosition:0.8)
        capture(app,"lighting-adjustments")
        app.buttons["Reset"].tap();app.buttons["Done"].tap()
    }
    @MainActor private func capture(_ app:XCUIApplication, _ name:String) {
        let attachment = XCTAttachment(screenshot:app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
