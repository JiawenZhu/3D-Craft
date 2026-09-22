import Foundation

struct CraftAsset: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var modelUrl: String?
    /// A looping character animation (Seedance MP4), when this creation is one.
    var animationUrl: String?
    var thumbUrl: String?
    var thumbDisplayUrl: String?
    var sourceImageUrl: String?
    var galleryExample: Bool?
    var galleryOrder: Int?
    var sourceImageURL: URL? { sourceImageUrl.flatMap(URL.init(string:)) }
    var faces: Int
    var fileSizeMb: Double
    var kind: String
    var isExample: Bool
    var projectId: String?
    var prompt: String?
    var archivedAt: Double?
    var creationKind: String?
    var firestoreDocName: String?

    var modelURL: URL? { modelUrl.flatMap(URL.init(string:)) }
    var animationURL: URL? { animationUrl.flatMap(URL.init(string:)) }
    var isAnimated: Bool { animationUrl != nil }
    var isConcept: Bool {
        creationKind == "Concept image" || (modelUrl == nil && animationUrl == nil && (thumbUrl != nil || sourceImageUrl != nil))
    }
    var isArchived: Bool { archivedAt != nil }
    var daysRemaining: Int {
        guard let archivedAt else { return 30 }
        let elapsed = Int((Date().timeIntervalSince1970 - archivedAt) / 86400)
        return max(0, 30 - elapsed)
    }
    var thumbURL: URL? { (thumbDisplayUrl ?? thumbUrl).flatMap(URL.init(string:)) }
    init(id: String, name: String, modelUrl: String? = nil, thumbUrl: String? = nil, faces: Int = 0, fileSizeMb: Double = 0, kind: String = "character", isExample: Bool = false, animationUrl: String? = nil, sourceImageUrl: String? = nil, projectId: String? = nil, prompt: String? = nil, archivedAt: Double? = nil, creationKind: String? = nil, firestoreDocName: String? = nil) {
        self.id=id; self.name=name; self.modelUrl=modelUrl; self.thumbUrl=thumbUrl; self.faces=faces; self.fileSizeMb=fileSizeMb; self.kind=kind; self.isExample=isExample
        self.animationUrl=animationUrl; self.sourceImageUrl=sourceImageUrl; self.projectId=projectId; self.prompt=prompt; self.archivedAt=archivedAt; self.creationKind=creationKind; self.firestoreDocName=firestoreDocName
    }
    init(_ d: [String:Any], base: String, example: Bool = false) {
        id=d["id"] as? String ?? UUID().uuidString; name=d["name"] as? String ?? "Untitled asset"
        modelUrl=resolved(d["modelUrl"] as? String, base:base); thumbUrl=resolved(d["thumbUrl"] as? String,base:base)
        animationUrl=resolved(d["animationUrl"] as? String, base:base)
        thumbDisplayUrl=resolved(d["thumbDisplayUrl"] as? String,base:base)
        sourceImageUrl=resolved(d["sourceImageUrl"] as? String,base:base)
        let gallery = d["galleryExample"] as? [String: Any]
        galleryExample = (d["galleryExample"] as? Bool) ?? (gallery != nil)
        let featured = ["lantern-explorer", "mint-racer", "cloud-dragon", "coconut-island", "woodland-cottage", "waterfall-diorama", "moss-robot", "moon-fox", "ancient-oak", "sunblade", "forest-shield", "ranger-bow", "starlight-robe", "ranger-outfit", "sunforge-helmet", "trail-boots", "bunny-knight", "panda-chef", "star-skiff", "treasure-chest"]
        galleryOrder = d["galleryOrder"] as? Int ?? featured.firstIndex(of: gallery?["slug"] as? String ?? "")
        faces=d["faces"] as? Int ?? 0; fileSizeMb=(d["fileSizeMb"] as? NSNumber)?.doubleValue ?? 0
        let n=name.lowercased()
        kind=d["kind"] as? String ?? (n.contains("car") || n.contains("taxi") || n.contains("van") ? "vehicle" : n.contains("dragon") || n.contains("bird") ? "flying" : "character")
        isExample=example
        projectId = d["projectId"] as? String
        prompt = d["prompt"] as? String
        archivedAt = (d["archivedAt"] as? NSNumber)?.doubleValue ?? (d["archivedAt"] as? Double)
        creationKind = d["creationKind"] as? String ?? d["kind"] as? String
        firestoreDocName = d["firestoreDocName"] as? String
    }
    static var lantern: CraftAsset {
        var asset = CraftAsset(id:"bundled-lantern",name:"Lantern Explorer",modelUrl:Bundle.main.url(forResource:"lantern_cat",withExtension:"glb")?.absoluteString,thumbUrl:Bundle.main.url(forResource:"lantern_cat",withExtension:"jpg")?.absoluteString,faces:94108,fileSizeMb:10.37,isExample:true)
        asset.thumbDisplayUrl = Bundle.main.url(forResource:"lantern_cat_display",withExtension:"png")?.absoluteString
        return asset
    }
}
func resolved(_ value: String?, base: String) -> String? {
    guard let value, !value.isEmpty else { return nil }
    if URL(string:value)?.scheme != nil { return value }
    return base.trimmingCharacters(in:CharacterSet(charactersIn:"/")) + "/" + value.trimmingCharacters(in:CharacterSet(charactersIn:"/"))
}
struct CraftConcept: Identifiable, Hashable, Codable {
    var id:String; var projectId:String; var name:String; var prompt:String; var imageUrl:String; var width:Int; var height:Int
    var label:String?; var direction:String?; var isOriginal:Bool?; var parentId:String?; var viewSetId:String?; var imageModel:String?; var imageProvider:String?
    init(_ d:[String:Any],base:String) { imageModel=d["imageModel"] as? String;imageProvider=d["imageProvider"] as? String;label=d["label"] as? String;direction=d["direction"] as? String;isOriginal=d["isOriginal"] as? Bool;parentId=d["parentId"] as? String;viewSetId=d["viewSetId"] as? String;id=d["id"] as? String ?? ""; projectId=d["projectId"] as? String ?? ""; name=d["name"] as? String ?? "Concept"; prompt=d["prompt"] as? String ?? ""; imageUrl=resolved(d["imageUrl"] as? String,base:base) ?? ""; width=d["width"] as? Int ?? 0; height=d["height"] as? Int ?? 0 }
}
struct CraftChatTurn: Identifiable, Codable {
    var id: String; var text: String; var status: String; var reply: String?
    var brief: String?; var ready: Bool?; var suggestions: [String]?; var error: String?
    var createdAt: Double
    var charged: Int?
    var isActive: Bool { status == "working" }
}
struct CraftProject: Identifiable, Codable {
    var conversation: [CraftChatTurn]?
    var turns: [CraftChatTurn] { conversation ?? [] }
    var brief: String { turns.last(where: { $0.status == "done" })?.brief ?? prompt }

