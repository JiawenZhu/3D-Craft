import XCTest

/// Read-only gallery acceptance. Uses existing models and never generates work.
final class GalleryReviewTests: XCTestCase {
    @MainActor func testConceptCountConfirmation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-craftChinese", "NO", "-craftAppearance", "emerald", "-craftDraftPrompt", "A tiny forest adventurer"]
        app.launch()
        let open = app.buttons["creation.generateConcepts"]
        XCTAssertTrue(open.waitForExistence(timeout: 20))
        open.tap()
        let minus = app.buttons["concept.generation.minus"]
        let plus = app.buttons["concept.generation.plus"]
        let count = app.staticTexts["concept.generation.count"]
        let total = app.staticTexts["concept.generation.total"]
        XCTAssertTrue(minus.waitForExistence(timeout: 5))
        XCTAssertEqual(count.label, "4")
        XCTAssertEqual(total.label, "60 Tokens")
        XCTAssertFalse(plus.isEnabled)
        minus.tap(); minus.tap(); minus.tap()
        XCTAssertEqual(count.label, "1")
        XCTAssertEqual(total.label, "15 Tokens")
        XCTAssertFalse(minus.isEnabled)
        plus.tap(); plus.tap()
        XCTAssertEqual(count.label, "3")
        XCTAssertEqual(total.label, "45 Tokens")
        capture(app, "concept-count-confirmation")
        app.buttons["concept.generation.cancel"].tap()
        open.tap()
        XCTAssertTrue(minus.waitForExistence(timeout: 5))
        XCTAssertEqual(count.label, "3")
        app.buttons["concept.generation.cancel"].tap()
        app.terminate()
    }

    @MainActor func testExpandedModelZoom() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-craftChinese", "NO", "-craftAppearance", "emerald"]
        app.launch()
        XCTAssertTrue(app.buttons["creation.category.objects"].waitForExistence(timeout: 20))
        app.buttons["creation.category.objects"].tap()
        let car = app.buttons["creation.asset.a-bc1cebd0f9"]
        XCTAssertTrue(car.waitForExistence(timeout: 15))
        car.tap()
        XCTAssertTrue(app.buttons["model.fullscreen"].waitForExistence(timeout: 10))
        app.buttons["model.fullscreen"].tap()
        let zoomIn = app.buttons["model.zoomIn"]
        XCTAssertTrue(zoomIn.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 5)
        capture(app, "gallery-expand-fit")
        zoomIn.tap()
        zoomIn.tap()
        Thread.sleep(forTimeInterval: 1)
        capture(app, "gallery-expand-detail")
        app.buttons["model.zoomOut"].tap()
        app.buttons["model.resetZoom"].tap()
        Thread.sleep(forTimeInterval: 1)
        capture(app, "gallery-expand-reset")
        app.buttons["model.closeFullscreen"].tap()
        XCTAssertTrue(app.buttons["model.fullscreen"].waitForExistence(timeout: 5))
        app.terminate()
    }

    @MainActor func testExistingConceptLayout() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-craftChinese", "NO", "-craftAppearance", "lavender"]
        app.launch()
        XCTAssertTrue(app.buttons["tab.1"].waitForExistence(timeout: 15))
        app.buttons["tab.1"].tap()
        let project = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "library.project.")).firstMatch
        XCTAssertTrue(project.waitForExistence(timeout: 10))
        project.tap()
        XCTAssertTrue(app.buttons["concept.settings"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.scrollViews["concept.carousel"].exists)
        XCTAssertTrue(app.scrollViews["concept.thumbnails"].exists)
        Thread.sleep(forTimeInterval: 2)
        capture(app, "gallery-concept-studio")
        app.buttons["concept.settings"].tap()
        XCTAssertTrue(app.buttons["concept.settings.done"].waitForExistence(timeout: 5))
        app.buttons["concept.settings.done"].tap()
        app.terminate()
    }

    @MainActor func testGalleryThemesAndRealModel() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        for theme in ["lavender", "emerald"] {
            app.launchArguments = ["-craftChinese", "NO", "-craftAppearance", theme, "-craftShowPriceDetails", "NO"]
            app.launch()
            XCTAssertTrue(app.buttons["creation.category.characters"].waitForExistence(timeout: 20))
            let cat = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@", "creation.asset.a-", "Lantern Explorer")).firstMatch
            XCTAssertTrue(cat.waitForExistence(timeout: 25), "The curated real Rodin sample must arrive from the studio.")
            Thread.sleep(forTimeInterval: 2)
            capture(app, "gallery-" + theme)
            app.buttons["creation.category.objects"].tap()
            XCTAssertFalse(cat.exists)
            let car = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@", "creation.asset.", "Mint Racer")).firstMatch
            XCTAssertTrue(car.waitForExistence(timeout: 5))
            app.buttons["creation.category.characters"].tap()
            XCTAssertTrue(cat.waitForExistence(timeout: 5))
            XCTAssertFalse(car.exists)
            app.buttons["creation.category.characters"].tap()
            if theme == "lavender" {
                cat.tap()
                XCTAssertTrue(app.buttons["studio.openConcept"].waitForExistence(timeout: 15))
                XCTAssertTrue(app.buttons["model.fullscreen"].exists)
                Thread.sleep(forTimeInterval: 5)
                capture(app, "gallery-real-model")
                app.buttons["studio.openConcept"].tap()
                XCTAssertTrue(app.buttons["concept.inspector.close"].waitForExistence(timeout: 10))
                waitUntilHittable(app.buttons["concept.inspector.close"])
                capture(app, "gallery-original-concept")
                app.buttons["concept.inspector.close"].tap()
                waitUntilHittable(app.buttons["Reset view"])
                app.buttons["Reset view"].tap()
                app.buttons["lighting.adjust"].tap()
                XCTAssertTrue(app.buttons["lighting.done"].waitForExistence(timeout: 5))
                app.buttons["lighting.environment.select"].tap()
                app.sliders["lighting.environment"].adjust(toNormalizedSliderPosition: 0.6)
                app.buttons["lighting.done"].tap()
                app.buttons["studio.back"].tap()
                app.buttons["creation.settings"].tap()
                XCTAssertTrue(app.buttons["creation.settings.done"].waitForExistence(timeout: 5))
                app.buttons["creation.settings.done"].tap()
            }
            app.terminate()
        }
    }

    @MainActor func testPrivateGalleryAndLibrary() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-craftChinese", "NO", "-craftAppearance", "emerald"]
        app.launch()
        let characters = app.buttons["creation.category.characters"]
        XCTAssertTrue(characters.waitForExistence(timeout: 15))
        XCTAssertEqual(characters.value as? String, "Selected")
        let privateDogs = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@", "creation.asset.", "dog"))
        XCTAssertFalse(privateDogs.firstMatch.exists)
        app.buttons["creation.category.objects"].tap()
        XCTAssertFalse(privateDogs.firstMatch.exists)
        let userCreated = app.buttons["creation.category.user-created"]
        XCTAssertTrue(userCreated.waitForExistence(timeout: 5))
        userCreated.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        guard privateDogs.firstMatch.waitForExistence(timeout: 5) else {
            throw XCTSkip("Private dog asset is not in this studio library.")
        }
        XCTAssertFalse(app.buttons["creation.asset.a-a44cd03b47"].exists)
        capture(app, "gallery-user-created")
        app.buttons["tab.1"].tap()
        XCTAssertTrue(app.buttons["library.filter.models"].waitForExistence(timeout: 10))
        capture(app, "gallery-library")
        app.buttons["library.filter.models"].tap()
        XCTAssertFalse(app.buttons["asset.a-a44cd03b47"].exists)
        let libraryDogs = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@", "asset.", "dog"))
        XCTAssertTrue(libraryDogs.firstMatch.waitForExistence(timeout: 5))
        capture(app, "gallery-library-models")
        app.terminate()
    }

    @MainActor func testProfileThemeChoicePersists() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-craftChinese", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["tab.2"].waitForExistence(timeout: 15))
        app.buttons["tab.2"].tap()
        let green = app.buttons["appearance.emerald"]
        XCTAssertTrue(green.waitForExistence(timeout: 10))
        let original = green.value as? String == "Selected" ? "emerald" : "lavender"
        let other = original == "emerald" ? "lavender" : "emerald"
        app.buttons["appearance." + other].tap()
        XCTAssertEqual(app.buttons["appearance." + other].value as? String, "Selected")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["tab.2"].waitForExistence(timeout: 15))
        app.buttons["tab.2"].tap()
        XCTAssertTrue(app.buttons["appearance." + other].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["appearance." + other].value as? String, "Selected")
        app.buttons["appearance." + original].tap()
        XCTAssertEqual(app.buttons["appearance." + original].value as? String, "Selected")
        app.terminate()
    }

    @MainActor func testWorldAndOutfitFraming() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-craftChinese", "NO", "-craftAppearance", "emerald"]
        app.launch()
        XCTAssertTrue(app.buttons["creation.category.objects"].waitForExistence(timeout: 20))
        app.buttons["creation.category.objects"].tap()
        for (name, screenshot) in [("Coconut Island", "gallery-world-model"), ("Starlight Robe", "gallery-outfit-model")] {
            let tile = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@", "creation.asset.a-", name)).firstMatch
            for _ in 0..<6 {
                if tile.exists && tile.isHittable && tile.frame.midY < app.frame.height * 0.72 { break }
                app.swipeUp()
            }
            XCTAssertTrue(tile.exists)
            waitUntilHittable(tile)
            tile.tap()
            XCTAssertTrue(app.buttons["model.fullscreen"].waitForExistence(timeout: 10))
            Thread.sleep(forTimeInterval: 5)
            capture(app, screenshot)
            app.buttons["studio.back"].tap()
            waitUntilHittable(app.buttons["creation.category.objects"])
            Thread.sleep(forTimeInterval: 1.5)
        }
        app.terminate()
    }

    @MainActor private func waitUntilHittable(_ element: XCUIElement) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed)
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        try? shot.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/" + name + ".png"))
    }
}
