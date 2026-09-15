import XCTest
@testable import CraftStudio

final class WebAuthAttemptTests: XCTestCase {
    func testCanonicalURLAndMatchingCallback() {
        let attempt = CraftWebAuthAttempt(state: "expected")
        XCTAssertEqual(attempt.url.host, "3d-craft.web.app")
        XCTAssertEqual(attempt.credentials(from: URL(string: "studio.craft.ios://auth?state=expected&uid=u&token=t&refresh=r")!)?.uid, "u")
    }
    func testRejectsWrongMissingDuplicateStateAndOtherDestinations() {
        let attempt = CraftWebAuthAttempt(state: "expected")
        for url in ["studio.craft.ios://auth?uid=u&token=t&refresh=r",
                    "studio.craft.ios://auth?state=wrong&uid=u&token=t&refresh=r",
                    "studio.craft.ios://auth?state=expected&state=wrong&uid=u&token=t&refresh=r",
                    "studio.craft.ios://auth?state=expected&uid=u&uid=other&token=t&refresh=r",
                    "https://auth?state=expected&uid=u&token=t&refresh=r",
                    "studio.craft.ios://other?state=expected&uid=u&token=t&refresh=r",
                    "studio.craft.ios://auth?state=expected&uid=u&token=&refresh=r"] {
            XCTAssertNil(attempt.credentials(from: URL(string: url)!))
        }
    }
    func testExpiredAttemptAndIndependentAttempts() {
        let attempt = CraftWebAuthAttempt(state: "expected", createdAt: Date(timeIntervalSince1970: 1000))
        let url = URL(string: "studio.craft.ios://auth?state=expected&uid=u&token=t&refresh=r")!
        XCTAssertNil(attempt.credentials(from: url, now: Date(timeIntervalSince1970: 1600)))
        XCTAssertNotEqual(CraftWebAuthAttempt().state, CraftWebAuthAttempt().state)
    }
}
