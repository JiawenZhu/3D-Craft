import XCTest

/// Uses ios/scripts/chat-review-server.py. Existing sample assets only; never submits generation.
final class ConversationReviewTests: XCTestCase {
    @MainActor func testAttachedImageSkipsConversationAndKeepsDraftOnCancel() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-craftConceptCount", "2", "-craftAPI", "http://127.0.0.1:8003", "-craftChinese", "NO",
            "-craftActiveConversation:http://127.0.0.1:8003", "chat-ui-review",
            "-craftChatReference:http://127.0.0.1:8003:chat-ui-review", "chat-ui-concept",
            "-craftChatDraft:http://127.0.0.1:8003:chat-ui-review", ""]
        app.launch()
        let send = app.buttons["chat.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Reference ready · Generate directly"].waitForExistence(timeout: 10))
        XCTAssertTrue(send.isEnabled) // An image alone is enough; no forced text question.
        send.tap()
        XCTAssertTrue(app.buttons["concept.generation.minus"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["concept.generation.total"].label, "30 Tokens")
        capture(app, "direct-photo-confirmation")
        app.buttons["concept.generation.cancel"].tap()
        XCTAssertTrue(app.staticTexts["Reference ready · Generate directly"].exists)
        let message = app.textFields["chat.message"].exists ? app.textFields["chat.message"] : app.textViews["chat.message"]
        message.tap(); message.typeText("Keep the face, add a blue jacket")
        send.tap()
        XCTAssertTrue(app.buttons["concept.generation.cancel"].waitForExistence(timeout: 5))
        app.buttons["concept.generation.cancel"].tap()
        XCTAssertEqual(message.value as? String, "Keep the face, add a blue jacket")
        app.terminate()
    }
    @MainActor func testConversationKeepsConceptsAndModelInline() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-craftConceptCount", "4", "-craftAPI", "http://127.0.0.1:8003", "-craftChinese", "NO", "-craftAppearance", "emerald",
            "-craftActiveConversation:http://127.0.0.1:8003", "chat-ui-review"]
        app.launch()
        XCTAssertTrue(app.buttons["chat.settings"].waitForExistence(timeout: 15))
        let concept = app.buttons["chat.concept.chat-ui-concept"]
        reveal(concept, in: app)
        XCTAssertTrue(concept.exists)
        concept.tap()
        let model = app.buttons["chat.generate3D"]
        if !model.isHittable { app.swipeUp() }
        XCTAssertTrue(model.isHittable)
        capture(app, "chat-inline-concept")
        // Check the real native model is present in the same scroll surface.
        let explore = app.buttons["chat.explore3D"]
        reveal(explore, in: app)
        capture(app, "chat-before-explore")
        explore.tap()
        let zoom = app.buttons["model.zoomIn"]
        reveal(zoom, in: app)
        XCTAssertTrue(zoom.waitForExistence(timeout: 15))
        zoom.tap()
        capture(app, "chat-inline-model")
        explore.tap()
        let create = app.buttons["chat.generateConcepts"]
        reveal(create, in: app)
        XCTAssertTrue(create.isHittable)
        capture(app, "chat-before-count")
        XCTAssertTrue(create.isEnabled)
        create.tap()
        let minus = app.buttons["concept.generation.minus"]
        XCTAssertTrue(minus.waitForExistence(timeout: 5))
        minus.tap(); minus.tap(); minus.tap()
        XCTAssertEqual(app.staticTexts["concept.generation.count"].label, "1")
        XCTAssertEqual(app.staticTexts["concept.generation.total"].label, "15 Tokens")
        app.buttons["concept.generation.plus"].tap()
        XCTAssertEqual(app.staticTexts["concept.generation.total"].label, "30 Tokens")
        capture(app, "chat-image-count")
        app.buttons["concept.generation.cancel"].tap()
        XCTAssertTrue(app.buttons["chat.settings"].exists)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["chat.settings"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["A cat riding a bicycle"].firstMatch.waitForExistence(timeout: 10))
        capture(app, "chat-saved-history")
        app.terminate()
    }
    @MainActor func testGallerySubmissionStartsConversation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-craftConceptCount", "4", "-craftAPI", "http://127.0.0.1:8003", "-craftChinese", "NO", "-craftAppearance", "lavender",
            "-craftActiveConversation:http://127.0.0.1:8003", "chat-ui-review", "-craftDraftPrompt", "A cat riding a bicycle"]
        app.launch()
        XCTAssertTrue(app.buttons["chat.gallery"].waitForExistence(timeout: 15))
        app.buttons["chat.gallery"].tap()
        XCTAssertTrue(app.buttons["creation.generateConcepts"].waitForExistence(timeout: 5))
        app.buttons["creation.generateConcepts"].tap()
        XCTAssertTrue(app.buttons["chat.settings"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["A cozy forest adventure"].waitForExistence(timeout: 20))
        capture(app, "chat-first-reply-purple")
        app.buttons["A cozy forest adventure"].tap()
        XCTAssertTrue(app.staticTexts["A cozy forest adventure"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["chat.generateConcepts"].waitForExistence(timeout: 20))
        app.terminate()
    }
    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists, element.frame.midY > 135, element.frame.midY < app.frame.height - 265 { return }
            let down = element.exists && element.frame.midY < 135
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: down ? 0.30 : 0.65))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: down ? 0.65 : 0.30))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let screenshot = app.screenshot()
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/craft-ui-" + name + ".png"))
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
