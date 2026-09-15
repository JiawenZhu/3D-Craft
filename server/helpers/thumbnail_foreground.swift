import Foundation
import Vision
import CoreImage
import ImageIO

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


// Local macOS display helper. It never writes to the reconstruction source.
if CommandLine.arguments.count != 3 { exit(2) }
do {
    let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
    let result = try CraftForegroundProcessor.foregroundPNG(from: data)
    try result.write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic)
} catch {
    fputs("Foreground extraction unavailable\n", stderr)
    exit(1)
}