    var id:String; var name:String; var prompt:String; var style:String; var imageUrl:String?; var concepts:[CraftConcept]
    var archivedAt: Double?
    var isArchived: Bool { archivedAt != nil }
    var daysRemaining: Int {
        guard let archivedAt else { return 30 }
        let elapsed = Int((Date().timeIntervalSince1970 - archivedAt) / 86400)
        return max(0, 30 - elapsed)
    }
    init(_ d:[String:Any],base:String) {
        conversation = (d["conversation"] as? [[String:Any]] ?? []).compactMap { item in
            guard let data = try? JSONSerialization.data(withJSONObject: item) else { return nil }
            return try? JSONDecoder().decode(CraftChatTurn.self, from: data)
        }
        id=d["id"] as? String ?? "";name=d["name"] as? String ?? "Untitled idea";prompt=d["prompt"] as? String ?? "";style=d["style"] as? String ?? "Stylized";imageUrl=resolved(d["imageUrl"] as? String,base:base);concepts=(d["concepts"] as? [[String:Any]] ?? []).map{CraftConcept($0,base:base)}
        archivedAt = (d["archivedAt"] as? NSNumber)?.doubleValue ?? (d["archivedAt"] as? Double)
    }
}
struct CraftJob: Identifiable, Codable {
    var sourcePrompt: String?
    var createdAt: Double?
    var id:String;var projectId:String;var kind:String;var status:String;var message:String;var progress:Double;var error:String?;var assets:[CraftAsset]
    var stage:String?;var coreConcept:String?;var selectedImageUrl:String?;var selectedConceptId:String?;var viewsUsable:Bool?;var warnings:[String]?;var concepts:[CraftConcept]?;var imageModel:String?;var imageProvider:String?
    var chargedTokens: Int?
    var reservedTokens: Int?
    var isActive:Bool { ["queued","running"].contains(status) }
    init(_ d:[String:Any],base:String) { sourcePrompt=d["sourcePrompt"] as? String;createdAt=d["createdAt"] as? Double;chargedTokens=d["charged"] as? Int;reservedTokens=d["reserved"] as? Int;imageModel=d["imageModel"] as? String;imageProvider=d["imageProvider"] as? String;stage=d["stage"] as? String;coreConcept=d["coreConcept"] as? String;selectedImageUrl=resolved(d["selectedImageUrl"] as? String,base:base);selectedConceptId=d["selectedConceptId"] as? String;viewsUsable=(d["validation"] as? [String:Any])?["usable"] as? Bool;warnings=d["warnings"] as? [String];concepts=(d["concepts"] as? [[String:Any]])?.map{CraftConcept($0,base:base)};id=d["id"] as? String ?? "";projectId=d["projectId"] as? String ?? "";kind=d["kind"] as? String ?? "concepts";status=d["status"] as? String ?? "queued";message=d["message"] as? String ?? "";progress=(d["progress"] as? NSNumber)?.doubleValue ?? 0;error=d["error"] as? String;assets=(d["assets"] as? [[String:Any]] ?? []).map{CraftAsset($0,base:base)} }
}
/// A creation someone could not afford: what it needed, and what they had.
struct CraftShortfall: Equatable {
    var needed: Int
    var available: Int
    var what: String
    var missing: Int { max(0, needed - available) }
    /// "this 3D model" reads as "This 3D model" when it opens a sentence.
    var sentenceStart: String { what.prefix(1).uppercased() + what.dropFirst() }
}

