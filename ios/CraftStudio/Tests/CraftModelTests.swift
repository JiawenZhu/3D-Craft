import XCTest
@testable import CraftStudio
final class CraftModelTests:XCTestCase {
    @MainActor func testPurchaseIsNotMarkedPresentedUntilWalletShowsIt() {
        let store = CraftStore()
        let key = "craft.test.purchase:" + UUID().uuidString
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let receipt = CraftStore.PurchaseCelebration(tokens: 200, balance: 700, presentationKey: key)
        store.purchaseToPresent = receipt
        store.presentPurchasedWallet()
        XCTAssertEqual(store.path.last, .wallet)
        XCTAssertEqual(store.walletCelebration?.tokens, 200)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: key))
        store.markPurchaseAnimationVisible(receipt)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: key))
    }
    @MainActor func testStaleAnimationCannotAcknowledgeAnotherReceipt() {
        let store = CraftStore()
        let key = "craft.test.purchase:" + UUID().uuidString
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let stale = CraftStore.PurchaseCelebration(tokens: 200, balance: 200, presentationKey: key)
        store.walletCelebration = CraftStore.PurchaseCelebration(tokens: 500, balance: 700)
        store.markPurchaseAnimationVisible(stale)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: key))
    }

    @MainActor func testModelTokensComeFromServerAndUnknownIsNotFree() throws {
        let store = CraftStore()
        store.modelPrices = try JSONDecoder().decode([String: CraftModelPrice].self, from: Data(#"{"rodin":{"name":"Rodin","unit":"generation","texturedCredits":46,"multiTexturedCredits":46,"note":"","noteZh":"","source":""},"trellis-2":{"name":"TRELLIS","unit":"generation","texturedCredits":3,"note":"","noteZh":"","source":""}}"#.utf8))
        XCTAssertEqual(store.modelTokenCost("rodin"), 46)
        XCTAssertEqual(store.modelTokenCost("rodin", views: 4), 46)
        XCTAssertEqual(store.modelTokenCost("trellis-2"), 3)
        XCTAssertNil(store.modelTokenCost("trellis-2", views: 3))
        XCTAssertNil(store.modelTokenCost("missing"))
    }

    func testEveryBuildUsesCloudAndIgnoresStaleLocalSettings() {
        for simulator in [true, false] {
            for saved in [nil, "http://127.0.0.1:8001", "http://192.168.1.10:8002/private-test-path", "https://studio.example.com"] {
                XCTAssertEqual(StudioConnection.initial(saved: saved, configured: "http://localhost:8001", simulator: simulator), "https://3d-craft.web.app")
            }
        }
    }

    func testPublicCategoriesNeverIncludeOwnedOrLegacyCreations() {
        let dog = CraftAsset(id: "my-dog", name: "A cut dog", kind: "character")
        let tree = CraftAsset(id: "my-tree", name: "My tree", kind: "world")
        let oldDog = CraftAsset(id: "old-dog", name: "A cut dog", isExample: true)
        var cat = CraftAsset(id: "public-cat", name: "Lantern Explorer", isExample: true)
        cat.galleryExample = true
        var island = CraftAsset(id: "public-island", name: "Coconut Island", kind: "world", isExample: true)
        island.galleryExample = true
        let owned = [dog, tree]
        let examples = [oldDog, cat, island, cat]
        XCTAssertEqual(GalleryHomeCategory.characters.assets(owned: owned, examples: examples).map(\.id), [cat.id])
        XCTAssertEqual(GalleryHomeCategory.objects.assets(owned: owned, examples: examples).map(\.id), [island.id])
        XCTAssertEqual(GalleryHomeCategory.userCreated.assets(owned: owned, examples: examples).map(\.id), [dog.id, tree.id])
        XCTAssertTrue(GalleryHomeCategory.characters.assets(owned: owned, examples: [oldDog]).isEmpty)
    }

    func testCuratedExampleRetainsSourceAndOrderingInCache() throws {
        let asset = CraftAsset(["id": "real-cat", "name": "Lantern Explorer", "kind": "character",
            "modelUrl": "/files/cat.glb", "sourceImageUrl": "/files/gallery-samples/lantern-explorer.png",
            "galleryExample": ["slug": "lantern-explorer", "batchId": "gallery-20260911"]],
            base: "http://127.0.0.1:8001", example: true)
        let cached = try JSONDecoder().decode(CraftAsset.self, from: JSONEncoder().encode(asset))
        XCTAssertEqual(cached.galleryExample, true)
        XCTAssertEqual(cached.galleryOrder, 0)
        XCTAssertEqual(cached.sourceImageURL?.absoluteString, "http://127.0.0.1:8001/files/gallery-samples/lantern-explorer.png")
        XCTAssertNotNil(cached.modelURL)
        XCTAssertTrue(cached.isExample)
    }
    func testSpendingSeparatesSettlementReservationAndMissingHistory() {
        func job(_ id: String, _ kind: String, _ status: String, _ charged: Int?, _ reserved: Int, project: String = "p") -> CraftJob {
            var data: [String: Any] = ["id": id, "kind": kind, "status": status, "reserved": reserved, "projectId": project]
            if let charged { data["charged"] = charged }
            return CraftJob(data, base: "http://localhost")
        }
        let image = job("i", "concepts", "done", 45, 0)
        let jobs = [image, image, job("m", "model", "running", 0, 55),
                    job("partial", "concepts", "error", 15, 0), job("old", "model", "done", nil, 0),
                    job("other", "model", "done", 55, 0, project: "other")]
        let summary = CraftSpendSummary(jobs: jobs, projectID: "p")
        XCTAssertEqual(summary.spent, 60)
        XCTAssertEqual(summary.reserved, 55)
        XCTAssertEqual(summary.spent(model: false), 60)
        XCTAssertEqual(summary.spent(model: true), 0)
        XCTAssertEqual(summary.unrecorded, 1)
        XCTAssertEqual(CraftSpendSummary(jobs: jobs).spent, 115)
    }

    @MainActor func testBackgroundConnectionFailureDoesNotPresentModal() async {
        let store=CraftStore()
        store.connectionFailed(URLError(.cannotConnectToHost))
        XCTAssertFalse(store.connected)
        XCTAssertNotNil(store.connectionNotice)
        XCTAssertNil(store.error)
    }

    @MainActor func testUncertainModelSubmissionReusesKeyAcrossRetryAndRelaunch() async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer{try?FileManager.default.removeItem(at:folder)}
        let url=folder.appendingPathComponent("pending.json")
        let concept=CraftConcept(["id":"selected-cat","projectId":"saved-project"],base:"http://127.0.0.1:9")
        let first=CraftStore(pendingURL:url);first.apiBase="http://127.0.0.1:9";first.wallet.available=100
        first.modelPrices = try JSONDecoder().decode([String: CraftModelPrice].self, from: Data(#"{"rodin":{"name":"Rodin","unit":"generation","texturedCredits":46,"note":"","noteZh":"","source":""}}"#.utf8))
        await first.generateModel(concept)
        let original=try XCTUnwrap(first.pendingGeneration)
        XCTAssertEqual(original.projectID,"saved-project")
        XCTAssertNil(original.jobID)
        // Zero currently available credit must not prevent checking the same
        // request: it may already have reserved the entire previous balance.
        first.wallet.available=0
        await first.generateModel(concept)
        XCTAssertEqual(first.pendingGeneration,original)
        let relaunched=CraftStore(pendingURL:url);relaunched.apiBase="http://127.0.0.1:9"
        XCTAssertEqual(relaunched.pendingGeneration,original)
        await relaunched.generateModel(concept)
        XCTAssertEqual(relaunched.pendingGeneration?.idempotencyKey,original.idempotencyKey)
        let different=CraftConcept(["id":"different-cat","projectId":"other-project"],base:"http://127.0.0.1:9")
        await relaunched.generateModel(different)
        XCTAssertEqual(relaunched.pendingGeneration,original)
    }

    @MainActor func testKnownTerminalJobPermitsNewExplicitGenerationKey() throws {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".json")
        defer{try?FileManager.default.removeItem(at:url)}
        let store=CraftStore(pendingURL:url)
        var pending=try PendingGeneration.make(base:store.apiBase,path:"/concepts/c/model",projectID:"p",payload:["engine":"rodin"])
        pending.jobID="confirmed-job";try store.persistPending(pending)
        try store.resolvePending(from:[CraftJob(["id":"confirmed-job","status":"running"],base:store.apiBase)])
        XCTAssertNotNil(store.pendingGeneration)
        try store.resolvePending(from:[CraftJob(["id":"confirmed-job","status":"done"],base:store.apiBase)])
        XCTAssertNil(store.pendingGeneration)
        XCTAssertFalse(FileManager.default.fileExists(atPath:url.path))
        let deliberateNew=try PendingGeneration.make(base:store.apiBase,path:"/concepts/c/model",projectID:"p",payload:["engine":"rodin"])
        XCTAssertNotEqual(deliberateNew.idempotencyKey,pending.idempotencyKey)
    }

    func testRelativeAssetURLKeepsMobileHost(){XCTAssertEqual(resolved("/files/mobile/cat.glb",base:"http://127.0.0.1:8001"),"http://127.0.0.1:8001/files/mobile/cat.glb")}
    func testAbsoluteModelURLIsPreserved(){XCTAssertEqual(resolved("https://example.com/a.glb",base:"http://127.0.0.1:8001"),"https://example.com/a.glb")}
}
