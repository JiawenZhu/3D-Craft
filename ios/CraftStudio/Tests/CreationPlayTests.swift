import XCTest
@testable import CraftStudio

@MainActor
final class CreationPlayTests: XCTestCase {
    private func job(_ id:String, status:String, asset:Bool=false, kind:String="model") -> CraftJob {
        CraftJob(["id":id,"projectId":"p","kind":kind,"status":status,
                  "assets":asset ? [["id":"a-"+id,"name":"Created model","modelUrl":"https://example.com/model.glb"]] : []],base:"https://example.com")
    }
    func testCompletionOnlyAfterWatchedModelHasActualAsset() {
        var tracker=ModelCompletionTracker()
        XCTAssertTrue(tracker.receive([job("old",status:"done",asset:true)]).isEmpty)
        XCTAssertTrue(tracker.receive([job("new",status:"running")]).isEmpty)
        XCTAssertTrue(tracker.receive([job("new",status:"done")]).isEmpty)
        let thumbnailOnly = CraftJob(["id":"new","projectId":"p","kind":"model","status":"done",
            "assets":[["id":"preview","name":"Preview","thumbnailUrl":"https://example.com/preview.png"]]],base:"https://example.com")
        XCTAssertTrue(tracker.receive([thumbnailOnly]).isEmpty)
        XCTAssertEqual(tracker.receive([job("new",status:"done",asset:true)]).map(\.id),["new"])
        XCTAssertTrue(tracker.receive([job("new",status:"done",asset:true)]).isEmpty)
    }
    func testFailedAndConceptJobsNeverAnnounceModel() {
        var tracker=ModelCompletionTracker()
        _=tracker.receive([job("bad",status:"running"),job("concept",status:"running",kind:"concepts")])
        XCTAssertTrue(tracker.receive([job("bad",status:"failed"),job("concept",status:"done",asset:true,kind:"concepts")]).isEmpty)
    }
    func testFastSubmissionAndSeveralCompletionsAreQueued() {
        var tracker=ModelCompletionTracker();tracker.watching=["a","b"]
        XCTAssertEqual(tracker.receive([job("a",status:"done",asset:true),job("b",status:"done",asset:true)]).count,2)
    }
    func testRepeatedLikeIsIdempotentAndPreservesOtherCategories() {
        let game:[String:Any]=["votes":["fun":4,"visuals":2]]
        let result=CommunityCloudService.applyingVote(to:game,existing:["fun","visuals"],category:"fun",liked:true)
        XCTAssertEqual(result["votes"] as? [String:Int],["fun":4,"visuals":2])
        XCTAssertEqual(result["myVotes"] as? [String],["fun","visuals"])
    }
    func testLikeUnlikeChangesOnlyOneVoteAndNeverNegative() {
        let game:[String:Any]=["votes":["fun":4,"visuals":2]]
        let liked=CommunityCloudService.applyingVote(to:game,existing:[],category:"fun",liked:true)
        XCTAssertEqual((liked["votes"] as? [String:Int])?["fun"],5)
        let undone=CommunityCloudService.applyingVote(to:liked,existing:["fun"],category:"fun",liked:false)
        XCTAssertEqual(undone["votes"] as? [String:Int],["fun":4,"visuals":2])
        let empty=CommunityCloudService.applyingVote(to:["votes":["fun":0]],existing:["fun"],category:"fun",liked:false)
        XCTAssertEqual((empty["votes"] as? [String:Int])?["fun"],0)
    }
    func testOpenCompletionNavigatesToExactAssetAndLeavesNextCard() {
        let store=CraftStore();store.completedModelCards=[job("a",status:"done",asset:true),job("b",status:"done",asset:true)]
        store.openCompletedModel()
        guard case .asset(let asset)=store.path.last else { return XCTFail("Expected model destination") }
        XCTAssertEqual(asset.id,"a-a");XCTAssertEqual(store.completedModelCards.first?.id,"b")
    }
}
