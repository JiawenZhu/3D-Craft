import XCTest
@testable import CraftStudio

final class CameraFramingTests: XCTestCase {
    func testResetOrbitsAroundSubjectAndEndsAtHome() {
        let frame = CraftCameraFraming.fit(size: SIMD3(1, 2, 1), aspect: 0.9)
        for start in [SIMD3<Float>(0, 1, -8), SIMD3<Float>(8, 5, 0), SIMD3<Float>(0, 1, 0.1), SIMD3<Float>(.nan, 0, 0)] {
            for step in 0...20 {
                let result = CraftCameraFraming.returnEye(from: start, to: frame, fraction: Float(step) / 20)
                XCTAssertTrue(result.x.isFinite && result.y.isFinite && result.z.isFinite)
                let delta = result - SIMD3<Float>(0, frame.targetY, 0)
                XCTAssertGreaterThanOrEqual(sqrt(delta.x * delta.x + delta.y * delta.y + delta.z * delta.z), frame.distance * 0.69)
            }
            let end = CraftCameraFraming.returnEye(from: start, to: frame, fraction: 1)
            let home = CraftCameraFraming.eye(frame)
            XCTAssertEqual(end.x, home.x, accuracy: 0.001)
            XCTAssertEqual(end.y, home.y, accuracy: 0.001)
            XCTAssertEqual(end.z, home.z, accuracy: 0.001)
        }
    }

    func testTallWideAndDeepAssetsRemainInsidePortraitAndLandscapeFrames() {
        for size in [SIMD3<Float>(1.25, 2, 1.1), SIMD3<Float>(2, 0.6, 1.8), SIMD3<Float>(0.4, 1, 2)] {
            for aspect: Float in [0.45, 0.9, 1.55, 2.2] {
                let fit = CraftCameraFraming.fit(size:size, aspect:aspect)
                let eye = SIMD3<Float>(0, fit.targetY + fit.distance * sin(fit.pitch), fit.distance * cos(fit.pitch))
                let target = SIMD3<Float>(0,fit.targetY,0)
                let forward = (target-eye) / fit.distance
                let up = SIMD3<Float>(0,cos(fit.pitch),-sin(fit.pitch))
                // Project every normalized model/plinth corner into the camera.
                let radius = CraftCameraFraming.platformRadius(size:size)
                for box in [(size.x / 2, Float(0), size.y, size.z / 2), (radius, -Float(0.11), Float(0), radius)] {
                for x in [-box.0,box.0] {
                    for y in [box.1,box.2] {
                        for z in [-box.3,box.3] {
                            let relative = SIMD3<Float>(x,y,z)-eye
                            let depth = relative.x*forward.x + relative.y*forward.y + relative.z*forward.z
                            let vertical = relative.x*up.x + relative.y*up.y + relative.z*up.z
                            XCTAssertGreaterThan(depth,0)
                            let halfHeight = depth*tan(Float(10) * .pi / 180)
                            XCTAssertLessThanOrEqual(abs(vertical)/halfHeight,0.901)
                            XCTAssertLessThanOrEqual(abs(x)/(halfHeight*aspect),0.901)
                        }
                    }
                }
                }
            }
        }
    }
}
