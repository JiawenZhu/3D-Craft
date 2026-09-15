import XCTest
import UIKit
@testable import CraftStudio

private actor ImageLoads {
    var count = 0
    func hit() { count += 1 }
}
final class CraftImageCacheTests: XCTestCase {
    func testDeletionCancelsPendingDownloadAndErasesDiskCache() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("previous account cache".utf8).write(to: folder.appendingPathComponent("old"))
        let started = expectation(description: "Download started")
        let cache = CraftImageCache(folder: folder) { _ in
            started.fulfill()
            try await Task.sleep(nanoseconds: 30_000_000_000)
            XCTFail("Deletion must cancel the download")
            return Data()
        }
        let download = Task { await cache.data(for: URL(string: "https://example.invalid/pending.png")!) }
        await fulfillment(of: [started], timeout: 2)
        await cache.erase()
        let result = await download.value
        XCTAssertNil(result)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }
    func testCoalescesConcurrentLoadsAndSurvivesNewCacheOffline() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let bytes = await MainActor.run {
            UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { context in
                UIColor.green.setFill(); context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
            }.pngData()!
        }
        let calls = ImageLoads()
        let cache = CraftImageCache(folder: folder) { _ in
            await calls.hit(); try await Task.sleep(nanoseconds: 40_000_000); return bytes
        }
        let url = URL(string: "https://example.invalid/immutable-image.png")!
        async let first = cache.data(for: url)
        async let second = cache.data(for: url)
        let results = await [first, second]
        XCTAssertNotNil(results[0]); XCTAssertEqual(results[0], results[1])
        let downloads = await calls.count; XCTAssertEqual(downloads, 1)
        let offline = CraftImageCache(folder: folder) { _ in throw URLError(.notConnectedToInternet) }
        let restored = await offline.data(for: url)
        XCTAssertEqual(restored, results[0])
    }
    func testInvalidResponseIsNotPersisted() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = CraftImageCache(folder: folder) { _ in Data("not an image".utf8) }
        let result = await cache.data(for: URL(string: "https://example.invalid/bad.png")!)
        XCTAssertNil(result)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }
}
