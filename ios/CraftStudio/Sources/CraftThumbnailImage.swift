import SwiftUI
import Vision
import CoreImage
import ImageIO
import CryptoKit

/// Display-only subject extraction. Source images used for generation and
/// export remain byte-for-byte unchanged. Semantic masks retain dark details.
enum CraftForegroundProcessor {
    enum ExtractionError: Error { case invalidImage, noSubject, renderFailed }

    static func foregroundPNG(from data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 640
              ] as CFDictionary) else { throw ExtractionError.invalidImage }

        if hasTransparency(image) { return try png(image) }
        let request = VNGenerateForegroundInstanceMaskRequest()
        request.preferBackgroundProcessing = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            throw ExtractionError.noSubject
        }
        let buffer = try observation.generateMaskedImage(ofInstances: observation.allInstances,
            from: handler, croppedToInstancesExtent: false)
        let ciImage = CIImage(cvPixelBuffer: buffer)
        guard let result = CIContext(options: [.cacheIntermediates: false])
            .createCGImage(ciImage, from: ciImage.extent), hasTransparency(result) else {
            throw ExtractionError.renderFailed
        }
        return try png(result)
    }

    static func hasTransparency(_ image: CGImage) -> Bool {
        // Alpha inspection only decides whether segmentation is needed. It
        // never classifies foreground by brightness or changes RGB values.
        var pixels = [UInt8](repeating: 0, count: 32 * 32 * 4)
        guard let context = CGContext(data: &pixels, width: 32, height: 32,
            bitsPerComponent: 8, bytesPerRow: 32 * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 32))
        return stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] < 240 }
    }

    private static func png(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
            throw ExtractionError.renderFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ExtractionError.renderFailed }
        return data as Data
    }
}

/// Serializes Vision work away from the main actor and caches transparent
/// results independently of the chosen theme, so switching colors is instant.
actor CraftThumbnailCache {
    static let shared = CraftThumbnailCache()
    private var memory: [String: Data] = [:]
    private var pending: [String: Task<Data?, Never>] = [:]
    private var generation = 0
    private var erasing = false
    private let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("CraftThumbnailCutouts-v1", isDirectory: true)

    func erase() async {
        erasing = true; generation += 1
        let tasks = Array(pending.values)
        tasks.forEach { $0.cancel() }
        for task in tasks { _ = await task.value }
        pending.removeAll(); memory.removeAll()
        try? FileManager.default.removeItem(at: folder)
        erasing = false
    }
    func imageData(for url: URL) async -> Data? {
        guard !erasing else { return nil }
        let version = generation
        let key = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        if let data = memory[key] { return data }
        let file = folder.appendingPathComponent(key).appendingPathExtension("png")
        if let data = try? Data(contentsOf: file) { remember(data, key: key); return data }
        if let task = pending[key] {
            let result = await task.value
            return version == generation ? result : nil
        }
        let folder = folder
        let task = Task.detached(priority: .utility) { () -> Data? in
        do {
            let data: Data
            if url.isFileURL { data = try Data(contentsOf: url) }
            else {
                let (received, response) = try await CraftCloudMedia.data(url)
                guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { return nil }
                data = received
            }
            if let cutout = try? CraftForegroundProcessor.foregroundPNG(from: data) {
                guard !Task.isCancelled else { return nil }
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try? cutout.write(to: file, options: .atomic)
                return cutout
            }
            // Some images/devices do not yield a reliable foreground mask.
            // Keep their source intact rather than erase subject details.
            guard !Task.isCancelled else { return nil }
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
            return data
        } catch { return nil }
        }
        pending[key] = task
        let data = await task.value
        guard version == generation else { return nil }
        pending[key] = nil
        if let data { remember(data, key: key) }
        return data
    }

    private func remember(_ data: Data, key: String) {
        if memory.count >= 60, let oldest = memory.keys.first { memory.removeValue(forKey: oldest) }
        memory[key] = data
    }
}

struct CraftThumbnailImage: View {
    let url: URL?
    var inset: CGFloat = 8
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    @State private var image: UIImage?
    @State private var loaded = false

    init(url: URL?, inset: CGFloat = 8) {
        self.url = url; self.inset = inset
        _image = State(initialValue: url.flatMap { CraftDecodedImages.shared.image("cutout:" + $0.absoluteString) })
    }
    var body: some View {
        ZStack {
            appearance.washSoft
            if let image {
                Image(uiImage: image).resizable().scaledToFit().padding(inset)
                    .accessibilityIdentifier("thumbnail.subject")
            } else if loaded {
                Image(systemName: "cube.transparent").font(.title).foregroundStyle(.secondary)
            } else {
                ProgressView().tint(appearance.ink)
            }
        }
        .task(id: url) {
            if let url, let cached = CraftDecodedImages.shared.image("cutout:" + url.absoluteString) { image = cached; loaded = true; return }
            image = nil; loaded = false
            if let url, let data = await CraftThumbnailCache.shared.imageData(for: url), !Task.isCancelled {
                image = UIImage(data: data)
                if let image { CraftDecodedImages.shared.insert(image, key: "cutout:" + url.absoluteString) }
            }
            guard !Task.isCancelled else { return }
            loaded = true
        }
    }
}
