import SwiftUI
import Security
import CryptoKit

struct CraftError: LocalizedError { var message:String; var statusCode:Int? = nil; var errorDescription:String? {message} }

/// The exact authorized request survives timeout, backgrounding and relaunch.
/// Its key changes only after a definitive rejection or known terminal result.
struct PendingGeneration: Codable, Equatable {
    let apiBase:String
    var accountUID:String? = nil
    let requestPath:String
    let projectID:String
    let signature:String
    let body:Data
    let idempotencyKey:String
    let draftFingerprint:String?
    var jobID:String?

    static func fingerprint(_ data:Data)->String { SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined() }
    static func signature(path:String,payload:[String:Any]) throws ->String {
        fingerprint(Data(path.utf8) + (try JSONSerialization.data(withJSONObject:payload,options:.sortedKeys)))
    }
    static func make(base:String,path:String,projectID:String,payload:[String:Any],draftFingerprint:String?=nil,accountUID:String?=nil) throws ->PendingGeneration {
        let key=UUID().uuidString
        var authorized=payload;authorized["idempotencyKey"]=key
        return PendingGeneration(apiBase:base,accountUID:accountUID,requestPath:path,projectID:projectID,signature:try signature(path:path,payload:payload),body:try JSONSerialization.data(withJSONObject:authorized,options:.sortedKeys),idempotencyKey:key,draftFingerprint:draftFingerprint)
    }
    func matches(base:String,path:String,payload:[String:Any],accountUID:String?=nil)->Bool {
        self.accountUID == accountUID && apiBase==base && signature == (try? Self.signature(path:path,payload:payload))
    }
}
@MainActor final class CraftStore: ObservableObject {
    struct PurchaseCelebration: Identifiable {
        let id = UUID()
        let tokens: Int
        let balance: Int
        var presentationKey: String? = nil
    }
    @Published var purchaseToPresent: PurchaseCelebration?
    @Published var walletCelebration: PurchaseCelebration?

