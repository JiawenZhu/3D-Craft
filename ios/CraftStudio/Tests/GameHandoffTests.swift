import XCTest
@testable import CraftStudio
final class GameHandoffTests: XCTestCase {
    private let bytes = Data([0x67,0x6c,0x54,0x46,2,0,0,0,24,0,0,0,4,0,0,0,0x4a,0x53,0x4f,0x4e,0x7b,0x7d,0x20,0x20])
    func testMultipleObjectsPreserveBytesAndUseUniqueFilenames() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let source=root.appendingPathComponent("original.glb");try bytes.write(to:source)
        let files=try GameHandoffFiles.prepare(sources:[source,source],names:["Moon Fox","Moon Fox"],idea:"我想自己设计玩法。",root:root)
        XCTAssertEqual(files.models.map(\.lastPathComponent),["01-moon-fox.glb","02-moon-fox.glb"])
        for model in files.models {XCTAssertEqual(try Data(contentsOf:model),bytes)}
        let brief=try String(contentsOf:files.brief,encoding:.utf8)
        XCTAssertEqual(brief,GameHandoffFiles.prompt(names:["Moon Fox","Moon Fox"],idea:"我想自己设计玩法。",chinese:false))
        XCTAssertFalse(brief.contains(root.path));XCTAssertTrue(brief.contains("我想自己设计玩法。"))
    }
    func testBriefIsShortAndLeavesGameDesignToUser() {
        for chinese in [true,false] {
            let brief=GameHandoffFiles.prompt(names:["Cat","Tree"],idea:"",chinese:chinese)
            XCTAssertLessThan(brief.count,180)
            XCTAssertTrue(brief.contains("01-cat.glb"));XCTAssertTrue(brief.contains("02-tree.glb"))
            for imposed in ["Safari","Chrome","Three.js","adventure","collectibles","index.html","REQUIRED DELIVERY"] {XCTAssertFalse(brief.contains(imposed))}
        }
    }
    func testBadSecondModelCleansEntirePartialPackage() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let valid=root.appendingPathComponent("valid.glb"), bad=root.appendingPathComponent("bad.glb")
        try bytes.write(to:valid);try Data("<html>bad download</html>".utf8).write(to:bad)
        XCTAssertThrowsError(try GameHandoffFiles.prepare(sources:[valid,bad],names:["a","b"],idea:"",root:root))
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath:root.path)),Set(["valid.glb","bad.glb"]))
    }
    func testEmptySelectionAndUnsafeNames() {
        XCTAssertThrowsError(try GameHandoffFiles.prepare(sources:[],names:[],idea:""))
        let name=GameHandoffFiles.filename(name:"../../🐱",index:0)
        XCTAssertEqual(name,"01-object.glb")
        XCTAssertTrue(GameHandoffFiles.filename(name:"小猫",index:1).hasSuffix(".glb"))
    }
}
