import SwiftUI
import CryptoKit
import ImageIO

/// Decoded previews survive view recreation; disk previews survive app launches.
/// Generation always continues to use the untouched original URL.
final class CraftDecodedImages: @unchecked Sendable {
    static let shared = CraftDecodedImages()
    private let images = NSCache<NSString, UIImage>()
    init() { images.totalCostLimit = 64 * 1024 * 1024; images.countLimit = 100 }
    func image(_ key: String) -> UIImage? { images.object(forKey: key as NSString) }
    func insert(_ image: UIImage, key: String) {
        images.setObject(image, forKey: key as NSString, cost: Int(image.size.width * image.size.height * image.scale * image.scale * 4))
    }
}

actor CraftImageCache {
    static let shared = CraftImageCache()
    typealias Loader = @Sendable (URL) async throws -> Data
    private let folder: URL
    private let loader: Loader
    private var pending: [String: Task<Data?, Never>] = [:]
    init(folder: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("CraftImagePreviews-v1"), loader: @escaping Loader = { try await CraftImageCache.download($0) }) {
        self.folder = folder; self.loader = loader
    }
    static func download(_ url: URL) async throws -> Data {
        if url.isFileURL { return try Data(contentsOf: url) }
        let (data, response) = try await CraftCloudMedia.data(url)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw URLError(.badServerResponse) }
        return data
    }
    func data(for url: URL) async -> Data? {
        let key = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        if let task = pending[key] { return await task.value }
        let folder = folder, loader = loader
        // Detached from the view task: switching a tab must not discard a download.
        let task = Task.detached(priority: .utility) { () -> Data? in
            let file = folder.appendingPathComponent(key)
            if let data = try? Data(contentsOf: file), UIImage(data: data) != nil {
                try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
                return data
            }
            guard let original = try? await loader(url),
                  let source = CGImageSourceCreateWithData(original as CFData, nil),
                  let preview = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1024
                  ] as CFDictionary), let data = UIImage(cgImage: preview).pngData() else { return nil }
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
            Self.trim(folder)
            return data
        }
        pending[key] = task
        let result = await task.value
        pending[key] = nil
        return result
    }
    private static func trim(_ folder: URL) {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? []
        let entries = files.compactMap { url -> (URL, Int, Date)? in
            guard let v = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
            return (url, v.fileSize ?? 0, v.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var size = entries.reduce(0) { $0 + $1.1 }
        for entry in entries where size > 256 * 1024 * 1024 {
            try? FileManager.default.removeItem(at: entry.0); size -= entry.1
        }
    }
}

struct CraftCachedImage: View {
    let url: URL?
    var contentMode: ContentMode = .fit
    @State private var image: UIImage?
    @State private var failed = false
    init(url: URL?, contentMode: ContentMode = .fit) {
        self.url = url; self.contentMode = contentMode
        _image = State(initialValue: url.flatMap { CraftDecodedImages.shared.image($0.absoluteString) })
    }
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode) }
            else if failed { Image(systemName: "photo").foregroundStyle(.secondary) }
            else { ProgressView() }
        }
        .task(id: url) {
            guard let url else { failed = true; return }
            if let cached = CraftDecodedImages.shared.image(url.absoluteString) { image = cached; return }
            image = nil; failed = false
            let data = await CraftImageCache.shared.data(for: url)
            let decoded = data.flatMap { UIImage(data: $0) }
            if let decoded { CraftDecodedImages.shared.insert(decoded, key: url.absoluteString) }
            guard !Task.isCancelled else { return }
            image = decoded; failed = decoded == nil
        }
    }
}
