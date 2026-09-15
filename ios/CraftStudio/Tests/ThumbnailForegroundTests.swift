import XCTest
import UIKit
@testable import CraftStudio

final class ThumbnailForegroundTests: XCTestCase {
    func testBundledDisplayThumbnailWorksWithoutVisionAndKeepsOriginalReference() throws {
        let asset = CraftAsset.lantern
        XCTAssertTrue(asset.thumbUrl?.hasSuffix("lantern_cat.jpg") == true)
        let display = try XCTUnwrap(asset.thumbURL)
        XCTAssertTrue(display.path.hasSuffix("lantern_cat_display.png"))
        let data = try Data(contentsOf: display)
        let prepared = try CraftForegroundProcessor.foregroundPNG(from: data)
        XCTAssertTrue(CraftForegroundProcessor.hasTransparency(try XCTUnwrap(UIImage(data: prepared)?.cgImage)))
    }

    func testDisplayDerivativeDoesNotReplaceSourceURL() throws {
        let asset = CraftAsset(["id": "a", "thumbUrl": "/files/source.png", "thumbDisplayUrl": "/api/assets/a/thumbnail-display?v=1"], base: "http://localhost:8001")
        XCTAssertEqual(asset.thumbURL?.absoluteString, "http://localhost:8001/api/assets/a/thumbnail-display?v=1")
        XCTAssertEqual(asset.thumbUrl, "http://localhost:8001/files/source.png")
        let legacy = CraftAsset(["id": "a", "thumbUrl": "/files/source.png"], base: "http://localhost:8001")
        XCTAssertEqual(legacy.thumbURL?.absoluteString, legacy.thumbUrl)
    }

    func testTransparentImageKeepsBlackSubjectOpaque() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100), format: format).image { context in
            UIColor.black.setFill(); context.fill(CGRect(x: 20, y: 20, width: 60, height: 60))
        }
        let result = try CraftForegroundProcessor.foregroundPNG(from: XCTUnwrap(image.pngData()))
        let cg = try XCTUnwrap(UIImage(data: result)?.cgImage)
        let values = rgba(cg)
        XCTAssertLessThan(values[3], 10, "Transparent background must stay transparent.")
        let center = ((cg.height / 2) * cg.width + cg.width / 2) * 4
        XCTAssertGreaterThan(values[center + 3], 245, "Black subject must not be removed by color.")
        XCTAssertLessThan(values[center], 10)
    }

    func testSemanticMaskRemovesCatBackdropAndPreservesDarkDetails() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "lantern_cat", withExtension: "jpg"))
        let source = try Data(contentsOf: url)
        let output: Data
        do {
            output = try CraftForegroundProcessor.foregroundPNG(from: source)
        } catch let error as NSError {
            #if targetEnvironment(simulator)
            if error.domain == "com.apple.Vision", error.code == 9 {
                throw XCTSkip("This simulator cannot create the Vision inference context. Host Vision extraction was checked against the real dog/cat sources; simulator uses the server's transparent display derivative. The transparent-image test verifies that fallback preserves alpha and black subject pixels.")
            }
            #endif
            throw error
        }
        let cg = try XCTUnwrap(UIImage(data: output)?.cgImage)
        XCTAssertTrue(CraftForegroundProcessor.hasTransparency(cg))
        let values = rgba(cg)
        var darkSubjectPixels = 0
        for i in stride(from: 0, to: values.count, by: 4) {
            if values[i + 3] > 240 && values[i] < 65 && values[i + 1] < 65 && values[i + 2] < 65 {
                darkSubjectPixels += 1
            }
        }
        XCTAssertGreaterThan(darkSubjectPixels, 100, "Eyes and dark clothing remain opaque.")
        XCTAssertLessThan(values[3], 10, "Corner background must be transparent.")
        XCTAssertLessThanOrEqual(max(cg.width, cg.height), 640)
        XCTAssertEqual(try Data(contentsOf: url), source, "The generation source must not be changed.")
    }

    private func rgba(_ image: CGImage) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixels
    }
}
