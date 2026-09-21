import Foundation
import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Widget style corresponding to the three circled icons in the iOS widget menu:
/// - `.small`: 2x2 square desk pet & avatar loop (Circled Icon 2)
/// - `.large`: 4x4 grand 3D showcase with stats & shortcuts (Circled Icon 4)
/// - `.medium`: 4x2 wide card with character on left & model specs on right (Circled Icon 5)
public enum CraftGadgetStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case small
    case medium
    case large

    public var id: String { rawValue }

    public func title(chinese: Bool) -> String {
        switch self {
        case .small:
            return chinese ? "桌面萌宠 (小组件)" : "Desk Companion (Small)"
        case .medium:
            return chinese ? "宽幅卡片 (中组件)" : "Studio Banner (Medium)"
        case .large:
            return chinese ? "全景展台 (大组件)" : "Grand Showcase (Large)"
        }
    }

    public func subtitle(chinese: Bool) -> String {
        switch self {
        case .small:
            return chinese ? "2x2 方块 · 纯粹角色动作特写" : "2x2 Square · Focused character action"
        case .medium:
            return chinese ? "4x2 宽幅 · 动画与模型参数双展" : "4x2 Wide · Animation & model specs"
        case .large:
            return chinese ? "4x4 大屏 · 沉浸式 3D 展台与快捷操作" : "4x4 Stage · Immersive studio & shortcuts"
        }
    }

    public var systemImage: String {
        switch self {
        case .small: return "square.inset.filled"
        case .medium: return "rectangle.inset.filled"
        case .large: return "square.split.2x2"
        }
    }
}

/// Metadata describing the active character animation displayed on the Home Screen widget.
public struct CraftGadgetData: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var modelName: String
    public var prompt: String
    public var loopDuration: String
    public var style: CraftGadgetStyle
    public var imageFileName: String?
    public var updatedAt: Date

    public init(
        id: String,
        name: String,
        modelName: String = "MiniMax Hailuo 02",
        prompt: String = "",
        loopDuration: String = "4s Loop",
        style: CraftGadgetStyle = .small,
        imageFileName: String? = nil,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.modelName = modelName
        self.prompt = prompt
        self.loopDuration = loopDuration
        self.style = style
        self.imageFileName = imageFileName
        self.updatedAt = updatedAt
    }

    public static var defaultDragon: CraftGadgetData {
        CraftGadgetData(
            id: "bundled-dragon",
            name: "Fire Dragon",
            modelName: "MiniMax Hailuo 02 (768p)",
            prompt: "A cute orange baby dragon breathing tiny glowing flames in a looping cycle",
            loopDuration: "4s Physics Loop",
            style: .small,
            imageFileName: "fire-dragon",
            updatedAt: .now
        )
    }
}

/// Central manager for desktop gadgets, syncing selection between the app and WidgetKit.
public final class CraftGadgetCenter: @unchecked Sendable {
    public static let shared = CraftGadgetCenter()

    private let storageKey = "craft_active_gadget_v1"
    private let appGroupName = "group.studio.craft.ios"

    private var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupName) ?? .standard
    }

    private init() {}

    /// Get current active gadget data, or fall back to default dragon mascot.
    public func activeGadget() -> CraftGadgetData {
        if let data = defaults.data(forKey: storageKey),
           let gadget = try? JSONDecoder().decode(CraftGadgetData.self, from: data) {
            return gadget
        }
        return .defaultDragon
    }

    /// Save the active gadget and notify WidgetKit to reload timelines.
    public func setActiveGadget(_ gadget: CraftGadgetData, image: UIImage? = nil) {
        var updated = gadget
        if let image {
            let fileName = "gadget_hero_\(gadget.id).png"
            if saveImageToDisk(image, fileName: fileName) {
                updated.imageFileName = fileName
            }
        }

        if let encoded = try? JSONEncoder().encode(updated) {
            defaults.set(encoded, forKey: storageKey)
        }

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// Load poster image from disk or bundle.
    public func loadHeroImage(for gadget: CraftGadgetData) -> UIImage? {
        if let fileName = gadget.imageFileName {
            // 1. Try file in container
            if let fileUrl = fileURL(for: fileName),
               let image = UIImage(contentsOfFile: fileUrl.path) {
                return image
            }
            // 2. Try named asset
            if let image = UIImage(named: fileName) {
                return image
            }
        }
        // Fallback to fire-dragon or mascot
        return UIImage(named: "fire-dragon") ?? UIImage(named: "mascot-dragon-model-1")
    }

    #if canImport(AVFoundation)
    /// Extract a crisp keyframe from the local video loop to use as the widget hero image.
    public func extractHeroKeyframe(from videoURL: URL) async -> UIImage? {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 800, height: 800)
        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        do {
            let (cgImage, _) = try await generator.image(at: time)
            return UIImage(cgImage: cgImage)
        } catch {
            return nil
        }
    }
    #endif

    // MARK: - Private File Helpers

    private func fileURL(for fileName: String) -> URL? {
        let folder: URL
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupName) {
            folder = container
        } else {
            folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        }
        return folder.appendingPathComponent(fileName)
    }

    private func saveImageToDisk(_ image: UIImage, fileName: String) -> Bool {
        guard let url = fileURL(for: fileName),
              let data = image.pngData() else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
