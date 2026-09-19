import Foundation

/// The website and iOS read this same owner-only Firebase collection.
enum FirebaseCreationLibrary {
    static let project = "forma-studio-2026"
    static let bucket = "forma-studio-2026.firebasestorage.app"

    static func mediaURL(path: String, uid: String) -> URL? {
        guard path.hasPrefix("users/\(uid)/"), !path.contains(".."),
              let encoded = path.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return nil }
        return URL(string: "https://firebasestorage.googleapis.com/v0/b/\(bucket)/o/\(encoded)?alt=media")
    }

    static func value(_ field: [String: Any]) -> Any? {
        if let text = field["stringValue"] as? String { return text }
        if let number = field["doubleValue"] as? NSNumber { return number }
        if let number = field["integerValue"] as? String { return Double(number) }
        if let flag = field["booleanValue"] as? Bool { return flag }
        return nil
    }

    @MainActor static func load() async throws -> [CraftAsset] {
        guard let uid = CraftAccount.shared.uid,
              let encodedUID = uid.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { throw URLError(.userAuthenticationRequired) }
        let token = try await CraftAccount.shared.token()
        var records: [CraftAsset] = []
        var pageToken: String?
        repeat {
            var components = URLComponents(string: "https://firestore.googleapis.com/v1/projects/\(project)/databases/(default)/documents/users/\(encodedUID)/mobileCreations")!
            components.queryItems = [URLQueryItem(name: "pageSize", value: "100")]
            if let pageToken { components.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData)
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 30
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw URLError(.badServerResponse) }
            for doc in result["documents"] as? [[String: Any]] ?? [] {
                let fields = doc["fields"] as? [String: [String: Any]] ?? [:]
                let d = fields.compactMapValues(value)
                // 3D objects and animated characters are the library; concept
                // images live in their projects instead.
                let kind = d["kind"] as? String
                guard d["ownerId"] as? String == uid, kind == "3D object" || kind == "Animated character",
                      let name = doc["name"] as? String, let ident = name.split(separator: "/").last else { continue }
                let animated = kind == "Animated character"
                let imagePath = d["previewStoragePath"] as? String ?? ""
                let modelPath = d["modelStoragePath"] as? String ?? ""
                var preview = mediaURL(path: imagePath, uid: uid)?.absoluteString
                // Legacy Firebase documents carry their preview inline. Keep them readable.
                if preview == nil, let inline = d["preview"] as? String, inline.hasPrefix("data:image/") { preview = inline }
                let id = String(ident).replacingOccurrences(of: animated ? "animation:" : "model:", with: "", options: .anchored)
                var asset = CraftAsset(id: id, name: d["name"] as? String ?? "Untitled creation",
                    modelUrl: animated ? nil : mediaURL(path: modelPath, uid: uid)?.absoluteString, thumbUrl: preview)
                if animated { asset.animationUrl = mediaURL(path: d["animationStoragePath"] as? String ?? "", uid: uid)?.absoluteString }
                records.append(asset)
            }
            pageToken = result["nextPageToken"] as? String
        } while pageToken?.isEmpty == false
        guard CraftAccount.shared.uid == uid else { throw URLError(.cancelled) }
        return records
    }
}

/// Attach identity only to this project's private Storage, never third-party URLs.
enum CraftCloudMedia {
    @MainActor static func request(_ url: URL) async throws -> URLRequest {
        var request = URLRequest(url: url)
        if url.host == "firebasestorage.googleapis.com" {
            guard url.scheme == "https", let uid = CraftAccount.shared.uid,
                  url.path.hasPrefix("/v0/b/\(FirebaseCreationLibrary.bucket)/o/users/\(uid)/") else { throw URLError(.noPermissionsToReadFile) }
            request.setValue("Firebase " + (try await CraftAccount.shared.token()), forHTTPHeaderField: "Authorization")
        }
        return request
    }
    static func data(_ url: URL) async throws -> (Data, URLResponse) {
        if url.scheme == "data", let comma = url.absoluteString.firstIndex(of: ","),
           let bytes = Data(base64Encoded: String(url.absoluteString[url.absoluteString.index(after: comma)...])) {
            return (bytes, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        return try await URLSession.shared.data(for: request(url))
    }
}
