import Foundation

/// Independent Cloud API service for Community Games & Leaderboard.
/// Connects directly to Firebase Firestore cloud endpoints without requiring
/// a running local Mac development server or local profile settings.
@MainActor
enum CommunityCloudService {
    static let projectID = "forma-studio-2026"
    static let firestoreBase = "https://firestore.googleapis.com/v1/projects/\(projectID)/databases/(default)/documents"
    static let gamesCollection = "\(firestoreBase)/communityGames"
    static let categories = ["fun", "animation", "visuals", "creativity"]
    
    // MARK: - Firestore Serialization Helpers
    
    static func parseFirestoreDoc(_ doc: [String: Any]) -> [String: Any]? {
        guard let fields = doc["fields"] as? [String: Any] else { return nil }
        var result: [String: Any] = [:]
        for (key, val) in fields {
            if let v = val as? [String: Any] {
                result[key] = parseFirestoreValue(v)
            }
        }
        if let name = doc["name"] as? String, result["id"] == nil {
            result["id"] = name.components(separatedBy: "/").last ?? ""
        }
        return result
    }
    
    static func parseFirestoreValue(_ val: [String: Any]) -> Any {
        if let s = val["stringValue"] as? String { return s }
        if let b = val["booleanValue"] as? Bool { return b }
        if let i = val["integerValue"] as? String { return Int(i) ?? 0 }
        if let i = val["integerValue"] as? Int { return i }
        if let d = val["doubleValue"] as? Double { return d }
        if let m = val["mapValue"] as? [String: Any], let fields = m["fields"] as? [String: Any] {
            var sub: [String: Any] = [:]
            for (k, v) in fields {
                if let vf = v as? [String: Any] {
                    sub[k] = parseFirestoreValue(vf)
                }
            }
            return sub
        }
        if let a = val["arrayValue"] as? [String: Any], let values = a["values"] as? [[String: Any]] {
            return values.map { parseFirestoreValue($0) }
        }
        return ""
    }
    
    static func encodeFirestoreValue(_ val: Any) -> [String: Any] {
        if let b = val as? Bool { return ["booleanValue": b] }
        if let i = val as? Int { return ["integerValue": String(i)] }
        if let d = val as? Double { return ["doubleValue": d] }
        if let s = val as? String { return ["stringValue": s] }
        if let dict = val as? [String: Any] {
            var fields: [String: Any] = [:]
            for (k, v) in dict {
                fields[k] = encodeFirestoreValue(v)
            }
            return ["mapValue": ["fields": fields]]
        }
        if let arr = val as? [Any] {
            return ["arrayValue": ["values": arr.map { encodeFirestoreValue($0) }]]
        }
        return ["stringValue": String(describing: val)]
    }

    // MARK: - Cloud Operations
    
