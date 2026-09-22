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

    private static func parseDoc(_ doc: [String: Any], uid: String, token: String) -> CraftAsset? {
        let fields = doc["fields"] as? [String: [String: Any]] ?? [:]
        let d = fields.compactMapValues(value)
        guard d["ownerId"] as? String == uid,
              let docName = doc["name"] as? String,
              let ident = docName.split(separator: "/").last else { return nil }
        let kind = d["kind"] as? String ?? "3D object"
        guard kind == "3D object" || kind == "Animated character" || kind == "Concept image" else { return nil }

        let animated = (kind == "Animated character")
        let isConcept = (kind == "Concept image")
        let imagePath = d["previewStoragePath"] as? String ?? ""
        let modelPath = d["modelStoragePath"] as? String ?? ""
        let sourcePath = d["sourceImageStoragePath"] as? String ?? imagePath
        var preview = mediaURL(path: imagePath, uid: uid)?.absoluteString
        if preview == nil, let inline = d["preview"] as? String, inline.hasPrefix("data:image/") { preview = inline }
        let sourceImg = mediaURL(path: sourcePath, uid: uid)?.absoluteString ?? preview

        var id = String(ident)
        if id.hasPrefix("model:") { id.removeFirst("model:".count) }
        else if id.hasPrefix("animation:") { id.removeFirst("animation:".count) }
        else if id.hasPrefix("concept:") { id.removeFirst("concept:".count) }

        let archivedAt = (d["archivedAt"] as? NSNumber)?.doubleValue ?? (d["archivedAt"] as? Double)
        let now = Date().timeIntervalSince1970
        if let archivedAt, (now - archivedAt) >= (30 * 86400) {
            // Automatically purge expired document after 30 days
            Task {
                try? await deleteDocByName(docName, token: token)
            }
            return nil
        }

        let asset = CraftAsset(
            id: id,
            name: d["name"] as? String ?? (isConcept ? "Concept image" : "Untitled creation"),
            modelUrl: (animated || isConcept) ? nil : mediaURL(path: modelPath, uid: uid)?.absoluteString,
            thumbUrl: preview,
            kind: isConcept ? "concept" : (animated ? "character" : (d["kind"] as? String ?? "character")),
            isExample: false,
            animationUrl: animated ? mediaURL(path: d["animationStoragePath"] as? String ?? "", uid: uid)?.absoluteString : nil,
            sourceImageUrl: sourceImg,
            projectId: d["projectId"] as? String,
            prompt: d["prompt"] as? String,
            archivedAt: archivedAt,
            creationKind: kind,
            firestoreDocName: docName
        )
        return asset
    }

    @MainActor private static func fetchAllDocs() async throws -> ([CraftAsset], String) {
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
                if let asset = parseDoc(doc, uid: uid, token: token) {
                    records.append(asset)
                }
            }
            pageToken = result["nextPageToken"] as? String
        } while pageToken?.isEmpty == false
        guard CraftAccount.shared.uid == uid else { throw URLError(.cancelled) }
        return (records, token)
    }

    @MainActor static func load() async throws -> [CraftAsset] {
        let (records, _) = try await fetchAllDocs()
        return records.filter { !$0.isArchived }
    }

    @MainActor static func loadArchived() async throws -> [CraftAsset] {
        let (records, _) = try await fetchAllDocs()
        return records.filter { $0.isArchived }
    }

    @MainActor static func archive(asset: CraftAsset) async throws {
        guard let uid = CraftAccount.shared.uid,
              let encodedUID = uid.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
              var components = URLComponents(url: resolveDocURL(asset: asset, uid: encodedUID), resolvingAgainstBaseURL: false) else { throw URLError(.userAuthenticationRequired) }
        components.queryItems = [URLQueryItem(name: "updateMask.fieldPaths", value: "archivedAt")]
        guard let url = components.url else { throw URLError(.badURL) }
        let token = try await CraftAccount.shared.token()
        let now = Date().timeIntervalSince1970
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["fields": ["archivedAt": ["doubleValue": now]]]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    @MainActor static func restore(asset: CraftAsset) async throws {
        guard let uid = CraftAccount.shared.uid,
              let encodedUID = uid.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
              var components = URLComponents(url: resolveDocURL(asset: asset, uid: encodedUID), resolvingAgainstBaseURL: false) else { throw URLError(.userAuthenticationRequired) }
        components.queryItems = [URLQueryItem(name: "updateMask.fieldPaths", value: "archivedAt")]
        guard let url = components.url else { throw URLError(.badURL) }
        let token = try await CraftAccount.shared.token()
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["fields": [:]]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    @MainActor static func deletePermanently(asset: CraftAsset) async throws {
        guard let uid = CraftAccount.shared.uid,
              let encodedUID = uid.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { throw URLError(.userAuthenticationRequired) }
        let url = resolveDocURL(asset: asset, uid: encodedUID)
        let token = try await CraftAccount.shared.token()
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) || http.statusCode == 404 else {
            throw URLError(.badServerResponse)
        }
    }

    private static func deleteDocByName(_ docPath: String, token: String) async throws {
        let cleanPath = docPath.hasPrefix("projects/") ? docPath : "projects/\(project)/databases/(default)/documents/\(docPath)"
        guard let url = URL(string: "https://firestore.googleapis.com/v1/\(cleanPath)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) || http.statusCode == 404 else {
            throw URLError(.badServerResponse)
        }
    }

    private static func resolveDocURL(asset: CraftAsset, uid: String) -> URL {
        let prefix = asset.isAnimated ? "animation:" : (asset.isConcept ? "concept:" : "model:")
        let rawId: String
        if let docName = asset.firestoreDocName, let last = docName.split(separator: "/").last {
            rawId = String(last)
        } else {
            rawId = prefix + asset.id
        }
        let docId = rawId.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? rawId
        return URL(string: "https://firestore.googleapis.com/v1/projects/\(project)/databases/(default)/documents/users/\(uid)/mobileCreations/\(docId)")!
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
