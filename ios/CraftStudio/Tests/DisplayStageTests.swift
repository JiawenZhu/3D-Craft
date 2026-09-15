import XCTest
import SceneKit
@testable import CraftStudio

final class DisplayStageTests: XCTestCase {
    func testStageTouchesNormalizedFeetAndStaysInsideCameraBounds() throws {
        for size in [SIMD3<Float>(1, 2, 1), SIMD3<Float>(2, 0.6, 1.8)] {
            let stage = CraftDisplayStage.make(size: size)
            let plinth = try XCTUnwrap(stage.childNode(withName: "plinth", recursively: false))
            let (low, high) = plinth.boundingBox
            XCTAssertEqual(plinth.convertPosition(high, to: stage).y, 0, accuracy: 0.0001)
            XCTAssertEqual(plinth.convertPosition(low, to: stage).y, -0.11, accuracy: 0.0001)
            XCTAssertLessThanOrEqual(high.x, CraftCameraFraming.platformRadius(size: size) + 0.0001)
            XCTAssertTrue(try XCTUnwrap(plinth.geometry?.firstMaterial).writesToDepthBuffer)
        }
    }
}
