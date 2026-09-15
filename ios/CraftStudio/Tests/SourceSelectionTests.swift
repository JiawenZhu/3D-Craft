import XCTest
import UIKit
@testable import CraftStudio

final class SourceSelectionTests: XCTestCase {
    private let legacyPrompt = "A brave ginger tabby adventurer wearing a teal jacket, full body, one character, clean background"

    func testNonCatSourceAndAssetParsingPreservesIdentityAndProvenance() {
        let projectID = "source-test-\(UUID().uuidString)"
        let base = "http://127.0.0.1:8001"
        let concept = CraftConcept([
            "id": "motorcycle-rear", "projectId": projectID,
            "name": "Cobalt motorcycle — rear view", "prompt": "Keep the two wheels and blue bodywork",
            "imageUrl": "/files/mobile/motorcycle-rear.png", "width": 2048, "height": 2048,
            "isOriginal": false, "direction": "back", "label": "Rear",
            "parentId": "motorcycle-original", "viewSetId": "bike-turnaround"
        ], base: base)
        XCTAssertEqual(concept.id, "motorcycle-rear")
        XCTAssertEqual(concept.projectId, projectID)
        XCTAssertEqual(concept.name, "Cobalt motorcycle — rear view")
        XCTAssertEqual(concept.imageUrl, base + "/files/mobile/motorcycle-rear.png")
        XCTAssertEqual(concept.width, 2048)
        XCTAssertEqual(concept.isOriginal, false)
        XCTAssertEqual(concept.direction, "back")
        XCTAssertEqual(concept.label, "Rear")
        XCTAssertEqual(concept.parentId, "motorcycle-original")
        XCTAssertEqual(concept.viewSetId, "bike-turnaround")

        let asset = CraftAsset([
            "id": "motorcycle-model", "name": "Cobalt racing motorcycle", "kind": "vehicle",
            "modelUrl": "/files/motorcycle-model/model.glb", "thumbUrl": "/files/mobile/motorcycle-rear.png",
            "faces": 48000, "fileSizeMb": 7.5
        ], base: base)
        XCTAssertEqual(asset.id, "motorcycle-model")
        XCTAssertEqual(asset.name, "Cobalt racing motorcycle")
        XCTAssertEqual(asset.kind, "vehicle")
        XCTAssertEqual(asset.modelURL?.absoluteString, base + "/files/motorcycle-model/model.glb")
        XCTAssertEqual(asset.thumbURL?.absoluteString, concept.imageUrl)
        XCTAssertFalse(asset.isExample)
    }

    @MainActor func testSingleImageModelPayloadOmitsEmptyMultiViewSelection() {
        let payload = CraftStore.modelPayload(engine: "rodin", quality: "default", effort: "high", conceptIds: [])
        XCTAssertNil(payload["conceptIds"], "Single-image requests must omit this field; an empty array violates the backend minimum.")
        XCTAssertEqual(payload["engine"] as? String, "rodin")
        XCTAssertEqual(payload["quality"] as? String, "default")
        XCTAssertEqual(payload["effort"] as? String, "high")
    }

    @MainActor func testMultiViewModelPayloadPreservesExactOrderedIDsAndSettings() {
        let selected = ["bike-front-02", "bike-back-04", "bike-left-01"]
        let payload = CraftStore.modelPayload(engine: "hunyuan3d-2.1", quality: "speedy", effort: "medium", conceptIds: selected)
        XCTAssertEqual(payload["conceptIds"] as? [String], selected)
        XCTAssertEqual(payload["engine"] as? String, "hunyuan3d-2.1")
        XCTAssertEqual(payload["quality"] as? String, "speedy")
        XCTAssertEqual(payload["effort"] as? String, "medium")
    }

    func testJobMetadataRetainsSelectedNonCatImageAndInvalidViewWarning() {
        let base = "http://127.0.0.1:8001"
        let job = CraftJob([
            "id": "bike-job", "projectId": "bike-project", "kind": "model", "status": "running",
            "stage": "geometry", "coreConcept": "A blue motorcycle with two wheels",
            "selectedImageUrl": "/files/mobile/bike-side.png", "selectedConceptId": "bike-side",
            "validation": ["usable": false], "warnings": ["Rear view changed the wheel spacing"],
            "concepts": [["id": "bike-side", "projectId": "bike-project", "imageUrl": "/files/mobile/bike-side.png", "direction": "left", "isOriginal": false]]
        ], base: base)
        XCTAssertEqual(job.stage, "geometry")
        XCTAssertEqual(job.coreConcept, "A blue motorcycle with two wheels")
        XCTAssertEqual(job.selectedImageUrl, base + "/files/mobile/bike-side.png")
        XCTAssertEqual(job.selectedConceptId, "bike-side")
        XCTAssertEqual(job.viewsUsable, false)
        XCTAssertEqual(job.warnings, ["Rear view changed the wheel spacing"])
        XCTAssertEqual(job.concepts?.first?.direction, "left")
        XCTAssertEqual(job.concepts?.first?.imageUrl, job.selectedImageUrl)
    }

