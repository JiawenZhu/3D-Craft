import XCTest
@testable import CraftStudio

final class APIKeysTests: XCTestCase {
    func testExpiryDefaultsTo90DaysWithBoundedChoices() {
        XCTAssertEqual(CraftAPIKeyRules.defaultExpiry, 90)
        XCTAssertEqual(CraftAPIKeyRules.expiryOptions, [30, 90, 365])
    }
    func testScopesAreLeastPrivilegeOrFullAccess() {
        XCTAssertEqual(CraftAPIKeyRules.requestScopes(fullAccess: true, selected: []), ["*"])
        XCTAssertEqual(CraftAPIKeyRules.requestScopes(fullAccess: false, selected: ["wallet:read", "bogus", "assets:read"]), ["assets:read", "wallet:read"])
        XCTAssertNil(CraftAPIKeyRules.requestScopes(fullAccess: false, selected: []))
        XCTAssertEqual(CraftAPIKeyRules.requestScopes(fullAccess: true, selected: [], allowDelete: true), ["*", "assets:delete"])
        XCTAssertEqual(CraftAPIKeyRules.requestScopes(fullAccess: false, selected: ["assets:read"], allowDelete: true), ["assets:read", "assets:delete"])
        XCTAssertNil(CraftAPIKeyRules.requestScopes(fullAccess: false, selected: [], allowDelete: true))
    }
    func testNamesAreTrimmedAndBounded() {
        XCTAssertNil(CraftAPIKeyRules.cleanName("   "))
        XCTAssertNil(CraftAPIKeyRules.cleanName(String(repeating: "x", count: 65)))
        XCTAssertEqual(CraftAPIKeyRules.cleanName(" ChatGPT "), "ChatGPT")
    }
    func testMetadataParsingAndStatus() throws {
        let key = try XCTUnwrap(CraftAPIKey(["id": "key_1", "name": "A", "prefix": "craft_live_abc123...", "scopes": ["*"],
                                             "createdAt": 5.5, "expiresAt": 100, "revoked": false, "revokedAt": NSNull(), "lastUsedAt": NSNull()]))
        XCTAssertEqual(key.displayPrefix, "craft_live_abc123…")
        XCTAssertEqual(key.status(now: Date(timeIntervalSince1970: 50)), .active)
        XCTAssertEqual(key.status(now: Date(timeIntervalSince1970: 200)), .expired)
        XCTAssertNil(key.lastUsedAt)
        XCTAssertEqual(CraftAPIKey(["id": "k", "revoked": true])?.status(), .revoked)
        XCTAssertNil(CraftAPIKey(["name": "missing id"]))
    }
    func testCreatedKeyRequiresCraftSecret() {
        XCTAssertNil(CraftCreatedAPIKey(["id": "k", "key": "sk-other"]))
        XCTAssertEqual(CraftCreatedAPIKey(["id": "k", "key": "craft_live_x"])?.secret, "craft_live_x")
    }
    @MainActor func testSignedOutStoreStartsEmptyAndClearsReveal() {
        let store = CraftAPIKeyStore()
        store.clear()
        XCTAssertNil(store.keys); XCTAssertNil(store.revealed); XCTAssertNil(store.error)
    }
    func testGuideUsesCanonicalCloudOrigin() {
        XCTAssertEqual(CraftAPIKeyRules.baseURL, "https://3d-craft.web.app/api/v1")
        XCTAssertEqual(CraftAPIKeyRules.openAPIURL.absoluteString, "https://3d-craft.web.app/api/v1/openapi.json")
    }
}
