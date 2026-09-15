import XCTest
@testable import CraftStudio

final class ConceptModelActivityTests: XCTestCase {
    @MainActor func testAcceptedJobAppearsImmediatelyAndCompletionCannotRegress() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = CraftStore(pendingURL: url)
        store.jobs = []
        let queued = CraftJob(["id":"new", "projectId":"p", "kind":"model", "status":"queued", "selectedConceptId":"front"], base:store.apiBase)
        store.acceptJob(queued)
        XCTAssertEqual(store.jobs.first?.selectedConceptId, "front")
        XCTAssertTrue(store.jobs.first?.isActive == true)
        var pending = try PendingGeneration.make(base:store.apiBase, path:"/concepts/front/model", projectID:"p", payload:["engine":"rodin"])
        pending.jobID = "new"; try store.persistPending(pending)
        let done = CraftJob(["id":"new", "projectId":"p", "kind":"model", "status":"done", "progress":100], base:store.apiBase)
        store.acceptJob(done)
        try store.resolvePending(from:store.jobs)
        XCTAssertNil(store.pendingGeneration)
        store.acceptJob(queued)
        XCTAssertEqual(store.jobs.count, 1)
        XCTAssertEqual(store.jobs.first?.status, "done")
        XCTAssertEqual(store.jobs.first?.progress, 100)
    }

    @MainActor func testNewJobImageCanBeSelectedBeforeProjectRefresh() {
        let store = CraftStore()
        let project = CraftProject(["id":"selection-fixture-project", "concepts":[]], base:store.apiBase)
        let concept = CraftConcept(["id":"selection-fixture-image", "projectId":project.id, "imageUrl":"/image.png"], base:store.apiBase)
        let key = "craftSelectedConcept:" + store.apiBase + ":" + project.id
        defer { UserDefaults.standard.removeObject(forKey:key) }
        store.jobs = [CraftJob(["id":"image-job", "projectId":project.id, "status":"done", "concepts":[["id":concept.id, "projectId":project.id, "imageUrl":"/image.png"]]], base:store.apiBase)]
        store.selectConcept(concept)
        XCTAssertEqual(store.selectedConcept(in:project)?.id, concept.id)
        XCTAssertNil(store.selectedConcept(in:CraftProject(["id":"another-project"], base:store.apiBase)))
    }

    private func concept(_ id: String) -> CraftConcept {
        CraftConcept(["id": id, "projectId": "p", "imageUrl": "/images/\(id).png"], base: "http://localhost")
    }
    private func job(_ id: String, kind: String = "model", source: String? = "front", status: String = "running",
                     image: String? = nil, project: String = "p") -> CraftJob {
        var values: [String: Any] = ["id": id, "projectId": project, "kind": kind, "status": status]
        if let source { values["selectedConceptId"] = source }
        if let image { values["selectedImageUrl"] = image }
        return CraftJob(values, base: "http://localhost")
    }

    func testModelReturnsItsSubmittedSourceNotAnotherModelsConcept() {
        let asset = CraftAsset(id: "model-a", name: "Dog")
        let own = CraftJob(["id":"own", "kind":"model", "projectId":"p", "selectedImageUrl":"/original.png", "assets":[["id":"model-a"]]], base:"http://localhost")
        let other = CraftJob(["id":"other", "kind":"model", "projectId":"p", "selectedImageUrl":"/newer.png", "assets":[["id":"model-b"]]], base:"http://localhost")
        XCTAssertEqual(ConceptModelActivity.sourceImage(for: asset, jobs:[other, own], projects:[])?.absoluteString, "http://localhost/original.png")
        XCTAssertNil(ConceptModelActivity.sourceImage(for: asset, jobs:[other], projects:[]))
        let legacy = CraftJob(["id":"legacy", "kind":"model", "projectId":"p", "selectedConceptId":"front", "assets":[["id":"model-a"]]], base:"http://localhost")
        let project = CraftProject(["id":"p", "concepts":[["id":"front", "imageUrl":"/front.png"], ["id":"back", "imageUrl":"/back.png"]]], base:"http://localhost")
        XCTAssertEqual(ConceptModelActivity.sourceImage(for: asset, jobs:[legacy], projects:[project])?.absoluteString, "http://localhost/front.png")
    }

    func testAutoOpenOnlyWatchedCompletedModelsAndOnlyOnce() {
        let complete = CraftJob(["id":"new", "kind":"model", "status":"done", "assets":[["id":"a", "modelUrl":"/dog.glb"]]], base:"http://localhost")
        XCTAssertNotNil(ConceptModelActivity.completedForPresentation(jobs:[complete], watching:["new"], opened:[]))
        XCTAssertNil(ConceptModelActivity.completedForPresentation(jobs:[complete], watching:[], opened:[]))
        XCTAssertNil(ConceptModelActivity.completedForPresentation(jobs:[complete], watching:["new"], opened:["new"]))
        for state in ["running", "queued", "failed", "partial"] {
            var unfinished = complete; unfinished.status = state
            XCTAssertNil(ConceptModelActivity.completedForPresentation(jobs:[unfinished], watching:["new"], opened:[]))
        }
        var noModel = complete; noModel.assets = []
        XCTAssertNil(ConceptModelActivity.completedForPresentation(jobs:[noModel], watching:["new"], opened:[]))
    }

    func testOnlyActualModelSourceAnimates() {
        let jobs = [job("model")]
        XCTAssertTrue(ConceptModelActivity.isWorking(on: concept("front"), jobs: jobs, submittingID: nil))
        XCTAssertFalse(ConceptModelActivity.isWorking(on: concept("back"), jobs: jobs, submittingID: nil))
        XCTAssertFalse(ConceptModelActivity.isWorking(on: concept("front"), jobs: [job("concepts", kind: "concepts")], submittingID: nil))
        XCTAssertFalse(ConceptModelActivity.isWorking(on: concept("front"), jobs: [job("done", status: "done")], submittingID: nil))
        XCTAssertFalse(ConceptModelActivity.isWorking(on: concept("front"), jobs: [job("failed", status: "failed")], submittingID: nil))
        XCTAssertFalse(ConceptModelActivity.isWorking(on: concept("front"), jobs: [job("other", project: "elsewhere")], submittingID: nil))
    }

    func testConfirmationBridgesSubmissionWithoutChangingOtherCards() {
        XCTAssertTrue(ConceptModelActivity.isWorking(on: concept("back"), jobs: [], submittingID: "back"))
        XCTAssertFalse(ConceptModelActivity.isWorking(on: concept("front"), jobs: [], submittingID: "back"))
        XCTAssertFalse(ConceptModelActivity.isWorking(on: concept("back"), jobs: [], submittingID: nil))
    }

    func testSourceIDWinsOverLegacyURLAndNewestTerminalJobStopsAnimation() {
        let front = concept("front")
        XCTAssertNil(ConceptModelActivity.latestJob(for: front,
            jobs: [job("wrong", source: "back", image: front.imageUrl)]))
        XCTAssertNotNil(ConceptModelActivity.latestJob(for: front,
            jobs: [job("legacy", source: nil, image: front.imageUrl)]))
        XCTAssertFalse(ConceptModelActivity.isWorking(on: front,
            jobs: [job("latest", status: "failed"), job("older")], submittingID: nil))
    }
}
