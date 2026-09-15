import XCTest
import UIKit
@testable import CraftStudio

final class CraftProfileTests: XCTestCase {
    @MainActor func testAssetAvatarKeepsTransparencyAndPhotoEncodingStaysJPEG() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("profile.json")
        let profile = CraftProfile(fileURL: url)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100), format: format).image { context in
            UIColor.black.setFill(); context.fill(CGRect(x: 20, y: 20, width: 60, height: 60))
        }
        try profile.save(name: "Dog maker", avatar: image, assetID: "dog")
        let restored = CraftProfile(fileURL: url)
        XCTAssertEqual(Array(try XCTUnwrap(restored.record.avatarData).prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
        XCTAssertTrue(CraftForegroundProcessor.hasTransparency(try XCTUnwrap(restored.avatar?.cgImage)))
        try profile.save(name: "Dog maker", avatar: image, assetID: nil)
        XCTAssertEqual(Array(try XCTUnwrap(profile.record.avatarData).prefix(2)), [255, 216])
    }

    @MainActor func testNameAndAvatarPersistAndDefaultCanBeRestored() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("profile.json")
        let profile = CraftProfile(fileURL: url)
        XCTAssertEqual(profile.displayName(chinese: false), "My studio")
        XCTAssertEqual(profile.displayName(chinese: true), "我的工作室")
        XCTAssertNil(profile.avatar)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2000, height: 1000)).image { context in
            UIColor.green.setFill(); context.fill(CGRect(x: 0, y: 0, width: 2000, height: 1000))
        }
        try profile.save(name: "  Emerald Maker  ", avatar: image, assetID: "my-dragon")
        let restored = CraftProfile(fileURL: url)
        XCTAssertEqual(restored.record.displayName, "Emerald Maker")
        XCTAssertEqual(restored.record.avatarAssetID, "my-dragon")
        XCTAssertNotNil(restored.avatar)
        XCTAssertLessThanOrEqual(restored.avatar!.size.width, 768)
        try restored.save(name: "Emerald Maker", avatar: nil, assetID: nil)
        let defaultAgain = CraftProfile(fileURL: url)
        XCTAssertNil(defaultAgain.avatar)
        XCTAssertNil(defaultAgain.record.avatarAssetID)
        XCTAssertEqual(defaultAgain.record.displayName, "Emerald Maker")
    }

    @MainActor func testInvalidNameDoesNotOverwriteSavedProfileAndCorruptFileFallsBack() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("profile.json")
        let profile = CraftProfile(fileURL: url)
        try profile.save(name: "My dragon", avatar: nil, assetID: nil)
        XCTAssertThrowsError(try profile.save(name: "  ", avatar: nil, assetID: nil))
        XCTAssertThrowsError(try profile.save(name: String(repeating: "a", count: 33), avatar: nil, assetID: nil))
        XCTAssertEqual(CraftProfile(fileURL: url).record.displayName, "My dragon")
        try Data("invalid file".utf8).write(to: url)
        XCTAssertEqual(CraftProfile(fileURL: url).displayName(chinese: false), "My studio")
    }
}
