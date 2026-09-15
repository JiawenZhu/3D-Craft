import Foundation

/// A callback is valid only for the active system authentication session.
struct CraftWebAuthAttempt {
    let state: String
    let createdAt: Date
    init(state: String = UUID().uuidString + UUID().uuidString, createdAt: Date = Date()) {
        self.state = state; self.createdAt = createdAt
    }
    var url: URL {
        var components = URLComponents(string: "https://3d-craft.web.app/auth/ios")!
        components.queryItems = [URLQueryItem(name: "state", value: state)]
        return components.url!
    }
    struct Credentials { let uid: String; let token: String; let refresh: String }
    func credentials(from url: URL, now: Date = Date()) -> Credentials? {
        guard now >= createdAt, now.timeIntervalSince(createdAt) < 600,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "studio.craft.ios", parts.host == "auth",
              parts.path.isEmpty, parts.fragment == nil, parts.user == nil, parts.port == nil,
              let items = parts.queryItems else { return nil }
        func value(_ name: String) -> String? {
            let matches = items.filter { $0.name == name }
            guard matches.count == 1, let value = matches[0].value, !value.isEmpty else { return nil }
            return value
        }
        guard value("state") == state, let uid = value("uid"), let token = value("token"),
              let refresh = value("refresh") else { return nil }
        return Credentials(uid: uid, token: token, refresh: refresh)
    }
}
