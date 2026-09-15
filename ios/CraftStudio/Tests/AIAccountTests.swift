import XCTest
@testable import CraftStudio

final class AIAccountTests: XCTestCase {
    @MainActor func testGPT6CanBeSelectedWhenReturnedByAccountCatalog() {
        let store = CraftStore(pendingURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let previous = store.plannerModelID; let effort = store.plannerEffort
        defer { store.plannerModelID = previous; store.plannerEffort = effort }
        store.applyAIAccount(["available":true, "connected":true, "models":[["id":"gpt-6-astra", "name":"GPT-6 Astra", "reasoningEfforts":["low","medium"]]]])
        store.selectPlanner("gpt-6-astra")
        XCTAssertEqual(store.selectedPlannerModel?.id, "gpt-6-astra")
        XCTAssertEqual(store.plannerEffort, "low")
        XCTAssertEqual(store.imagePayload([:])["plannerModel"] as? String, "gpt-6-astra")
    }
    func testDeviceCodeOnlyOpensOfficialHTTPSVerificationAndHasBoundedWait() throws {
        let now = Date(timeIntervalSince1970: 1000)
        let valid = try XCTUnwrap(CraftAILogin(["loginId": "l", "userCode": "ABCD", "verificationUrl": "https://auth.openai.com/codex/device"], now: now))
        XCTAssertEqual(valid.deadline.timeIntervalSince(now), 300)
        for bad in ["http://auth.openai.com/device", "https://openai.com.attacker.test/device", "https://attacker.test/openai.com", "https://user@auth.openai.com/device"] {
            XCTAssertNil(CraftAILogin(["loginId": "l", "userCode": "ABCD", "verificationUrl": bad]))
        }
    }

    func testDisconnectedAccountCannotSupplyAvailableModels() {
        let data: [String: Any] = ["available": true, "connected": false,
            "models": [["id": "gpt-5.6", "name": "GPT 5.6", "reasoningEfforts": ["low"]]]]
        XCTAssertTrue(CraftAIAccount(data).models.isEmpty)
        XCTAssertFalse(CraftAIAccount(data).imageGenerationSupported)
    }

    @MainActor func testPlannerChangesIdentityAndPreservesDefaultLegacyRetry() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = CraftStore(pendingURL: url)
        let old = (store.imageModelID, store.plannerModelID, store.plannerEffort)
        defer { store.imageModelID = old.0; store.plannerModelID = old.1; store.plannerEffort = old.2 }
        store.imageModelID = CraftImageModel.defaultID; store.plannerModelID = CraftPlannerModel.defaultID
        let defaults = store.imagePayload(["count": 4])
        XCTAssertNil(defaults["plannerModel"]); XCTAssertNil(defaults["plannerEffort"])
        let legacy = try PendingGeneration.make(base: store.apiBase, path: "/projects/p/concepts", projectID: "p", payload: ["count": 4])
        try store.persistPending(legacy)
        XCTAssertTrue(legacy.matches(base: store.apiBase, path: legacy.requestPath, payload: store.imagePayload(["count": 4])))
        store.aiAccount = CraftAIAccount(["available": true, "connected": true,
            "models": [["id": "gpt-5.6", "name": "GPT 5.6", "reasoningEfforts": ["low", "high"]]]])
        store.selectPlanner("gpt-5.6")
        XCTAssertEqual(store.plannerEffort, "low")
        let changed = store.imagePayload(["count": 4])
        XCTAssertEqual(changed["plannerModel"] as? String, "gpt-5.6")
        XCTAssertEqual(changed["plannerEffort"] as? String, "low")
        XCTAssertFalse(legacy.matches(base: store.apiBase, path: legacy.requestPath, payload: changed))
        XCTAssertEqual(store.pendingGeneration?.body, legacy.body)
        store.selectPlanner("made-up-model")
        XCTAssertEqual(store.plannerModelID, "gpt-5.6", "Only actual account models are selectable.")
    }

    func testRemovedImageProviderMigratesSelectionButHistoricalPendingStaysExact() throws {
        XCTAssertEqual(CraftImageModel.restoredSelection("gpt-image-2.5-sunburst"), CraftImageModel.defaultID)
        XCTAssertEqual(CraftImageModel.placeholders.map(\.id), [CraftImageModel.defaultID, "codex-gpt-image-2"])
        let pending = try PendingGeneration.make(base: "http://localhost", path: "/projects/p/concepts", projectID: "p", payload: ["imageModel": "gpt-image-2.5-sunburst", "count": 4])
        let restored = try JSONDecoder().decode(PendingGeneration.self, from: JSONEncoder().encode(pending))
        XCTAssertEqual(restored.body, pending.body)
        XCTAssertEqual(restored.idempotencyKey, pending.idempotencyKey)
    }
}
