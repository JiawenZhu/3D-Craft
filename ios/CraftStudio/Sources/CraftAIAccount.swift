import Foundation

struct CraftPlannerModel: Identifiable, Equatable {
    let id: String
    let name: String
    let reasoningEfforts: [String]
    static let defaultID = "gemini-3.8-flash"
    static let defaultName = "Gemini 3.8 Flash"
    var fastEffort: String? {
        ["low", "none", "minimal"].first(where: reasoningEfforts.contains) ?? reasoningEfforts.first
    }
}

struct CraftAIAccount: Equatable {
    // Version 1 launches with Gemini; account-connected AI is deferred.
    static let enabledForRelease = false
    var available = false
    var connected = false
    var email: String?
    var models: [CraftPlannerModel] = []
    var pendingLoginID: String?
    var loginStatus: String?
    var imageGenerationSupported = false
    init() {}
    init(_ data: [String: Any]) {
        available = data["available"] as? Bool ?? false
        connected = data["connected"] as? Bool ?? false
        email = data["email"] as? String
        pendingLoginID = data["pendingLoginId"] as? String
        loginStatus = data["loginStatus"] as? String
        imageGenerationSupported = data["imageGenerationSupported"] as? Bool ?? false
        if connected {
            var seen = Set<String>()
            models = (data["models"] as? [[String: Any]] ?? []).compactMap { entry in
                guard let id = entry["id"] as? String, !id.isEmpty, seen.insert(id).inserted else { return nil }
                return CraftPlannerModel(id: id, name: entry["name"] as? String ?? id,
                    reasoningEfforts: entry["reasoningEfforts"] as? [String] ?? [])
            }
        }
    }
}

struct CraftAILogin: Identifiable {
    let id: String
    let verificationURL: URL
    let userCode: String
    let startedAt: Date
    var deadline: Date { startedAt.addingTimeInterval(300) }

    init?(_ data: [String: Any], now: Date = Date()) {
        guard let id = data["loginId"] as? String, !id.isEmpty,
              let code = data["userCode"] as? String, !code.isEmpty,
              let value = data["verificationUrl"] as? String,
              let url = URL(string: value), Self.isOfficialVerificationURL(url) else { return nil }
        self.id = id; verificationURL = url; userCode = code; startedAt = now
    }

    static func isOfficialVerificationURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              let host = url.host?.lowercased() else { return false }
        return host == "openai.com" || host.hasSuffix(".openai.com")
            || host == "chatgpt.com" || host.hasSuffix(".chatgpt.com")
    }
}
