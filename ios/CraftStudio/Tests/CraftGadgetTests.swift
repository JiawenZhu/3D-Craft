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