    static func checkLink(urlString: String) async throws -> [String: Any] {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host?.lowercased(), !host.isEmpty else {
            throw CraftError(message: "Enter a valid game link starting with https://")
        }
        if scheme != "https" {
            throw CraftError(message: "Game links must use secure HTTPS.")
        }
        
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 12
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) {
                return ["url": url.absoluteString, "checkedAt": Date().timeIntervalSince1970, "message": "Public page opens."]
            }
            // Some platforms return 403 to automated clients; allow well-known game hosting sites
            if host.contains("claude.ai") || host.contains("chatgpt.com") || host.contains("web.app") || host.contains("github.io") {
                return ["url": url.absoluteString, "checkedAt": Date().timeIntervalSince1970, "message": "Public page opens."]
            }
            throw CraftError(message: "The game page could not be opened (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)).")
        } catch let e as CraftError {
            throw e
        } catch {
            if host.contains("claude.ai") || host.contains("chatgpt.com") || host.contains("web.app") || host.contains("github.io") {
                return ["url": url.absoluteString, "checkedAt": Date().timeIntervalSince1970, "message": "Public page opens."]
            }
            throw CraftError(message: "Could not open game link: \(error.localizedDescription)")
        }
    }
    
    static func fetchGames(category: String = "fun", offset: Int = 0) async throws -> [String: Any] {
        guard let url = URL(string: "\(gamesCollection)?pageSize=300") else {
            throw CraftError(message: "Invalid cloud URL")
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        if let token = try? await CraftAccount.shared.token() {
            req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CraftError(message: "Could not load community games from cloud.")
        }
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let docs = root["documents"] as? [[String: Any]] ?? []
        let currentUID = CraftAccount.shared.uid ?? ""
        
        var parsedGames: [[String: Any]] = []
        for doc in docs {
            if let game = parseFirestoreDoc(doc) {
                let removed = game["removed"] as? Bool ?? false
                if removed { continue }
                
                var g = game
                let votesMap = game["votes"] as? [String: Any] ?? [:]
                var votes: [String: Int] = ["fun": 0, "animation": 0, "visuals": 0, "creativity": 0]
                for cat in categories {
                    votes[cat] = (votesMap[cat] as? Int) ?? 0
                }
                g["votes"] = votes
                let rawOwner = (game["ownerId"] as? String) ?? (game["owner"] as? String ?? "")
                let ownerId = rawOwner.replacingOccurrences(of: "firebase:", with: "")
                g["isMine"] = (!currentUID.isEmpty && currentUID == ownerId)
                g["myVotes"] = [String]()
                parsedGames.append(g)
            }
        }
        
        // Sort games by selected category votes descending
        parsedGames.sort { a, b in
            let vA = (a["votes"] as? [String: Int])?[category] ?? 0
            let vB = (b["votes"] as? [String: Int])?[category] ?? 0
            if vA != vB { return vA > vB }
            let tA = a["createdAt"] as? Double ?? 0
            let tB = b["createdAt"] as? Double ?? 0
            return tA > tB
        }
        
        // Fetch vote states in bounded parallel batches instead of one network
        // round trip per game. A list refresh no longer grows linearly in latency.
        if !currentUID.isEmpty {
            for start in stride(from:0,to:parsedGames.count,by:6) {
                let ids=parsedGames[start..<min(start+6,parsedGames.count)].compactMap{$0["id"] as? String}
                let states=await withTaskGroup(of:(String,[String]?).self, returning:[String:[String]].self) { group in
                    for id in ids { group.addTask { (id,await fetchUserVote(gameId:id,userUID:currentUID)) } }
                    var states=[String:[String]]()
                    for await (id,cats) in group { if let cats { states[id]=cats } }
                    return states
                }
                for i in start..<min(start+6,parsedGames.count) {
                    if let id=parsedGames[i]["id"] as? String, let cats=states[id] { parsedGames[i]["myVotes"]=cats }
                }
            }
        }

        return ["games": parsedGames, "hasMore": false, "categories": categories]
    }
    
    static func fetchMySubmissions() async throws -> [[String: Any]] {
        guard let currentUID = CraftAccount.shared.uid, !currentUID.isEmpty else {
            return []
        }
        let result = try await fetchGames(category: "fun", offset: 0)
        let games = result["games"] as? [[String: Any]] ?? []
        return games.filter { ($0["isMine"] as? Bool) == true }
    }
    
    static func fetchUserVote(gameId: String, userUID: String) async -> [String]? {
        guard let url = URL(string: "\(gamesCollection)/\(gameId)/votes/\(userUID)") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 4
        guard let token = try? await CraftAccount.shared.token() else { return nil }
        req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let doc = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let parsed = parseFirestoreDoc(doc) else {
            return nil
        }
        if let cats = parsed["categories"] as? [String] {
            return cats
        }
        return nil
    }
    
    static func publishGame(title: String, creator: String, description: String, urlString: String) async throws -> [String: Any] {
        guard let uid = CraftAccount.shared.uid, !uid.isEmpty else {
            throw CraftError(message: "Please sign in to publish a game.")
        }
        let token = try await CraftAccount.shared.token()
        let gameId = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        guard let url = URL(string: "\(gamesCollection)/\(gameId)") else {
            throw CraftError(message: "Invalid cloud URL")
        }
        let now = Date().timeIntervalSince1970
        let votesMap: [String: Any] = ["fun": 0, "animation": 0, "visuals": 0, "creativity": 0]
        let fields: [String: Any] = [
            "id": encodeFirestoreValue(gameId),
            "title": encodeFirestoreValue(title),
            "creator": encodeFirestoreValue(creator),
            "description": encodeFirestoreValue(description),
            "url": encodeFirestoreValue(urlString),
            "ownerId": encodeFirestoreValue(uid),
            "owner": encodeFirestoreValue("firebase:\(uid)"),
            "createdAt": encodeFirestoreValue(now),
            "checkedAt": encodeFirestoreValue(now),
            "reachable": encodeFirestoreValue(true),
            "removed": encodeFirestoreValue(false),
            "likes": encodeFirestoreValue(0),
            "votes": encodeFirestoreValue(votesMap),
            "updatedAt": encodeFirestoreValue(now)
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["fields": fields])
        req.timeoutInterval = 15
        
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"]
            throw CraftError(message: "Failed to publish game to cloud: \(detail ?? "")")
        }
        
        return [
            "id": gameId,
            "title": title,
            "creator": creator,
            "description": description,
            "url": urlString,
            "createdAt": now,
            "checkedAt": now,
            "reachable": true,
            "votes": votesMap,
            "myVotes": [String](),
            "isMine": true
        ]
    }
    
    /// Idempotent intent: retrying "liked=true" never adds a second vote.
    static func applyingVote(to game: [String:Any], existing: [String], category: String, liked: Bool) -> [String:Any] {
        var result=game
        var cats=Set(existing)
        let wasLiked=cats.contains(category)
        if liked { cats.insert(category) } else { cats.remove(category) }
        var counts=game["votes"] as? [String:Int] ?? [:]
        counts[category]=max(0,(counts[category] ?? 0)+(wasLiked == liked ? 0 : liked ? 1 : -1))
        result["votes"]=counts;result["likes"]=counts.values.reduce(0,+)
        result["myVotes"]=cats.sorted()
        return result
    }

    static func vote(gameId: String, category: String, liked: Bool) async throws -> [String: Any] {
        guard let uid=CraftAccount.shared.uid, !uid.isEmpty else { throw CraftError(message:"Please sign in to vote.") }
        guard categories.contains(category), !gameId.isEmpty, !gameId.contains("/"), !uid.contains("/") else { throw CraftError(message:"Invalid vote") }
        let token=try await CraftAccount.shared.token()
        let gameURL=URL(string:"\(gamesCollection)/\(gameId)")!
        let voteURL=URL(string:"\(gamesCollection)/\(gameId)/votes/\(uid)")!
        @Sendable func read(_ url: URL, missingOK: Bool = false) async throws -> [String:Any]? {
            var req=URLRequest(url:url);req.timeoutInterval=15
            req.setValue("Bearer "+token,forHTTPHeaderField:"Authorization")
            let (data,response)=try await URLSession.shared.data(for:req)
            let status=(response as? HTTPURLResponse)?.statusCode ?? 0
            if missingOK && status==404 { return nil }
            guard status==200, let doc=try JSONSerialization.jsonObject(with:data) as? [String:Any] else { throw CraftError(message:"Could not read your vote. Please retry.") }
            return doc
        }
        for _ in 0..<3 {
            async let gameRead=read(gameURL)
            async let voteRead=read(voteURL,missingOK:true)
            let (gameDoc,voteDoc)=try await (gameRead,voteRead)
            guard let gameDoc, let game=parseFirestoreDoc(gameDoc), let stamp=gameDoc["updateTime"] as? String,
                  let gameName=gameDoc["name"] as? String else { throw CraftError(message:"Game is unavailable") }
            let existing=voteDoc.flatMap(parseFirestoreDoc)?["categories"] as? [String] ?? []
            let updated=applyingVote(to:game,existing:existing,category:category,liked:liked)
            if existing.contains(category)==liked { return updated }
            guard CraftAccount.shared.uid==uid else { throw CancellationError() }
            let voteName=gameName+"/votes/"+uid
            let voteCondition: [String:Any] = voteDoc == nil ? ["exists":false] : ["updateTime":voteDoc?["updateTime"] as? String ?? ""]
            let writes: [[String:Any]] = [
                ["update":["name":voteName,"fields":["userId":encodeFirestoreValue(uid),"categories":encodeFirestoreValue(updated["myVotes"]!),"updatedAt":encodeFirestoreValue(Date().timeIntervalSince1970)]],"currentDocument":voteCondition],
                ["update":["name":gameName,"fields":["votes":encodeFirestoreValue(updated["votes"]!),"likes":encodeFirestoreValue(updated["likes"]!),"updatedAt":encodeFirestoreValue(Date().timeIntervalSince1970)]],"updateMask":["fieldPaths":["votes","likes","updatedAt"]],"currentDocument":["updateTime":stamp]]
            ]
            var req=URLRequest(url:URL(string:firestoreBase+":commit")!);req.httpMethod="POST";req.timeoutInterval=15
            req.setValue("Bearer "+token,forHTTPHeaderField:"Authorization");req.setValue("application/json",forHTTPHeaderField:"Content-Type")
            req.httpBody=try JSONSerialization.data(withJSONObject:["writes":writes])
            let (data,response)=try await URLSession.shared.data(for:req)
            let status=(response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(status) { return updated }
            let problem=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any]
            let code=(problem?["error"] as? [String:Any])?["status"] as? String ?? ""
            if status==409 || ["ABORTED","FAILED_PRECONDITION"].contains(code) { continue }
            throw CraftError(message:"Your vote could not be saved. Please retry.")
        }
        throw CraftError(message:"The votes changed while saving. Please try again.")
    }

    static func deleteGame(gameId: String) async throws {
        guard let uid = CraftAccount.shared.uid, !uid.isEmpty else {
            throw CraftError(message: "Please sign in to remove a game.")
        }
        let token = try await CraftAccount.shared.token()
        guard let url = URL(string: "\(gamesCollection)/\(gameId)?updateMask.fieldPaths=removed&updateMask.fieldPaths=updatedAt") else {
            throw CraftError(message: "Invalid cloud URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let fields: [String: Any] = [
            "removed": encodeFirestoreValue(true),
            "updatedAt": encodeFirestoreValue(Date().timeIntervalSince1970)
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: ["fields": fields])
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"]
            throw CraftError(message: "Failed to remove game: \(detail ?? "")")
        }
    }
    
    static func playGame(gameId: String) async throws -> [String: Any] {
        guard let url = URL(string: "\(gamesCollection)/\(gameId)") else {
            throw CraftError(message: "Invalid game URL")
        }
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let doc = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let parsed = parseFirestoreDoc(doc),
              let link = parsed["url"] as? String else {
            throw CraftError(message: "Game link is unavailable.")
        }
        return ["url": link]
    }
}