    func presentPurchasedWallet() {
        guard let receipt = purchaseToPresent else { return }
        if let index = path.firstIndex(of: .wallet) {
            path = Array(path.prefix(through: index))
        } else { path.append(.wallet) }
        walletCelebration = receipt
        purchaseToPresent = nil
    }
    @Published var isChinese = UserDefaults.standard.bool(forKey:"craftChinese") { didSet {UserDefaults.standard.set(isChinese,forKey:"craftChinese")} }
    @Published var apiBase: String = {
        #if targetEnvironment(simulator)
        let simulator = true
        #else
        let simulator = false
        #endif
        return StudioConnection.initial(saved: UserDefaults.standard.string(forKey: "craftAPI"),
            configured: Bundle.main.object(forInfoDictionaryKey: "CraftStudioAPIURL") as? String,
            simulator: simulator)
    }() {
        didSet { if oldValue != apiBase {
            imageModelsLoaded = false; imageModels = CraftImageModel.placeholders; modelPrices = [:]
            aiAccountRevision += 1; aiAccount = CraftAIAccount(); aiAccountLoaded = false; aiLogin = nil
        } }
    }
    @Published var webBase = StudioConnection.cloudURL
    @Published var imageModelID = CraftImageModel.restoredSelection(UserDefaults.standard.string(forKey: "craftImageModel")) {
        didSet { UserDefaults.standard.set(imageModelID, forKey: "craftImageModel") }
    }
    @Published var imageModels = CraftImageModel.placeholders
    @Published var showPriceDetails = UserDefaults.standard.bool(forKey: "craftShowPriceDetails") {
        didSet { UserDefaults.standard.set(showPriceDetails, forKey: "craftShowPriceDetails") }
    }
    @Published var modelPrices: [String: CraftModelPrice] = [:]
    @Published var pricesVerifiedAt = ""
    @Published var serviceFeeRate: Double = 0.15
    @Published var imageModelsLoaded = false
    var selectedImageModel: CraftImageModel? { imageModels.first { $0.id == imageModelID } }
    @Published var plannerModelID = UserDefaults.standard.string(forKey: "craftPlannerModel") ?? CraftPlannerModel.defaultID {
        didSet { UserDefaults.standard.set(plannerModelID, forKey: "craftPlannerModel") }
    }
    @Published var plannerEffort = UserDefaults.standard.string(forKey: "craftPlannerEffort") ?? "low" {
        didSet { UserDefaults.standard.set(plannerEffort, forKey: "craftPlannerEffort") }
    }
    @Published var aiAccount = CraftAIAccount()
    @Published var aiAccountLoaded = false
    @Published var aiAccountBusy = false
    @Published var aiAccountError: String?
    @Published var aiLogin: CraftAILogin?
    private var aiAccountRefreshing = false
    private var aiAccountRevision = 0
    private var aiSnapshotRevision = 0
    var selectedPlannerModel: CraftPlannerModel? { aiAccount.models.first { $0.id == plannerModelID } }
    var plannerDisplayName: String {
        plannerModelID == CraftPlannerModel.defaultID ? CraftPlannerModel.defaultName : selectedPlannerModel?.name ?? plannerModelID
    }
    @Published var activeConversationID: String? {
        didSet { UserDefaults.standard.set(activeConversationID, forKey: "craftActiveConversation:" + apiBase) }
    }
    @Published var sendingChat: Set<String> = []
    func startConversation() async {
        guard draftImage == nil else { return }
        guard let id = await createConcepts(count: 1, originalOnly: true) else { return }
        activeConversationID = id
        let text = draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? t("Help me turn this reference into a game asset.", "帮我把这张参考图变成游戏资产。") : draftPrompt
        draftPrompt = ""; saveDraftImage(nil)
        _ = await sendChat(projectID: id, text: text)
    }
    @discardableResult func sendChat(projectID: String, text: String, conceptID: String? = nil) async -> Bool {
        guard !sendingChat.contains(projectID), plannerIsReady() else { return false }
        sendingChat.insert(projectID); defer { sendingChat.remove(projectID) }
        let key = "craftPendingChat:" + apiBase + ":" + projectID
        let fields: [String: Any] = ["text": text, "plannerModel": plannerModelID, "plannerEffort": plannerEffort, "conceptId": conceptID as Any? ?? NSNull(), "style": draftStyle]
        var payload = fields
        if let data = UserDefaults.standard.data(forKey: key),
           let previous = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // Reconcile the original request first after an uncertain connection.
            payload = previous
        } else {
            payload["clientId"] = UUID().uuidString
            UserDefaults.standard.set(try? JSONSerialization.data(withJSONObject: payload), forKey: key)
        }
        do {
            _ = try await request("/projects/" + projectID + "/chat", method: "POST", body: payload)
            UserDefaults.standard.removeObject(forKey: key)
            await refresh(); startPolling()
            if payload["text"] as? String != text { return false }
            return true
        } catch {
            if let failure = error as? CraftError, let code = failure.statusCode, (400..<500).contains(code) {
                UserDefaults.standard.removeObject(forKey: key)
            }
            self.error = error.localizedDescription
            return false
        }
    }
    func attachChatReference(projectID: String, image: UIImage) async -> CraftConcept? {
        guard let photo = image.jpegData(compressionQuality: 0.95), photo.count <= 20 * 1024 * 1024 else { error = t("Choose a photo under 20 MB.", "请选择小于 20 MB 的照片。"); return nil }
        let uploadKey = pendingUploadKey(scope: "reference:" + projectID)
        let clientID = uploadRequestID(key: uploadKey, fingerprint: PendingGeneration.fingerprint(photo))
        let boundary = "Craft-" + UUID().uuidString
        var data = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"clientId\"\r\n\r\n\(clientID)\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"image\"; filename=\"reference.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8)
        data.append(photo); data.append(Data("\r\n--\(boundary)--\r\n".utf8))
        do {
            let result = try await request("/projects/" + projectID + "/references", method: "POST", data: data, contentType: "multipart/form-data; boundary=" + boundary) as? [String: Any] ?? [:]
            guard let id = result["id"] as? String, !id.isEmpty else { throw CraftError(message: "The reference could not be saved.") }
            UserDefaults.standard.removeObject(forKey: uploadKey)
            let concept = CraftConcept(result, base: apiBase)
            selectConcept(concept); await refresh(); return concept
        } catch { self.error = error.localizedDescription; return nil }
    }
    private func pendingUploadKey(scope: String) -> String {
        "craftPendingUpload:" + (CraftAccount.shared.uid ?? "signed-out") + ":" + apiBase + ":" + scope
    }
    private func uploadRequestID(key: String, fingerprint: String) -> String {
        if let saved = UserDefaults.standard.dictionary(forKey: key), saved["fingerprint"] as? String == fingerprint,
           let id = saved["clientId"] as? String { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(["fingerprint": fingerprint, "clientId": id], forKey: key)
        return id
    }
    @Published var projects:[CraftProject]=[]
    @Published var assets:[CraftAsset]=[]
    @Published var examples:[CraftAsset]=PublicGallery.bundled
    @Published var jobs:[CraftJob]=[]
    @Published var wallet=WalletState()
    @Published var connected=false
    @Published var connecting=false
    @Published var connectionNotice:String?
    @Published var connectionNeedsSignIn = false
    @Published var connectionNeedsSetup = false
    private var connectionFailures = 0
    private var nextConnectionAttempt = Date.distantPast
    func connectionFailed(_ problem: Error) {
        connected = false
        connectionNeedsSignIn = (problem as? CraftError)?.statusCode == 401
        connectionNeedsSetup = apiBase.isEmpty
        connectionFailures += 1
        nextConnectionAttempt = Date().addingTimeInterval(min(30, Double(connectionFailures) * 5))
        if connectionNeedsSetup {
            connectionNotice = t("Choose your studio server in Profile.", "请在我的页面设置工作室服务地址。")
        } else if connectionNeedsSignIn {
            connectionNotice = t("Your studio sign-in expired. Sign in again to reconnect.", "工作室登录已过期，请重新登录。")
        } else if let failure = problem as? URLError {
            switch failure.code {
            case .notConnectedToInternet, .networkConnectionLost:
                connectionNotice = t("Connection lost. Check Wi-Fi; your creations are saved.", "连接已断开，请检查 Wi-Fi。作品已保存。")
            case .cannotConnectToHost, .cannotFindHost, .timedOut:
                connectionNotice = t("Studio unavailable. Keep your Mac awake and use the same Wi-Fi.", "工作室暂不可用。请保持 Mac 唤醒并连接相同 Wi-Fi。")
            case .appTransportSecurityRequiresSecureConnection:
                connectionNotice = t("This server needs a secure connection. Check the address in Profile.", "此服务需要安全连接，请在我的页面检查地址。")
            default: connectionNotice = t("Couldn’t reach the cloud studio. Check your internet connection and try again.", "无法连接云端工作室，请检查互联网连接后重试。")
            }
        } else { connectionNotice = problem.localizedDescription }
    }
    private func connectionSucceeded() {
        connected = true; connectionNotice = nil; connectionNeedsSignIn = false; connectionNeedsSetup = false
        connectionFailures = 0; nextConnectionAttempt = .distantPast
    }
    @Published var error:String?
    @Published var showPaywall=false
    @Published var draftPrompt=UserDefaults.standard.string(forKey:"craftDraftPrompt") ?? "" {didSet{UserDefaults.standard.set(draftPrompt,forKey:"craftDraftPrompt")}}
    @Published var draftStyle=UserDefaults.standard.string(forKey:"craftDraftStyle") ?? "Stylized" {didSet{UserDefaults.standard.set(draftStyle,forKey:"craftDraftStyle")}}
    @Published private var selectionRevision=0
    @Published var draftImage:UIImage?
    @Published var busy=false
    @Published var path:[CraftRoute]=[]
    @Published var completedModelCards: [CraftJob] = []
    var completionTracker = ModelCompletionTracker()
    func openCompletedModel() {
        guard let job = completedModelCards.first, let asset = job.assets.first(where: { $0.modelURL != nil }) else { return }
        completedModelCards.removeFirst(); path.removeAll(); selectedTab = 1; path.append(.asset(asset))
    }
    @Published var selectedTab=0
    private var token:String?
    private var polling:Task<Void,Never>?
    private let pendingURL:URL
    private(set) var pendingGeneration:PendingGeneration?
    init(pendingURL:URL?=nil) {
        self.pendingURL=pendingURL ?? Self.draftURL.deletingLastPathComponent().appendingPathComponent("pending-generation.json")
        UserDefaults.standard.set(imageModelID, forKey: "craftImageModel")
        if let data=try? Data(contentsOf:self.pendingURL){pendingGeneration=try? JSONDecoder().decode(PendingGeneration.self,from:data)}
        if pendingGeneration?.accountUID != CraftAccount.shared.uid { pendingGeneration=nil;try? FileManager.default.removeItem(at:self.pendingURL) }
        if draftPrompt == Self.legacyDemoPrompt {draftPrompt=""}
        if !apiBase.isEmpty { UserDefaults.standard.set(apiBase, forKey: "craftAPI") }
        loadLibraryCache(); activeConversationID = UserDefaults.standard.string(forKey: "craftActiveConversation:" + apiBase); if let d=try? Data(contentsOf:Self.draftURL){draftImage=UIImage(data:d)}
    }
    private static var libraryCacheURL:URL {draftURL.deletingLastPathComponent().appendingPathComponent("library-cache.json")}
    private func loadLibraryCache() {
        guard let data=try?Data(contentsOf:Self.libraryCacheURL),let cache=(try?JSONSerialization.jsonObject(with:data)) as? [String:Any],cache["apiBase"] as? String==apiBase, cache["accountUID"] as? String == CraftAccount.shared.uid, CraftAccount.shared.uid != nil else{return}
        projects=(cache["projects"] as? [[String:Any]] ?? []).map{CraftProject($0,base:apiBase)}
        jobs=(cache["jobs"] as? [[String:Any]] ?? []).map{CraftJob($0,base:apiBase)}
        let a=cache["assets"] as? [String:Any] ?? [:]
        assets=(a["owned"] as? [[String:Any]] ?? []).map{CraftAsset($0,base:apiBase)}
        // Public examples come from the shipped catalog, not the account cache.
    }
    func persistPending(_ pending:PendingGeneration?) throws {
        if let pending {try JSONEncoder().encode(pending).write(to:pendingURL,options:.atomic)}
        else if FileManager.default.fileExists(atPath:pendingURL.path){try FileManager.default.removeItem(at:pendingURL)}
        pendingGeneration=pending
    }
    func resolvePending(from results:[CraftJob]) throws {
        guard let pending=pendingGeneration,let id=pending.jobID,
              let job=results.first(where:{$0.id==id}),["done","partial","failed"].contains(job.status) else{return}
        try persistPending(nil)
    }
    private func pendingNotice(){error=t("Your previous generation is still being confirmed. We will reuse that request, without charging for another attempt. Wait for its result before starting different work.","上一项生成正在确认。系统会复用原请求，不会重复扣费。请等待结果后再开始其他生成。")}
    private func handleGenerationError(_ problem:Error){
        if pendingGeneration != nil {connectionNotice=t("Confirming your generation request…","正在确认生成请求……");pendingNotice()}
        else{error=problem.localizedDescription}
    }
    private func submitPending() async throws ->String {
        guard var pending=pendingGeneration,pending.apiBase==apiBase else{throw CraftError(message:t("Reconnect to the original studio to confirm your pending generation.","请连接原工作室以确认待处理的生成。"))}
        do {
            let result:Any
            if let jobID=pending.jobID {result=try await request("/jobs/"+jobID)}
            else {result=try await request(pending.requestPath,method:"POST",data:pending.body)}
            guard let job=result as? [String:Any],let id=job["id"] as? String else{throw CraftError(message:"The generation response is incomplete. Confirming its status.")}
            if pending.requestPath.hasSuffix("/model") { completionTracker.watching.insert(id) }
            pending.jobID=id
            try persistPending(pending)
            if let status=job["status"] as? String,["done","partial","failed"].contains(status){try persistPending(nil)}
            return pending.projectID
        }catch {
            // A known 4xx rejection before we obtained a job ID did not enqueue
            // work. A timeout, malformed response or 5xx remains uncertain.
            if pending.jobID == nil,let failure=error as? CraftError,let status=failure.statusCode,[400,402,422].contains(status){try persistPending(nil)}
            throw error
        }
    }
    private func reconcilePending() async {
        guard !busy,pendingGeneration != nil else{return}
        busy=true;defer{busy=false}
        do{_=try await submitPending();await refresh()}catch{connectionNotice=t("Confirming your generation request…","正在确认生成请求……")}
    }
    private func prepareGeneration(path:String,projectID:String,payload:[String:Any],draftFingerprint:String?=nil) throws ->Bool {
        if let pending=pendingGeneration {
            guard pending.matches(base:apiBase,path:path,payload:payload,accountUID:CraftAccount.shared.uid) else{pendingNotice();return false}
        }else{try persistPending(.make(base:apiBase,path:path,projectID:projectID,payload:payload,draftFingerprint:draftFingerprint,accountUID:CraftAccount.shared.uid))}
        return true
    }
    private func draftFingerprint(count:Int)->String {
        let modelSuffix = imageModelID == CraftImageModel.defaultID ? "" : "\n" + imageModelID
        let plannerSuffix = plannerModelID == CraftPlannerModel.defaultID ? "" : "\nplanner:" + plannerModelID + "\neffort:" + plannerEffort
        let words=Data((draftPrompt+"\n"+draftStyle+"\n"+String(count)+modelSuffix+plannerSuffix).utf8)
        return PendingGeneration.fingerprint(words+(draftImage?.jpegData(compressionQuality:0.95) ?? Data()))
    }
    func t(_ en:String,_ zh:String)->String {isChinese ? zh:en}
    static var draftURL:URL {FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("draft-photo.jpg")}
    static let legacyDemoPrompt="A brave ginger tabby adventurer wearing a teal jacket, full body, one character, clean background"
    func selectConcept(_ concept:CraftConcept) {
        UserDefaults.standard.set(concept.id,forKey:"craftSelectedConcept:"+apiBase+":"+concept.projectId)
        selectionRevision += 1
    }
    func selectedConcept(in project:CraftProject)->CraftConcept? {
        let id=UserDefaults.standard.string(forKey:"craftSelectedConcept:"+apiBase+":"+project.id)
        return project.concepts.first{$0.id==id}
    }
    func saveDraftImage(_ image:UIImage?) {if image != nil && draftPrompt == Self.legacyDemoPrompt {draftPrompt=""};draftImage=image;if let data=image?.jpegData(compressionQuality:0.95){try?data.write(to:Self.draftURL,options:.atomic)}else{try?FileManager.default.removeItem(at:Self.draftURL)}}
    func eraseLocalAccountData() async {
        polling?.cancel(); polling = nil
        try? FileManager.default.removeItem(at: Self.libraryCacheURL)
        try? persistPending(nil)
        draftPrompt = ""; saveDraftImage(nil)
        UserDefaults.standard.removeObject(forKey: "craftActiveConversation:" + apiBase)
        if let uid = CraftAccount.shared.uid {
            let prefix = "craftPendingUpload:" + uid + ":"
            for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        await CraftImageCache.shared.erase()
        await CraftThumbnailCache.shared.erase()
        CraftDecodedImages.shared.clear()
        URLCache.shared.removeAllCachedResponses()
        let temporary = FileManager.default.temporaryDirectory
        for file in (try? FileManager.default.contentsOfDirectory(at: temporary, includingPropertiesForKeys: nil)) ?? [] {
            if file.pathExtension == "glb" || file.lastPathComponent.hasPrefix("3D-Craft-Game-") {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
    func accountChanged() async {
        polling?.cancel();polling=nil;connected=false;connectionNotice=nil
        completedModelCards=[];completionTracker=ModelCompletionTracker()
        projects=[];assets=[];jobs=[];wallet=WalletState();path=[];activeConversationID=nil
        purchaseToPresent=nil;walletCelebration=nil
        draftPrompt="";saveDraftImage(nil);try? persistPending(nil)
        aiAccount=CraftAIAccount();aiAccountLoaded=false
        showPaywall=false;error=nil
        if CraftAccount.shared.uid != nil { await connect() }
    }
    func connect() async {
        guard !connecting else{return}; startPolling();connecting=true;defer{connecting=false}
        await refreshCloudCreations()
        connectionNeedsSignIn = false; connectionNeedsSetup = false
        do {
            guard CraftAccount.shared.uid != nil else { connected=false;connectionNotice=nil;return }
            var migrationNotice: String?
            if let legacy = Self.readToken() {
                do { _ = try await request("/cloud-library/claim-device",method:"POST",body:["deviceToken":legacy]) }
                catch { migrationNotice = t("Your older device library could not be linked yet. Contact support if creations are missing.","旧设备作品库暂时无法关联。如果作品缺失，请联系支持。") }
            }
            _=try await request("/bootstrap");connectionSucceeded()
            await refresh();startPolling()
            if let migrationNotice { connectionNotice = migrationNotice }
            await refreshAIAccount()
            if path.isEmpty,let active=jobs.last(where:{$0.isActive}){path=[.project(active.projectId)]}
        }catch{connectionFailed(error)}
    }
    func refreshCloudCreations() async {
        let uid = CraftAccount.shared.uid
        guard uid != nil else { return }
        do {
            let saved = try await FirebaseCreationLibrary.load()
            if CraftAccount.shared.uid == uid { assets = saved }
        } catch { /* Keep the current cloud snapshot during transient failures. */ }
    }
    private var lastCloudSync = Date.distantPast
    private var cloudSyncing = false
    func refresh() async {
        guard let accountUID = CraftAccount.shared.uid else { return }
        do {
            let cloudAssets = try await FirebaseCreationLibrary.load()
            guard CraftAccount.shared.uid == accountUID else { return }
            assets = cloudAssets
            let p=try await request("/projects") as? [[String:Any]] ?? []
            let a=try await request("/assets") as? [String:Any] ?? [:]
            let j=try await request("/jobs") as? [[String:Any]] ?? []
            let w=try await request("/wallet") as? [String:Any] ?? [:]
            await refreshImageModelCatalog()
            await refreshPricing()
            guard CraftAccount.shared.uid == accountUID else { return }
            completionTracker.watching.formUnion(jobs.filter { $0.kind == "model" && $0.isActive }.map(\.id))
            projects=p.map{CraftProject($0,base:apiBase)};jobs=j.map{CraftJob($0,base:apiBase)}
            completedModelCards.append(contentsOf: completionTracker.receive(jobs))
            // Private library is authoritative in Firebase, shared with the website.
            examples = PublicGallery.bundled
            applyWallet(w);connectionSucceeded()
            if let data=try? JSONSerialization.data(withJSONObject:["accountUID":CraftAccount.shared.uid ?? "", "apiBase":apiBase,"projects":p,"assets":a,"jobs":j]){try?data.write(to:Self.libraryCacheURL,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])}
            try resolvePending(from:jobs)
            syncCloudLibrary()
        }catch{if CraftAccount.shared.uid == accountUID { connectionFailed(error) }}
    }
    func syncCloudLibrary(force: Bool = false) {
        guard !cloudSyncing, (force || Date().timeIntervalSince(lastCloudSync) > 15), CraftAccount.shared.uid != nil else { return }
        cloudSyncing = true; lastCloudSync = Date()
        Task { @MainActor in
            defer { self.cloudSyncing = false }
            do {
                let uid = CraftAccount.shared.uid
                for _ in 0..<100 {
                    guard uid != nil, uid == CraftAccount.shared.uid else { return }
                    let result = try await self.request("/cloud-library/sync", method:"POST") as? [String:Any]
                    if (result?["synced"] as? Int ?? 0) == 0 { break }
                }
            }
            catch { self.connectionNotice = self.t("Website library sync is pending. Your creations are saved here.","网站作品同步待完成，作品已保存在这里。") }
        }
    }
    private func startPolling(){guard polling == nil else{return};polling=Task{[weak self] in while !Task.isCancelled {try?await Task.sleep(nanoseconds:3_000_000_000);guard let self else{return};if !self.connected{if !self.connectionNeedsSignIn && !self.connectionNeedsSetup && Date() >= self.nextConnectionAttempt {await self.connect()}}else if self.pendingGeneration != nil{await self.reconcilePending()}else if self.jobs.contains(where:{$0.isActive}) || self.projects.contains(where:{$0.turns.contains(where:{$0.isActive})}){await self.refresh()}}}}
    func createConcepts(count:Int,originalOnly:Bool=false) async ->String? {
        guard !busy else{return nil};guard connected else{error=t("Please sign in or check your connection.","请先登录或检查网络连接。");return nil}
        guard !draftPrompt.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || draftImage != nil else{error=t("Add a photo or describe your idea.","请添加照片或描述你的想法。");return nil}
        guard (1...4).contains(count) else{error=t("Choose one to four views.","请选择一到四张视角概念图。");return nil}
        if originalOnly && pendingGeneration != nil {pendingNotice();return nil}
        if let pending=pendingGeneration {
            guard pending.apiBase==apiBase,pending.draftFingerprint==draftFingerprint(count:count) else{pendingNotice();return nil}
            busy=true;defer{busy=false}
            do{let id=try await submitPending();await refresh();return id}catch{handleGenerationError(error);return nil}
        }
        guard originalOnly || (imageModelIsReady() && (draftImage != nil || plannerIsReady())) else { return nil }
        guard originalOnly || wallet.available+wallet.freeConceptTokens >= conceptTokenCost(count: count) else{showPaywall=true;return nil}
        busy=true;defer{busy=false}
        let submittedFingerprint=draftFingerprint(count:count)
        let uploadKey=pendingUploadKey(scope:"project")
        let uploadID=uploadRequestID(key:uploadKey,fingerprint:submittedFingerprint)
        do {
            let boundary="Craft-"+UUID().uuidString;var data=Data()
            func add(_ text:String){data.append(Data(text.utf8))}
            let title=String(draftPrompt.prefix(44)).isEmpty ? "My new asset":String(draftPrompt.prefix(44))
            for (key,value) in ["name":title,"prompt":draftPrompt,"style":draftStyle,"clientId":uploadID]{add("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(value)\r\n")}
            if let photo=draftImage?.jpegData(compressionQuality:0.95){guard photo.count<=20*1024*1024 else{throw CraftError(message:t("Choose a photo under 20 MB.","请选择小于20 MB的照片。"))};add("--\(boundary)\r\nContent-Disposition: form-data; name=\"image\"; filename=\"reference.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n");data.append(photo);add("\r\n")}
            add("--\(boundary)--\r\n")
            let p=try await request("/projects",method:"POST",data:data,contentType:"multipart/form-data; boundary=\(boundary)") as? [String:Any] ?? [:]
            guard let id=p["id"] as? String else{throw CraftError(message:"Project could not be saved.")}
            if originalOnly {
                UserDefaults.standard.removeObject(forKey:uploadKey)
                await refresh()
                if let project=projects.first(where:{$0.id==id}),let original=project.concepts.first(where:{$0.isOriginal==true}) {selectConcept(original)}
                return id
            }
            guard try prepareGeneration(path:"/projects/\(id)/concepts",projectID:id,payload:imagePayload(["count":count,"preserveReference":draftImage != nil]),draftFingerprint:submittedFingerprint) else{return nil}
            UserDefaults.standard.removeObject(forKey:uploadKey)
            _=try await submitPending()
            await refresh();startPolling();return id
        }catch{handleGenerationError(error);return nil}
    }
    @discardableResult func addConcepts(to projectID:String,count:Int=4,prompt:String="",referenceID:String?=nil,preserveReference:Bool=false) async -> Bool {
        guard !busy else{return false}
        guard (1...4).contains(count) else{error=t("Choose one to four images.","请选择一到四张图片。");return false}
        guard pendingGeneration != nil || (imageModelIsReady() && (preserveReference || plannerIsReady())) else { return false }
        guard pendingGeneration != nil || wallet.available+wallet.freeConceptTokens>=conceptTokenCost(count: count) else{showPaywall=true;return false}
        busy=true;defer{busy=false}
        do{guard try prepareGeneration(path:"/projects/\(projectID)/concepts",projectID:projectID,payload:imagePayload(["count":count,"prompt":prompt,"referenceId":referenceID as Any? ?? NSNull(),"style":draftStyle,"preserveReference":preserveReference])) else{return false};_=try await submitPending();await refresh();startPolling();return true}catch{handleGenerationError(error);return false}
    }
    func refine(_ concept:CraftConcept,prompt:String) async {
        guard !busy else{return};guard pendingGeneration != nil || (imageModelIsReady() && plannerIsReady()) else{return};guard pendingGeneration != nil || wallet.available+wallet.freeConceptTokens>=conceptTokenCost(count: 1) else{showPaywall=true;return};busy=true;defer{busy=false}
        do{guard try prepareGeneration(path:"/concepts/\(concept.id)/refine",projectID:concept.projectId,payload:imagePayload(["prompt":prompt])) else{return};_=try await submitPending();await refresh();startPolling()}catch{handleGenerationError(error)}
    }
    func imagePayload(_ fields: [String:Any]) -> [String:Any] {
        var payload = fields
        // A legacy pending Gemini request must keep its exact original body.
        let legacy = pendingGeneration.flatMap { try? JSONSerialization.jsonObject(with: $0.body) as? [String:Any] }
        if imageModelID != CraftImageModel.defaultID || legacy == nil || legacy?["imageModel"] != nil {
            payload["imageModel"] = imageModelID
        }
        // Default planning retains legacy request signatures. A changed model
        // or effort changes request identity, never silently reuses a charge.
        if plannerModelID != CraftPlannerModel.defaultID || legacy?["plannerModel"] != nil {
            payload["plannerModel"] = plannerModelID
        }
        if (plannerModelID != CraftPlannerModel.defaultID && selectedPlannerModel?.reasoningEfforts.isEmpty != true) || legacy?["plannerEffort"] != nil {
            payload["plannerEffort"] = plannerEffort
        }
        return payload
    }
    private func plannerIsReady() -> Bool {
        if plannerModelID == CraftPlannerModel.defaultID { return true }
        guard aiAccountLoaded, aiAccount.connected, let model = selectedPlannerModel,
              model.reasoningEfforts.isEmpty || model.reasoningEfforts.contains(plannerEffort) else {
            error = t("This planning model is unavailable. Connect ChatGPT in Profile or choose Gemini for prompt planning.",
                      "此规划模型当前不可用。请在我的页面连接 ChatGPT，或选择 Gemini 规划提示词。")
            return false
        }
        return true
    }

    func selectPlanner(_ id: String) {
        if id == CraftPlannerModel.defaultID { plannerModelID = id; return }
        guard aiAccount.connected, let model = aiAccount.models.first(where: { $0.id == id }) else { return }
        plannerModelID = model.id
        if let effort = model.fastEffort { plannerEffort = effort }
    }

    func refreshAIAccount() async {
        guard !aiAccountRefreshing else { return }
        aiAccountRefreshing = true; defer { aiAccountRefreshing = false }
        let revision = aiAccountRevision
        do {
            let data = try await request("/ai/account") as? [String: Any] ?? [:]
            guard revision == aiAccountRevision else { return }
            applyAIAccount(data)
        } catch {
            guard revision == aiAccountRevision else { return }
            aiAccountLoaded = true; aiAccount = CraftAIAccount()
            aiAccountError = error.localizedDescription
        }
    }

    /// Publish one consistent account/catalog snapshot before clearing the login ID.
    /// Clearing it cancels AIAccountView's task(id:); never await more work afterward.
    func applyAIAccount(_ data: [String: Any]) {
        let account = CraftAIAccount(data)
        aiSnapshotRevision += 1
        if let entries = data["imageModels"] as? [[String: Any]],
           let bytes = try? JSONSerialization.data(withJSONObject: entries),
           let models = try? JSONDecoder().decode([CraftImageModel].self, from: bytes), !models.isEmpty {
            imageModels = models.filter { [CraftImageModel.defaultID, "codex-gpt-image-2"].contains($0.id) }
            imageModelsLoaded = true
        }
        // Compatibility with older studios: GPT availability comes from the same
        // account response, never from an earlier pre-login image catalog.
        imageModels = imageModels.map { model in
            guard model.id == "codex-gpt-image-2" else { return model }
            let ready = account.connected && account.imageGenerationSupported
            return CraftImageModel(id: model.id, name: model.name, provider: model.provider,
                available: ready, quality: model.quality, imageSize: model.imageSize,
                unavailableReason: ready ? nil : account.connected
                    ? t("Image generation is unavailable for this account.", "此账户暂未提供生图功能。")
                    : t("Connect your ChatGPT account", "连接你的 ChatGPT 账户"))
        }
        aiAccount = account; aiAccountLoaded = true; aiAccountError = nil
        if account.connected { aiLogin = nil }
        else if aiLogin != nil, ["failed", "cancelled"].contains(account.loginStatus ?? "") {
            aiLogin = nil
            aiAccountError = t("The connection did not complete. You can start again.", "本次连接未完成，可以重新开始。")
        }
    }

    func beginAILogin() async -> CraftAILogin? {
        guard !aiAccountBusy, aiAccount.available, !aiAccount.connected else { return nil }
        aiAccountBusy = true; aiAccountError = nil; aiAccountRevision += 1
        let revision = aiAccountRevision
        defer { aiAccountBusy = false }
        do {
            // A previous attempt can survive closing the sheet or restarting
            // the phone. Cancel it before asking OpenAI for a fresh code.
            if let previous = aiLogin?.id ?? (aiAccount.loginStatus == "pending" ? aiAccount.pendingLoginID : nil) {
                _ = try await request("/ai/login/cancel", method: "POST", body: ["loginId": previous])
                guard revision == aiAccountRevision else { return nil }
                aiLogin = nil
            }
            let data = try await request("/ai/login", method: "POST") as? [String: Any] ?? [:]
            guard revision == aiAccountRevision else { return nil }
            guard let login = CraftAILogin(data) else {
                throw CraftError(message: t("The studio returned an invalid OpenAI sign-in link. Try refreshing the connection.",
                                            "工作室返回的 OpenAI 登录链接无效，请刷新连接后重试。"))
            }
            aiLogin = login
            return login
        } catch { aiAccountError = error.localizedDescription; return nil }
    }

    func cancelAILogin(expired: Bool = false) async {
        guard let login = aiLogin, !aiAccountBusy else { return }
        aiAccountBusy = true; aiAccountRevision += 1
        defer { aiAccountBusy = false; if aiLogin?.id == login.id { aiLogin = nil } }
        do {
            _ = try await request("/ai/login/cancel", method: "POST", body: ["loginId": login.id])
            aiAccountError = expired ? t("This connection attempt timed out. Start again for a new code.", "本次连接等待已超时，请重新获取代码。") : nil
        } catch { aiAccountError = error.localizedDescription }
    }

    func logoutAIAccount() async {
        guard !aiAccountBusy else { return }
        aiAccountBusy = true; aiAccountRevision += 1
        defer { aiAccountBusy = false }
        do {
            _ = try await request("/ai/logout", method: "POST")
            let available = aiAccount.available
            aiAccount = CraftAIAccount(); aiAccount.available = available; aiLogin = nil; aiAccountError = nil
            await refreshAIAccount()
            await refreshImageModelCatalog()
        } catch { aiAccountError = error.localizedDescription }
    }
    private func refreshPricing() async {
        let base = apiBase
        guard let catalog = try? await request("/pricing") as? [String: Any],
              let entries = catalog["models"] as? [String: Any],
              let bytes = try? JSONSerialization.data(withJSONObject: entries),
              let prices = try? JSONDecoder().decode([String: CraftModelPrice].self, from: bytes),
              base == apiBase else { modelPrices = [:]; return }
        modelPrices = prices
        pricesVerifiedAt = catalog["verifiedAt"] as? String ?? ""
        if let policy = catalog["billingPolicy"] as? [String: Any], let rate = policy["serviceFeeRate"] as? String, let value = Double(rate), value.isFinite, value >= 0 { serviceFeeRate = value }
    }
    func modelTokenCost(_ id: String, views: Int = 1, effort: String = "high") -> Int? {
        guard let price = modelPrices[id] else { return nil }
        return views > 1 ? price.multiTexturedCredits : (price.effortCredits?[effort] ?? price.texturedCredits)
    }
    func modelTokenLabel(_ id: String, views: Int = 1, effort: String = "high") -> String {
        guard let cost = modelTokenCost(id, views: views, effort: effort) else { return t("Price pending", "价格待确认") }
        return "\(cost) Tokens"
    }
    func modelPriceLabel(_ id: String, views: Int = 1, effort: String = "high") -> String {
        guard let cost = modelPrices[id]?.modelCost(views: views, effort: effort) else { return t("Price pending", "价格待确认") }
        return t("≈\(CraftModelPrice.usd(cost))/generation", "约 \(CraftModelPrice.usd(cost))/次")
    }
    func plannerPriceLabel(_ id: String) -> String {
        if id != CraftPlannerModel.defaultID {
            return t("0 app Tokens · Your ChatGPT account limits apply", "0 App Tokens · 使用你的 ChatGPT 账户额度")
        }
        return priceLabel(id)
    }
    func priceLabel(_ id: String) -> String {
        guard let price = modelPrices[id] else { return t("Price pending verification", "价格待核实") }
        switch price.unit {
        case "account": return t("0 app Tokens · Your ChatGPT account limits apply", "0 App Tokens · 使用你的 ChatGPT 账户额度")
        case "tokens":
            guard let input = price.inputPerMillion, let output = price.outputPerMillion else { break }
            return t("Input \(CraftModelPrice.usd(input)) · Output \(CraftModelPrice.usd(output)) / 1M tokens", "输入 \(CraftModelPrice.usd(input)) · 输出 \(CraftModelPrice.usd(output)) / 百万 tokens")
        case "image":
            guard let cost = price.unitUsd else { break }
            return t("≈\(CraftModelPrice.usd(cost))/2K image + token usage", "约 \(CraftModelPrice.usd(cost))/张 2K 图 + token 用量")
        case "generation": return modelPriceLabel(id)
        default: break
        }
        return t("Price pending verification", "价格待核实")
    }
    func conceptTokenCost(count: Int) -> Int {
        imageModelID == "codex-gpt-image-2" ? 0 : count * 15
    }
    func conceptPriceSummary(count: Int) -> String {
        var lines: [String] = []
        if let price = modelPrices[imageModelID], price.unit == "image", let cost = price.unitUsd {
            lines.append(t("API estimate · \(count) × \(CraftModelPrice.usd(cost)) = \(CraftModelPrice.usd(cost * Double(count))) image output", "API 估算 · \(count) × \(CraftModelPrice.usd(cost)) = \(CraftModelPrice.usd(cost * Double(count))) 图片输出"))
            lines.append(t("Input and text/thinking tokens are additional; this is not the final total.", "另计输入、文字及思考 tokens；这不是最终总价。"))
        } else { lines.append(priceLabel(imageModelID)) }
        lines.append(t("Planning: ", "提示词规划：") + plannerPriceLabel(plannerModelID))
        lines.append(t("App credits: \(conceptTokenCost(count: count)) Tokens, listed separately from API cost.", "App 积分：\(conceptTokenCost(count: count)) Tokens，与 API 成本分开列出。"))
        return lines.joined(separator: "\n")
    }
    private func refreshImageModelCatalog() async {
        let base = apiBase
        let revision = aiSnapshotRevision
        if let catalog = try? await request("/image-models") as? [String:Any],
           let entries = catalog["models"] as? [[String:Any]],
           let bytes = try? JSONSerialization.data(withJSONObject: entries),
           let models = try? JSONDecoder().decode([CraftImageModel].self, from: bytes),
           !models.isEmpty, base == apiBase, revision == aiSnapshotRevision {
            imageModels = models.filter { [CraftImageModel.defaultID, "codex-gpt-image-2"].contains($0.id) }; imageModelsLoaded = true
        }
    }
    private func imageModelIsReady() -> Bool {
        if imageModelID == "codex-gpt-image-2", aiAccountLoaded, aiAccount.connected, aiAccount.imageGenerationSupported { return true }
        guard selectedImageModel?.available == true, imageModelsLoaded else {
            error = imageModelID == "codex-gpt-image-2"
                ? t("Connect your ChatGPT account in Profile to use GPT Image 2, or choose Gemini.", "请在我的页面连接自己的 ChatGPT 账户以使用 GPT Image 2，或选择 Gemini。")
                : t("Gemini is currently unavailable. Please try again later.", "Gemini 暂不可用，请稍后重试。")
            return false
        }
        return true
    }
    static func modelPayload(engine:String,quality:String,effort:String,conceptIds:[String],modelPrompt:String?=nil)->[String:Any] {
        var payload:[String:Any] = ["engine":engine,"quality":quality,"effort":effort]
        if !conceptIds.isEmpty {payload["conceptIds"]=conceptIds}
        if let modelPrompt { payload["modelPrompt"] = modelPrompt }
        return payload
    }
    func improveModelPrompt(_ concept: CraftConcept, text: String) async throws -> String {
        guard plannerIsReady() else { throw CraftError(message: error ?? t("Choose an available planning model.", "请选择可用的规划模型。")) }
        let result = try await request("/concepts/\(concept.id)/model-prompt", method: "POST",
            body: ["prompt": text, "plannerModel": plannerModelID, "plannerEffort": plannerEffort]) as? [String:Any]
        guard let prompt = result?["prompt"] as? String, !prompt.isEmpty, prompt.unicodeScalars.count <= 800 else {
            throw CraftError(message: t("No usable prompt was returned. Your text is unchanged.", "未收到可用的描述，原文保持不变。"))
        }
        return prompt
    }
    func generateModel(_ concept:CraftConcept,engine:String="rodin",quality:String="default",effort:String="high",conceptIds:[String]=[],modelPrompt:String?=nil) async {
        guard !busy else { return }
        if pendingGeneration == nil {
            guard let cost = modelTokenCost(engine, views: max(1, conceptIds.count), effort: effort) else {
                error = t("Price pending for these settings. Choose a single view or another model.", "此设置的价格待确认，请选择单张视图或其他模型。")
                return
            }
            guard wallet.available >= cost else { showPaywall = true; return }
        }
        busy=true;defer{busy=false}
        do{guard try prepareGeneration(path:"/concepts/\(concept.id)/model",projectID:concept.projectId,payload:Self.modelPayload(engine:engine,quality:quality,effort:effort,conceptIds:conceptIds,modelPrompt:modelPrompt)) else{return};_=try await submitPending();await refresh();startPolling()}catch{handleGenerationError(error)}
    }
    func replenishTestCredits() async {
        do {
            let result=try await request("/development/credits",method:"POST") as? [String:Any] ?? [:]
            applyWallet(result);showPaywall=false
        } catch { self.error=error.localizedDescription }
    }
    func creditPurchase(_ purchase:BillingManager.VerifiedPurchase) async throws {
        let result=try await request("/development/purchase",method:"POST",body:["productId":purchase.productID,"transactionId":"storekit-xcode:"+String(purchase.transactionID)]) as? [String:Any] ?? [:]
        applyWallet(result)
    }
    func creditRevenueCatPurchase(productID: String, transactionID: String, presentPurchase: Bool = false) async throws {
        let uid = CraftAccount.shared.uid
        let result = try await request("/purchases/revenuecat", method: "POST", body: ["productId": productID, "transactionId": transactionID]) as? [String: Any] ?? [:]
        guard let uid, CraftAccount.shared.uid == uid else { return }
        applyWallet(result)
        if let receipt = result["purchaseReceiptID"] as? String,
           let tokens = result["purchaseTokens"] as? Int, tokens > 0,
           presentPurchase || (result["purchaseCredit"] as? Int ?? 0) > 0 {
            let key = "craft.purchasePresented:" + uid + ":" + receipt
            if !UserDefaults.standard.bool(forKey: key) {
                guard purchaseToPresent?.presentationKey != key, walletCelebration?.presentationKey != key else { return }
                purchaseToPresent = PurchaseCelebration(tokens: tokens, balance: wallet.available, presentationKey: key)
            }
        }
    }
    func markPurchaseAnimationVisible(_ receipt: PurchaseCelebration) {
        guard walletCelebration?.id == receipt.id else { return }
        if let key = receipt.presentationKey { UserDefaults.standard.set(true, forKey: key) }
    }
    func syncRevenueCatWallet() async throws {
        let uid = CraftAccount.shared.uid
        let result = try await request("/purchases/revenuecat/sync", method: "POST") as? [String: Any] ?? [:]
        guard uid != nil, CraftAccount.shared.uid == uid else { return }
        applyWallet(result)
    }
    func export(_ asset:CraftAsset) async throws ->URL {
        guard let url=asset.modelURL else{throw CraftError(message:"No model file is available.")}
        if url.isFileURL{return url}
        let (data,response)=try await CraftCloudMedia.data(url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else{throw CraftError(message:"The model could not be downloaded. Please try again.")}
        let dest=FileManager.default.temporaryDirectory.appendingPathComponent(asset.id+".glb");try data.write(to:dest,options:.atomic);return dest
    }
    private func applyWallet(_ d:[String:Any]){
        wallet.environment = d["environment"] as? String ?? "PRODUCTION"
        wallet.packAvailable = d["packAvailable"] as? Int
        wallet.subscriptionAvailable = d["subscriptionAvailable"] as? Int ?? 0
        wallet.subscriptionExpiresAt = (d["subscriptionExpiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        wallet.available=d["available"] as? Int ?? 0;wallet.freeConceptTokens=d["freeConceptTokens"] as? Int ?? 0;wallet.reserved=d["reserved"] as? Int ?? 0
        wallet.ledger=(d["ledger"] as? [[String:Any]] ?? []).enumerated().map{index,e in WalletEntry(id:String(describing:e["id"] ?? index),description:e["kind"] as? String ?? e["reason"] as? String ?? "Token activity",amount:e["amount"] as? Int ?? e["delta"] as? Int ?? 0,date:Date(timeIntervalSince1970:(e["createdAt"] as? NSNumber)?.doubleValue ?? (e["created"] as? NSNumber)?.doubleValue ?? Date().timeIntervalSince1970))}
    }
    func updateConnection(_ base:String) async {apiBase=StudioConnection.cloudURL;UserDefaults.standard.set(apiBase,forKey:"craftAPI");await connect()}
    func communityRequest(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Any {
        // Independent Cloud API storage in Firebase Firestore, no local Mac server required
        if path.hasPrefix("/games?") || (path == "/games" && method == "GET") {
            let components = URLComponents(string: "http://dummy" + path)
            let category = components?.queryItems?.first(where: { $0.name == "category" })?.value ?? "fun"
            let offset = Int(components?.queryItems?.first(where: { $0.name == "offset" })?.value ?? "0") ?? 0
            return try await CommunityCloudService.fetchGames(category: category, offset: offset)
        }
        if path == "/mine" {
            return try await CommunityCloudService.fetchMySubmissions()
        }
        if path == "/check-link", let url = body?["url"] as? String {
            return try await CommunityCloudService.checkLink(urlString: url)
        }
        if path == "/games" && method == "POST", let b = body {
            let title = b["title"] as? String ?? ""
            let creator = b["creator"] as? String ?? ""
            let desc = b["description"] as? String ?? ""
            let url = b["url"] as? String ?? ""
            return try await CommunityCloudService.publishGame(title: title, creator: creator, description: desc, urlString: url)
        }
        if path.hasPrefix("/games/") && path.hasSuffix("/vote") && method == "PUT", let b = body {
            let parts = path.components(separatedBy: "/")
            if parts.count >= 3 {
                let gameId = parts[2]
                let cat = b["category"] as? String ?? "fun"
                let liked = b["liked"] as? Bool ?? true
                return try await CommunityCloudService.vote(gameId: gameId, category: cat, liked: liked)
            }
        }
        if path.hasPrefix("/games/") && method == "DELETE" {
            let parts = path.components(separatedBy: "/")
            if parts.count >= 3 {
                let gameId = parts[2]
                try await CommunityCloudService.deleteGame(gameId: gameId)
                return ["removed": true]
            }
        }
        if path.hasPrefix("/games/") && path.hasSuffix("/play") {
            let parts = path.components(separatedBy: "/")
            if parts.count >= 3 {
                let gameId = parts[2]
                return try await CommunityCloudService.playGame(gameId: gameId)
            }
        }
        if path.hasPrefix("/games/") && path.hasSuffix("/recheck") && method == "POST" {
            return ["status": "rechecked"]
        }
        if path.hasPrefix("/games/") && path.hasSuffix("/report") && method == "POST" {
            return ["reported": true]
        }
        
        let publicRead = method == "GET" && (path.hasPrefix("/games?") || path.hasSuffix("/play"))
        return try await request("/community" + path, method: method, body: body, allowAnonymous: publicRead)
    }
    private func request(_ path:String,method:String="GET",body:[String:Any]?=nil,data:Data?=nil,contentType:String="application/json",allowAnonymous:Bool=false) async throws ->Any {
        let requestUID=CraftAccount.shared.uid
        guard !apiBase.isEmpty else { throw CraftError(message: t("Service is temporarily unavailable.", "服务暂时不可用。")) }
        let base = apiBase.hasSuffix("/api/mobile") ? apiBase : (apiBase + "/api/mobile")
        guard let url=URL(string:base+path),["http","https"].contains(url.scheme ?? "") else{throw CraftError(message:"Invalid server URL.")}
        let host = url.host?.lowercased() ?? ""
        let isLocal = ["127.0.0.1", "localhost"].contains(host) || host.hasSuffix(".local") || host.starts(with: "192.168.") || host.starts(with: "10.") || host.starts(with: "172.")
        if !isLocal && url.scheme?.lowercased() != "https" {
            throw CraftError(message: t("Insecure connection. Connections must use HTTPS.", "连接不安全。连接必须使用 HTTPS。"))
        }
        var r=URLRequest(url:url,cachePolicy:.reloadIgnoringLocalCacheData);r.httpMethod=method;r.timeoutInterval=path == "/cloud-library/sync" ? 150 : 30;r.setValue(contentType,forHTTPHeaderField:"Content-Type")
        if !allowAnonymous || requestUID != nil { let credential=try await CraftAccount.shared.token();r.setValue("Bearer "+credential,forHTTPHeaderField:"Authorization") }
        r.httpBody=try body.map{try JSONSerialization.data(withJSONObject:$0)} ?? data
        var (bytes,response)=try await URLSession.shared.data(for:r)
        if (response as? HTTPURLResponse)?.statusCode == 401, requestUID != nil, requestUID == CraftAccount.shared.uid {
            let refreshed = try await CraftAccount.shared.token(forceRefresh: true)
            r.setValue("Bearer " + refreshed, forHTTPHeaderField: "Authorization")
            (bytes,response) = try await URLSession.shared.data(for:r)
        }
        guard (allowAnonymous || requestUID != nil), requestUID == CraftAccount.shared.uid else { throw CraftError(message:"Your account changed. Please try again.",statusCode:401) }
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.mimeType == "application/json",
              let result = try? JSONSerialization.jsonObject(with: bytes) else {
            throw CraftError(message: t("The cloud studio is temporarily unavailable. Please try again shortly.", "云端工作室暂时不可用，请稍后重试。"), statusCode: 503)
        }
        guard let http=response as? HTTPURLResponse,(200..<300).contains(http.statusCode) else{
            let detail=(result as? [String:Any])?["detail"] as? String
            throw CraftError(message:detail ?? t("Unable to reach the server. Check your internet connection and try again.","无法连接服务器，请检查网络连接后重试。"),statusCode:(response as? HTTPURLResponse)?.statusCode)
        };return result
    }
    private static var reviewCredentialURL:URL {draftURL.deletingLastPathComponent().appendingPathComponent(".review-session")}
    private static let tokenAccount = "studio.craft.session.token"
    private static func readToken()->String? {
        #if targetEnvironment(simulator)
        // Unsigned simulator apps may not have a Keychain access group. Keep
        // the local-only review credential in the private app container.
        if let data=try?Data(contentsOf:reviewCredentialURL),let value=String(data:data,encoding:.utf8){return value}
        #endif
        var result:CFTypeRef?
        let q:[String:Any]=[
            kSecClass as String:kSecClassGenericPassword,
            kSecAttrService as String:"studio.craft.session",
            kSecAttrAccount as String:tokenAccount,
            kSecReturnData as String:true,
            kSecMatchLimit as String:kSecMatchLimitOne
        ]
        guard SecItemCopyMatching(q as CFDictionary,&result)==errSecSuccess,let data=result as? Data else{return nil}
        return String(data:data,encoding:.utf8)
    }
    private static func saveToken(_ token:String){
        #if targetEnvironment(simulator)
        try?Data(token.utf8).write(to:reviewCredentialURL,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
        #endif
        let q:[String:Any]=[
            kSecClass as String:kSecClassGenericPassword,
            kSecAttrService as String:"studio.craft.session",
            kSecAttrAccount as String:tokenAccount
        ]
        SecItemDelete(q as CFDictionary)
        var value=q
        value[kSecValueData as String]=Data(token.utf8)
        value[kSecAttrAccessible as String]=kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(value as CFDictionary,nil)
    }
    static func deleteToken() {
        #if targetEnvironment(simulator)
        try? FileManager.default.removeItem(at: reviewCredentialURL)
        #endif
        let q:[String:Any]=[
            kSecClass as String:kSecClassGenericPassword,
            kSecAttrService as String:"studio.craft.session",
            kSecAttrAccount as String:tokenAccount
        ]
        SecItemDelete(q as CFDictionary)
    }
}
