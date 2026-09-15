import Foundation

/// Perspective fit for the real scene bounds, including its display plinth.
enum CraftCameraFraming {
    struct Frame { let targetY: Float; let distance: Float; let pitch: Float }
    static func platformRadius(size: SIMD3<Float>) -> Float { max(0.7, max(size.x, size.z) * 0.60) }
    static func fit(size: SIMD3<Float>, aspect: Float) -> Frame {
        let pitch: Float = 0.12
        let targetY = (size.y - 0.11) * 0.5
        let radius = platformRadius(size:size)
        // A product-photo lens keeps front and rear proportions close, while
        // retaining native perspective zoom/orbit controls.
        let tanY = tan(Float(10) * .pi / 180)
        let tanX = tanY * max(0.1, aspect)
        var distance: Float = 0
        for box in [(size.x / 2, Float(0), size.y, size.z / 2), (radius, -Float(0.11), Float(0), radius)] {
        for x in [-box.0, box.0] {
            for y in [box.1, box.2] {
                for z in [-box.3, box.3] {
                    let relativeY = y - targetY
                    let vertical = relativeY * cos(pitch) - z * sin(pitch)
                    let depth = relativeY * sin(pitch) + z * cos(pitch)
                    distance = max(distance, depth + max(abs(x) / tanX, abs(vertical) / tanY) / 0.9)
                }
            }
        }
        }
        return Frame(targetY: targetY, distance: distance, pitch: pitch)
    }

    /// The eye position a frame implies — the same expression the framing test
    /// projects from, kept in one place so the arrival cannot drift from it.
    static func eye(_ frame: Frame) -> SIMD3<Float> {
        SIMD3(0,
              frame.targetY + frame.distance * sin(frame.pitch),
              frame.distance * cos(frame.pitch))
    }

    /// Return around the subject, never through it, and always keep a finite orbit.
    static func returnEye(from start: SIMD3<Float>, to frame: Frame, fraction: Float) -> SIMD3<Float> {
        let target = SIMD3<Float>(0, frame.targetY, 0)
        let offset = start - target
        let length = sqrt(offset.x * offset.x + offset.y * offset.y + offset.z * offset.z)
        guard start.x.isFinite, start.y.isFinite, start.z.isFinite, length.isFinite, length > 0.001 else { return eye(frame) }
        let t = min(1, max(0, fraction))
        let eased = t * t * (3 - 2 * t)
        let yaw = atan2(offset.x, offset.z) * (1 - eased)
        let pitch = asin(min(1, max(-1, offset.y / length))) * (1 - eased) + frame.pitch * eased
        let radius = max(frame.distance * 0.7, length) * (1 - eased) + frame.distance * eased
        return target + SIMD3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * radius
    }

    /// The frame the arrival dollies in *from*: same target, same pitch, a touch
    /// further out. Because only the distance changes, the eye moves along the
    /// view axis and the camera orientation is identical at both ends — the
    /// settle is a pure dolly and the composition never swings.
    ///
    /// Presentation only. `fit` and `platformRadius` are byte-for-byte unchanged,
    /// so the framing CameraFramingTests verifies is exactly the framing that ships.
    static func entrance(_ frame: Frame, pull: Float = 0.16) -> Frame {
        Frame(targetY: frame.targetY,
              distance: frame.distance * (1 + max(0, pull)),
              pitch: frame.pitch)
    }
}