/// Where a blocked creation should land. Someone who already pays monthly
/// needs Tokens now, not another plan; someone with no plan is usually better
/// off seeing plans first.
enum CraftPaywallRoute {
    static func startOnTokenPacks(hasPlan: Bool) -> Bool { hasPlan }
}

struct WalletEntry: Identifiable { var id:String;var description:String;var amount:Int;var date:Date }
struct WalletState { var environment="PRODUCTION";var available=0;var packAvailable:Int?;var subscriptionAvailable=0;var subscriptionExpiresAt:Date?;var freeConceptTokens=0;var reserved=0;var ledger:[WalletEntry]=[] }
enum CraftRoute:Hashable {case project(String),asset(CraftAsset),wallet,settings,games(CraftAsset)}

/// Server-published provider costs. These are not the app's Token prices.
struct CraftModelPrice: Decodable {
    let name: String
    let unit: String
    let unitUsd: Double?
    let texturedUsd: Double?
    let multiUnitUsd: Double?
    let multiTexturedUsd: Double?
    let effortTexturedUsd: [String: Double]?
    let effortCredits: [String: Int]?
    let texturedCredits: Int?
    let multiTexturedCredits: Int?
    let highPackUsd: Double?
    let fourKUsd: Double?
    let inputPerMillion: Double?
    let outputPerMillion: Double?
    let note: String
    let noteZh: String
    let source: String

    func modelCost(texture: Bool = true, views: Int = 1, effort: String = "high") -> Double? {
        guard unit == "generation" else { return nil }
        if views > 1 { return texture ? multiTexturedUsd : multiUnitUsd }
        if texture, let cost = effortTexturedUsd?[effort] { return cost }
        return texture ? texturedUsd : unitUsd
    }
    static func usd(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(2...3)))
    }
}

/// Settled app credits, never inferred from current provider rates or status.
struct CraftSpendSummary {
    let jobs: [CraftJob]
    init(jobs: [CraftJob], projectID: String? = nil) {
        var seen = Set<String>()
        self.jobs = jobs.filter { (projectID == nil || $0.projectId == projectID) && seen.insert($0.id).inserted }
    }
    var spent: Int { jobs.reduce(0) { $0 + max(0, $1.chargedTokens ?? 0) } }
    var reserved: Int { jobs.filter(\.isActive).reduce(0) { $0 + max(0, $1.reservedTokens ?? 0) } }
    var unrecorded: Int { jobs.filter { $0.chargedTokens == nil }.count }
    func spent(model: Bool) -> Int { jobs.filter { ($0.kind == "model") == model }.reduce(0) { $0 + max(0, $1.chargedTokens ?? 0) } }
    func spent(kind: String) -> Int { jobs.filter { $0.kind == kind }.reduce(0) { $0 + max(0, $1.chargedTokens ?? 0) } }
}
