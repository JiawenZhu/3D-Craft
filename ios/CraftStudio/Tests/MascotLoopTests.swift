import AVFoundation
import XCTest
@testable import CraftStudio

final class MascotLoopTests: XCTestCase {
    func testThemeSelectsOriginalMascot() {
        XCTAssertEqual(CraftAppearance.lavender.mascot, "dragon")
        XCTAssertEqual(CraftAppearance.emerald.mascot, "panda")
    }

    /// Every clip the indicator can request is bundled, silent, short and small.
    func testEveryClipAndPosterIsBundledSilentAndSmall() async throws {
        for appearance in CraftAppearance.allCases {
            let char = appearance.mascot
            var clips = [CraftMascotPhase.thinking, .concept, .model].map { "mascot-\(char)-\($0.rawValue)" }
            clips.append("mascot-\(char)-thinking-small")
            for name in clips {
                let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "mp4"), name)
                let bytes = try XCTUnwrap(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
                XCTAssertLessThan(bytes, 400_000, name)
                let asset = AVURLAsset(url: url)
                let audio = try await asset.loadTracks(withMediaType: .audio)
                XCTAssertTrue(audio.isEmpty, "\(name) must not carry audio")
                let seconds = try await asset.load(.duration).seconds
                XCTAssertEqual(seconds, 4, accuracy: 0.25, name)
            }
            for poster in ["mascot-\(char)-poster", "mascot-\(char)-poster-small"] {
                XCTAssertNotNil(Bundle.main.url(forResource: poster, withExtension: "jpg"), poster)
            }
        }
    }
}
