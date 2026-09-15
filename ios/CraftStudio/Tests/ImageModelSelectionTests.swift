import XCTest
@testable import CraftStudio

final class ImageModelSelectionTests: XCTestCase {
    @MainActor func testRendererChangesRequestIdentityAndPreservesLegacyRetry() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = CraftStore(pendingURL: url)
        let previous = store.imageModelID
        let previousPlanner = store.plannerModelID
        defer { store.imageModelID = previous; store.plannerModelID = previousPlanner }
        store.plannerModelID = CraftPlannerModel.defaultID
        store.imageModelID = CraftImageModel.defaultID
        let gemini = store.imagePayload(["count": 4])
        XCTAssertEqual(gemini["imageModel"] as? String, "gemini-3-pro-image")
        store.imageModelID = "codex-gpt-image-2"
        let openAI = store.imagePayload(["count": 4])
        XCTAssertEqual(openAI["imageModel"] as? String, "codex-gpt-image-2")
        let pending = try PendingGeneration.make(base: store.apiBase, path: "/projects/p/concepts", projectID: "p", payload: gemini)
        XCTAssertFalse(pending.matches(base: store.apiBase, path: pending.requestPath, payload: openAI))
        let legacy = try PendingGeneration.make(base: store.apiBase, path: pending.requestPath, projectID: "p", payload: ["count": 4])
        try store.persistPending(legacy)
        store.imageModelID = CraftImageModel.defaultID
        XCTAssertTrue(legacy.matches(base: store.apiBase, path: legacy.requestPath, payload: store.imagePayload(["count": 4])))
    }

    @MainActor func testUnavailableRendererCannotCreateProjectOrPendingCharge() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let store = CraftStore(pendingURL: url)
        let previous = store.imageModelID
        defer { store.imageModelID = previous }
        store.imageModelID = "codex-gpt-image-2"
        store.imageModelsLoaded = true
        let previousPrompt = store.draftPrompt
        defer { store.draftPrompt = previousPrompt }
        store.draftPrompt = "A small test character"
        store.connected = true
        store.wallet.available = 1000
        let result = await store.createConcepts(count: 4)
        XCTAssertNil(result)
        XCTAssertNil(store.pendingGeneration)
        XCTAssertNotNil(store.error)
        XCTAssertEqual(store.wallet.available, 1000)
    }

    @MainActor func testLoginPublishesImageReadinessBeforeCancellingPollTask() async throws {
        let store = CraftStore(pendingURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let previous = store.imageModelID
        defer { store.imageModelID = previous }
        store.imageModelID = "codex-gpt-image-2"
        store.imageModels = CraftImageModel.placeholders
        store.aiLogin = CraftAILogin(["loginId":"test-login", "userCode":"TEST-CODE", "verificationUrl":"https://auth.openai.com/codex/device"])
        // No follow-up network request can complete after SwiftUI cancels this task.
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            store.applyAIAccount(["available":true, "connected":true, "imageGenerationSupported":true,
                "models":[["id":"gpt-5.6-sol", "reasoningEfforts":["low"]]]])
        }
        await task.value
        XCTAssertTrue(store.aiAccount.connected)
        XCTAssertTrue(store.selectedImageModel?.available == true)
        XCTAssertNil(store.selectedImageModel?.unavailableReason)
        XCTAssertNil(store.aiLogin)
        // Refresh still updates capability even when the connected flag is unchanged.
        store.applyAIAccount(["available":true, "connected":true, "imageGenerationSupported":false])
        XCTAssertFalse(store.selectedImageModel?.available == true)
        store.applyAIAccount(["available":true, "connected":true, "imageGenerationSupported":true])
        XCTAssertTrue(store.selectedImageModel?.available == true)
        store.applyAIAccount(["available":true, "connected":false])
        XCTAssertFalse(store.selectedImageModel?.available == true)
    }

    func testConceptPreservesActualRendererAndLegacyConceptStillLoads() {
        let concept = CraftConcept(["id": "c", "imageModel": "gpt-image-2.5-sunburst", "imageProvider": "OpenAI"], base: "http://localhost")
        XCTAssertEqual(concept.imageModel, "gpt-image-2.5-sunburst")
        XCTAssertEqual(concept.imageProvider, "OpenAI")
        XCTAssertNil(CraftConcept(["id": "old"], base: "http://localhost").imageModel)
    }
}
