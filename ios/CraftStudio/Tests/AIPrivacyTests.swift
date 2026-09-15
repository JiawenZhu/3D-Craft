import XCTest
@testable import CraftStudio

final class AIPrivacyTests: XCTestCase {
    func testOnlyGenerationWritesRequireAISharing() {
        for path in ["/projects/p/concepts", "/projects/p/chat", "/concepts/c/refine", "/concepts/c/model-prompt"] {
            XCTAssertEqual(CraftAIProvider.recipient(path: path, method: "POST"), .google)
            XCTAssertNil(CraftAIProvider.recipient(path: path, method: "GET"))
        }
        XCTAssertEqual(CraftAIProvider.recipient(path: "/concepts/c/model", method: "POST"), .fal)
        for path in ["/projects", "/projects/p/references", "/purchases/revenuecat", "/purchases/revenuecat/sync", "/cloud-library/sync", "/community/games", "/account/delete"] {
            XCTAssertNil(CraftAIProvider.recipient(path: path, method: "POST"))
        }
    }
    func testConsentDoesNotCrossAccountsOrProviders() {
        XCTAssertNotEqual(CraftAIProvider.google.key(uid: "one"), CraftAIProvider.google.key(uid: "two"))
        XCTAssertNotEqual(CraftAIProvider.google.key(uid: "one"), CraftAIProvider.fal.key(uid: "one"))
    }
}