    @MainActor func testExplicitSecondSelectionPersistsAcrossStoreRecreationAndDoesNotFallBack() throws {
        try preservingDraftAndDefaults { pendingURL in
            let base = "http://127.0.0.1:8001/source-tests-\(UUID().uuidString)"
            let project = self.project()
            let first = CraftStore(pendingURL: pendingURL)
            first.apiBase = base
            first.projects = [project]
            // A nonempty list is not authorization to use its first image.
            XCTAssertNil(first.selectedConcept(in: project))
            first.selectConcept(project.concepts[1])
            XCTAssertEqual(first.selectedConcept(in: project)?.id, project.concepts[1].id)
            XCTAssertEqual(first.selectedConcept(in: project)?.imageUrl, project.concepts[1].imageUrl)

            let reopened = CraftStore(pendingURL: pendingURL)
            reopened.apiBase = base
            reopened.projects = [project]
            XCTAssertEqual(reopened.selectedConcept(in: project)?.id, project.concepts[1].id)
            // A removed source must not silently change the user's choice to image one.
            var missingSelection = project
            missingSelection.concepts = [project.concepts[0]]
            XCTAssertNil(reopened.selectedConcept(in: missingSelection))
            reopened.apiBase = base + "-other-workspace"
            XCTAssertNil(reopened.selectedConcept(in: project))
        }
    }

    @MainActor func testSelectionFromAnotherProjectDoesNotSelectAnUnrelatedFirstImage() throws {
        try preservingDraftAndDefaults { pendingURL in
            let store = CraftStore(pendingURL: pendingURL)
            store.apiBase = "http://127.0.0.1:8001/source-tests-\(UUID().uuidString)"
            let first = self.project()
            let other = self.project()
            store.projects = [first, other]
            store.selectConcept(first.concepts[1])
            XCTAssertNil(store.selectedConcept(in: other))
        }
    }

    @MainActor func testChoosingPhotoClearsOnlyExactLegacyDemoPrompt() throws {
        try preservingDraftAndDefaults { pendingURL in
            let store = CraftStore(pendingURL: pendingURL)
            let photo = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
                UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
            }
            store.draftPrompt = self.legacyPrompt
            store.saveDraftImage(photo)
            XCTAssertEqual(store.draftPrompt, "")
            XCTAssertNotNil(store.draftImage)

            let custom = "A cobalt motorcycle with two wheels and a brown leather seat"
            store.draftPrompt = custom
            store.saveDraftImage(photo)
            XCTAssertEqual(store.draftPrompt, custom)
            XCTAssertEqual(UserDefaults.standard.string(forKey: "craftDraftPrompt"), custom)

            let intentionalExtension = self.legacyPrompt + "; add a red scarf"
            store.draftPrompt = intentionalExtension
            store.saveDraftImage(photo)
            XCTAssertEqual(store.draftPrompt, intentionalExtension)
        }
    }

    @MainActor func testModelPromptIsIncludedWithSelectedViewsAndExplicitBlankIsPreserved() {
        let payload = CraftStore.modelPayload(engine: "rodin", quality: "default", effort: "high", conceptIds: ["front", "back"], modelPrompt: "保留面部特征和眼镜")
        XCTAssertEqual(payload["modelPrompt"] as? String, "保留面部特征和眼镜")
        XCTAssertEqual(payload["conceptIds"] as? [String], ["front", "back"])
        let blank = CraftStore.modelPayload(engine: "rodin", quality: "default", effort: "high", conceptIds: [], modelPrompt: "")
        XCTAssertEqual(blank["modelPrompt"] as? String, "")
    }

    @MainActor func testRelaunchClearsLegacyPromptButPreservesCustomPrompt() throws {
        try preservingDraftAndDefaults { pendingURL in
            UserDefaults.standard.set(self.legacyPrompt, forKey: "craftDraftPrompt")
            let migrated = CraftStore(pendingURL: pendingURL)
            XCTAssertEqual(migrated.draftPrompt, "")
            XCTAssertNotEqual(UserDefaults.standard.string(forKey: "craftDraftPrompt"), self.legacyPrompt)
            let custom = "A tiny ceramic lighthouse with a red roof"
            UserDefaults.standard.set(custom, forKey: "craftDraftPrompt")
            let ordinary = CraftStore(pendingURL: pendingURL)
            XCTAssertEqual(ordinary.draftPrompt, custom)
        }
    }

    private func project() -> CraftProject {
        let id = "selection-test-\(UUID().uuidString)"
        return CraftProject([
            "id": id, "name": "Cobalt motorcycle", "prompt": "Keep the blue bodywork", "style": "Realistic",
            "imageUrl": "/files/mobile/\(id)-original.png",
            "concepts": [
                ["id": "\(id)-original", "projectId": id, "name": "Original motorcycle", "imageUrl": "/files/mobile/\(id)-original.png", "isOriginal": true],
                ["id": "\(id)-second", "projectId": id, "name": "Motorcycle side concept", "imageUrl": "/files/mobile/\(id)-second.png", "isOriginal": false]
            ]
        ], base: "http://127.0.0.1:8001")
    }

    /// Synchronous MainActor tests cannot interleave preference mutations. Restore
    /// only keys these stores changed, along with the existing draft photo bytes.
    @MainActor private func preservingDraftAndDefaults(_ body: (URL) throws -> Void) throws {
        let defaults = UserDefaults.standard
        let before = defaults.dictionaryRepresentation().filter { $0.key == "craftDraftPrompt" || $0.key == "craftAPI" || $0.key.hasPrefix("craftSelectedConcept:") }
        let draftURL = CraftStore.draftURL
        let oldPhoto = try? Data(contentsOf: draftURL)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("source-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            let after = defaults.dictionaryRepresentation().filter { $0.key == "craftDraftPrompt" || $0.key == "craftAPI" || $0.key.hasPrefix("craftSelectedConcept:") }
            for key in Set(before.keys).union(after.keys) {
                if let value = before[key] { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
            if let oldPhoto { try? oldPhoto.write(to: draftURL, options: .atomic) }
            else { try? FileManager.default.removeItem(at: draftURL) }
            try? FileManager.default.removeItem(at: folder)
        }
        try body(folder.appendingPathComponent("pending.json"))
    }
}
