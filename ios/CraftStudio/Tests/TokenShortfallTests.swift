import XCTest
@testable import CraftStudio

/// A creation someone cannot afford should explain the gap in their own terms
/// and open the page that actually helps.
final class TokenShortfallTests: XCTestCase {
    func testTheGapIsWhatIsMissingNotTheWholePrice() {
        let shortfall = CraftShortfall(needed: 98, available: 40, what: "this animation")
        XCTAssertEqual(shortfall.missing, 58)
        XCTAssertEqual(shortfall.sentenceStart, "This animation")
    }

    func testAnAffordableCreationLeavesNothingMissing() {
        XCTAssertEqual(CraftShortfall(needed: 46, available: 300, what: "this 3D model").missing, 0)
    }

    func testFreeConceptTokensCountTowardsWhatSomeoneHas() {
        // The store adds pack, plan and free concept Tokens before deciding.
        var wallet = WalletState()
        wallet.available = 10
        wallet.freeConceptTokens = 25
        let have = wallet.available + wallet.freeConceptTokens
        XCTAssertEqual(CraftShortfall(needed: 46, available: have, what: "this image").missing, 11)
    }

    func testSubscribersAreSentToTokenPacksAndEveryoneElseToPlans() {
        XCTAssertTrue(CraftPaywallRoute.startOnTokenPacks(hasPlan: true))
        XCTAssertFalse(CraftPaywallRoute.startOnTokenPacks(hasPlan: false))
    }

    @MainActor
    func testMiniMaxAnimationCostFollowsRodinBenchmark() async {
        let store = CraftStore()
        let miniMax480Cost = await store.animationCost(model: "minimax-h3", resolution: "480p", duration: "5")
        let miniMax768Cost = await store.animationCost(model: "minimax-h3", resolution: "768p", duration: "5")
        let seedance480Cost = await store.animationCost(model: "seedance-2.5", resolution: "480p", duration: "4")
        let seedance720Cost = await store.animationCost(model: "seedance-2.5", resolution: "720p", duration: "4")

        XCTAssertEqual(miniMax480Cost, 29)
        XCTAssertEqual(miniMax768Cost, 35)
        XCTAssertEqual(seedance480Cost, 98)
        XCTAssertEqual(seedance720Cost, 220)
    }
}
