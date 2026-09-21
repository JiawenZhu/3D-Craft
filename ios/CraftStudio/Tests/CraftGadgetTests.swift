import XCTest
@testable import CraftStudio

final class CraftGadgetTests: XCTestCase {
    func testDefaultGadgetIsFireDragon() {
        let center = CraftGadgetCenter.shared
        let defaultGadget = CraftGadgetData.defaultDragon
        XCTAssertEqual(defaultGadget.id, "bundled-dragon")
        XCTAssertEqual(defaultGadget.name, "Fire Dragon")
        XCTAssertEqual(defaultGadget.style, .small)
        XCTAssertEqual(defaultGadget.loopDuration, "4s Physics Loop")
    }

    func testSetAndRetrieveActiveGadget() {
        let center = CraftGadgetCenter.shared
        let testGadget = CraftGadgetData(
            id: "test-asset-\(UUID().uuidString)",
            name: "Cyber Cat Jump",
            modelName: "MiniMax Hailuo 02 (768p)",
            prompt: "A cyber cat jumping through a portal",
            loopDuration: "4s Loop",
            style: .medium,
            imageFileName: nil,
            updatedAt: .now
        )

        center.setActiveGadget(testGadget)
        let retrieved = center.activeGadget()

        XCTAssertEqual(retrieved.id, testGadget.id)
        XCTAssertEqual(retrieved.name, "Cyber Cat Jump")
        XCTAssertEqual(retrieved.style, .medium)
        XCTAssertEqual(retrieved.modelName, "MiniMax Hailuo 02 (768p)")

        // Explicitly test Keychain status with access group
        let testData = "test_payload".data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "test_account",
            kSecAttrService as String: "studio.craft.gadget",
            kSecAttrAccessGroup as String: "C265XC3RH7.studio.craft.ios",
            kSecValueData as String: testData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemDelete(query as CFDictionary)
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        print("KEYCHAIN_TEST addStatus: \(addStatus)")
        XCTAssertEqual(addStatus, errSecSuccess, "SecItemAdd failed with OSStatus: \(addStatus)")
    }

    func testDynamicCharacterSwitching() {
        let center = CraftGadgetCenter.shared

        // 1. Set to Fire Dragon
        let dragon = CraftGadgetData(
            id: "dragon-1",
            name: "Fire Dragon",
            modelName: "MiniMax Hailuo 02",
            prompt: "dragon",
            loopDuration: "4s",
            style: .small,
            imageFileName: nil,
            updatedAt: .now
        )
        let redImage = UIGraphicsImageRenderer(size: CGSize(width: 50, height: 50)).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 50, height: 50))
        }
        center.setActiveGadget(dragon, image: redImage)
        XCTAssertEqual(center.activeGadget().name, "Fire Dragon")

        // 2. Switch dynamically to Explorer Kitten
        let kitten = CraftGadgetData(
            id: "kitten-1",
            name: "Explorer Kitten",
            modelName: "Seedance 2.5",
            prompt: "kitten",
            loopDuration: "4s",
            style: .small,
            imageFileName: nil,
            updatedAt: .now
        )
        let blueImage = UIGraphicsImageRenderer(size: CGSize(width: 50, height: 50)).image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 50, height: 50))
        }
        center.setActiveGadget(kitten, image: blueImage)

        // 3. Verify it dynamically updated to Kitten, NOT dragon!
        let active = center.activeGadget()
        XCTAssertEqual(active.id, "kitten-1")
        XCTAssertEqual(active.name, "Explorer Kitten")
        XCTAssertNotNil(center.loadHeroImage(for: active))
    }

    func testGadgetStyleLocalization() {
        XCTAssertTrue(CraftGadgetStyle.small.title(chinese: true).contains("小组件"))
        XCTAssertTrue(CraftGadgetStyle.small.title(chinese: false).contains("Small"))
        XCTAssertTrue(CraftGadgetStyle.medium.title(chinese: true).contains("中组件"))
        XCTAssertTrue(CraftGadgetStyle.medium.title(chinese: false).contains("Medium"))
        XCTAssertTrue(CraftGadgetStyle.large.title(chinese: true).contains("大组件"))
        XCTAssertTrue(CraftGadgetStyle.large.title(chinese: false).contains("Large"))
    }
}
