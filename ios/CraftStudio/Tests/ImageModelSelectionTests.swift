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
        XCTAssertEqual(gemini["imageModel"] as? String, "gemini-3.1-flash-image", "new concepts default to the fast renderer")
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

    @MainActor func testPendingConceptKeepsApprovedPriceAndNewRequestUsesCurrentPrice() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = CraftStore(pendingURL: url)
        let previous = (store.imageModelID, store.plannerModelID)
        defer { store.imageModelID = previous.0; store.plannerModelID = previous.1 }
        store.imageModelID = CraftImageModel.defaultID
        store.plannerModelID = CraftPlannerModel.defaultID
        var approved = store.imagePayload(["count": 1])
        approved["maxTokens"] = 20
        let pending = try PendingGeneration.make(base: store.apiBase, path: "/projects/p/concepts", projectID: "p", payload: approved)
        try store.persistPending(pending)
        let retry = store.imagePayload(["count": 1])
        XCTAssertEqual(retry["maxTokens"] as? Int, 20)
        XCTAssertTrue(pending.matches(base: store.apiBase, path: pending.requestPath, payload: retry))
        XCTAssertFalse(pending.matches(base: store.apiBase, path: pending.requestPath, payload: store.imagePayload(["count": 2])))
        XCTAssertEqual(store.pendingGeneration?.body, pending.body)
        try store.persistPending(nil)
        XCTAssertEqual(store.imagePayload(["count": 1])["maxTokens"] as? Int, store.conceptTokenCost(count: 1))
    }

    func testGeminiReleaseMigratesSelectionWithoutRewritingSavedChatGPTRequest() throws {
        XCTAssertFalse(CraftAIAccount.enabledForRelease)
        XCTAssertEqual(CraftImageModel.restoredSelection("codex-gpt-image-2"), CraftImageModel.defaultID)
        let pending = try PendingGeneration.make(base: StudioConnection.cloudURL, path: "/projects/p/concepts", projectID: "p", payload: ["count": 1, "imageModel": "codex-gpt-image-2", "maxTokens": 0])
        let restored = try JSONDecoder().decode(PendingGeneration.self, from: JSONEncoder().encode(pending))
        XCTAssertEqual(restored.body, pending.body)
        XCTAssertFalse(restored.matches(base: StudioConnection.cloudURL, path: pending.requestPath, payload: ["count": 1, "imageModel": CraftImageModel.defaultID, "maxTokens": 33]))
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

    func testFastIsDefaultButAChosenProSurvivesRelaunch() {
        XCTAssertEqual(CraftImageModel.defaultID, "gemini-3.1-flash-image")
        XCTAssertEqual(CraftImageModel.restoredSelection(nil), CraftImageModel.defaultID)
        XCTAssertEqual(CraftImageModel.restoredSelection(CraftImageModel.proID), CraftImageModel.proID)
        XCTAssertEqual(CraftImageModel.placeholders.map(\.id).prefix(2), [CraftImageModel.defaultID, CraftImageModel.proID])
    }

    @MainActor func testOfflineQuoteMatchesServerCapForEachRenderer() {
        let store = CraftStore(pendingURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let previous = store.imageModelID
        defer { store.imageModelID = previous }
        // server: cloud_concept_provider.quote(now, n, model)["maxTokens"]
        store.imageModelID = CraftImageModel.defaultID
        XCTAssertEqual((1...4).map { store.conceptTokenCost(count: $0) }, [14, 28, 40, 52])
        store.imageModelID = CraftImageModel.proID
        XCTAssertEqual((1...4).map { store.conceptTokenCost(count: $0) }, [33, 66, 97, 128])
    }

    @MainActor func testServerWithoutFastModelKeepsCreatorOnPro() {
        let store = CraftStore(pendingURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let previous = store.imageModelID
        defer { store.imageModelID = previous }
        UserDefaults.standard.removeObject(forKey: "craftImageModel")
        store.imageModelID = CraftImageModel.defaultID
        UserDefaults.standard.removeObject(forKey: "craftImageModel")
        store.adoptImageModels([CraftImageModel(id: CraftImageModel.proID, name: "Gemini 3 Pro Image", provider: "google",
                                                available: true, quality: "Pro", imageSize: "2K", unavailableReason: nil)])
        XCTAssertEqual(store.imageModelID, CraftImageModel.proID, "an older studio keeps working on Pro")
        XCTAssertNil(UserDefaults.standard.string(forKey: "craftImageModel"), "the fallback is not saved, so Fast returns later")
        XCTAssertEqual(CraftImageModel.restoredSelection(UserDefaults.standard.string(forKey: "craftImageModel")), CraftImageModel.defaultID)
    }

    func testConceptPreservesActualRendererAndLegacyConceptStillLoads() {
        let concept = CraftConcept(["id": "c", "imageModel": "gpt-image-2.5-sunburst", "imageProvider": "OpenAI"], base: "http://localhost")
        XCTAssertEqual(concept.imageModel, "gpt-image-2.5-sunburst")
        XCTAssertEqual(concept.imageProvider, "OpenAI")
        XCTAssertNil(CraftConcept(["id": "old"], base: "http://localhost").imageModel)
    }
}
