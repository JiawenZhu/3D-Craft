import XCTest

/// Small visual sample of the real renderer; does not submit generation work.
final class StageReviewTests: XCTestCase {
    @MainActor func testExistingDogAndProfileSelection() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-craftChinese", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["tab.1"].waitForExistence(timeout: 15))
        app.buttons["tab.1"].tap()
        let search = app.textFields["Search your creations"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap(); search.typeText("A cut dog\n")
        let dog = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "asset.")).firstMatch
        guard dog.waitForExistence(timeout: 10) else { throw XCTSkip("Existing dog asset is not in this studio library.") }
        dog.tap()
        XCTAssertTrue(app.buttons["model.fullscreen"].waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.staticTexts["Loading your 3D asset…"])
        waitForExpectations(timeout: 30)
        capture(app, "stage-dog-front")
        let scene = app.descendants(matching: .any).matching(identifier: "model").firstMatch
        scene.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: scene.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)), withVelocity: .slow, thenHoldForDuration: 0.2)
        capture(app, "stage-dog-back")
        app.buttons["asset.play"].tap()
        XCTAssertTrue(app.buttons["game.launch"].waitForExistence(timeout: 10))
        app.buttons["game.launch"].tap()
        let move = app.webViews.buttons["Forward"]
        XCTAssertTrue(move.waitForExistence(timeout: 60), "The selected dog must finish loading in the embedded game.")
        move.press(forDuration: 0.5)
        capture(app, "stage-dog-native-game")
        app.buttons["Back to model"].tap()
        // The chooser is a navigation destination underneath the game cover.
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["studio.back"].tap()
        app.buttons["tab.2"].tap()
        app.buttons["profile.edit"].tap()
        XCTAssertTrue(app.textFields["profile.name"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["profile.choosePhoto"].exists)
        let avatar = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "profile.avatar.")).firstMatch
        for _ in 0..<3 { if avatar.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(avatar.isHittable)
        avatar.tap()
        expectation(for: NSPredicate(format: "selected == true"), evaluatedWith: avatar)
        waitForExpectations(timeout: 15)
        app.swipeDown()
        capture(app, "stage-profile-custom-avatar")
        XCTAssertTrue(app.buttons["profile.save"].isEnabled)
        app.buttons["profile.cancel"].tap()
        app.buttons["tab.0"].tap()
    }

    @MainActor func testLightingFocusWhileDragging() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["-craftChinese", "NO"]; app.launch()
        XCTAssertTrue(app.buttons["tab.0"].waitForExistence(timeout: 15)); app.buttons["tab.0"].tap()
        let sample = app.buttons["creation.sampleDetails"]
        guard sample.waitForExistence(timeout: 5) else { throw XCTSkip("Preserve user reference draft") }
        sample.tap()
        XCTAssertTrue(app.buttons["lighting.adjust"].waitForExistence(timeout: 10))
        app.buttons["lighting.adjust"].tap()
        XCTAssertTrue(app.buttons["lighting.done"].waitForExistence(timeout: 5))
        for id in ["lighting.directional", "lighting.environment", "lighting.exposure"] {
            app.buttons[id + ".select"].tap()
            let slider = app.sliders[id]
            expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: slider)
            waitForExpectations(timeout: 5)
            let previousValue = slider.value as? String
            print("FOCUS_CAPTURE " + id)
            slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.2, thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.5)), withVelocity: .slow, thenHoldForDuration: 7)
            expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: app.buttons["lighting.done"])
            waitForExpectations(timeout: 3)
            XCTAssertNotEqual(previousValue, slider.value as? String, "The selected light must respond to dragging")
            XCTAssertTrue(app.sliders[id].isHittable)
            capture(app, "lighting-restored-" + id)
        }
        app.buttons["lighting.reset"].tap()
        capture(app, "lighting-focus-restored")
        app.buttons["lighting.done"].tap()
        XCTAssertTrue(app.buttons["lighting.adjust"].waitForExistence(timeout: 5))
        let scene = app.descendants(matching: .any).matching(identifier: "model").firstMatch
        scene.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: scene.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)))
        capture(app, "lighting-explore-restored")
    }

    @MainActor func testGroundedStageAndOrbit() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-craftChinese", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["tab.0"].waitForExistence(timeout: 15))
        app.buttons["tab.0"].tap()
        let sample = app.buttons["creation.sampleDetails"]
        guard sample.waitForExistence(timeout: 5) else {
            throw XCTSkip("A user reference is attached. Keep the draft intact.")
        }
        capture(app, "stage-home")
        sample.tap()
        XCTAssertTrue(app.buttons["model.fullscreen"].waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.staticTexts["Loading your 3D asset…"])
        waitForExpectations(timeout: 20)
        capture(app, "stage-front")
        let scene = app.descendants(matching: .any).matching(identifier: "model").firstMatch
        XCTAssertTrue(scene.exists)
        let right = scene.coordinate(withNormalizedOffset: CGVector(dx: 0.80, dy: 0.5))
        let left = scene.coordinate(withNormalizedOffset: CGVector(dx: 0.20, dy: 0.5))
        right.press(forDuration: 0.1, thenDragTo: left, withVelocity: .slow, thenHoldForDuration: 0.2)
        capture(app, "stage-orbit")
        for _ in 0..<3 {
            app.buttons["Reset view"].tap()
            right.press(forDuration: 0.05, thenDragTo: left, withVelocity: .fast, thenHoldForDuration: 0.05)
        }
        app.buttons["Reset view"].tap()
        // Capture after the return settles, including repeated interruption/restart.
        Thread.sleep(forTimeInterval: 1)
        capture(app, "stage-reset-recovered")
        app.buttons["lighting.adjust"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Done"].isHittable)
        XCTAssertTrue(app.sliders["lighting.directional"].isHittable)
        capture(app, "stage-lighting-layout")
        app.buttons["Done"].tap()
        app.buttons["model.fullscreen"].tap()
        XCTAssertTrue(app.buttons["model.closeFullscreen"].waitForExistence(timeout: 10))
        capture(app, "stage-fullscreen")
        app.buttons["model.closeFullscreen"].tap()
        app.buttons["studio.back"].tap()
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        try? shot.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/" + name + ".png"))
    }
}
