import SwiftUI

/// A device-local identity, independent of studio credentials and generation data.
struct CraftProfileRecord: Codable, Equatable {
    var displayName = ""
    var avatarData: Data?
    var avatarAssetID: String?
}

@MainActor final class CraftProfile: ObservableObject {
    static let shared = CraftProfile()
    @Published private(set) var record: CraftProfileRecord
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CraftStudio", isDirectory: true).appendingPathComponent("profile.json")
        if let data = try? Data(contentsOf: self.fileURL),
           var saved = try? JSONDecoder().decode(CraftProfileRecord.self, from: data) {
            if let avatar = saved.avatarData, UIImage(data: avatar) == nil {
                saved.avatarData = nil
                saved.avatarAssetID = nil
            }
            record = saved
        } else {
            record = CraftProfileRecord()
        }
    }

    var avatar: UIImage? { record.avatarData.flatMap { UIImage(data: $0) } }
    func displayName(chinese: Bool) -> String {
        record.displayName.isEmpty ? (chinese ? "我的工作室" : "My studio") : record.displayName
    }

    func save(name: String, avatar: UIImage?, assetID: String?) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 32, !trimmed.contains(where: \.isNewline) else {
            throw ProfileError.invalidName
        }
        let avatarData: Data?
        if let avatar {
            guard avatar.size.width > 0, avatar.size.height > 0 else { throw ProfileError.invalidImage }
            // Normalize orientation and keep a bounded, offline-ready image.
            let scale = min(1, 768 / max(avatar.size.width, avatar.size.height))
            let size = CGSize(width: avatar.size.width * scale, height: avatar.size.height * scale)
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                avatar.draw(in: CGRect(origin: .zero, size: size))
            }
            // Generated-asset portraits carry a semantic alpha mask. JPEG
            // would bake that transparent area back into a black rectangle.
            let encoded = assetID == nil ? image.jpegData(compressionQuality: 0.88) : image.pngData()
            guard let encoded else { throw ProfileError.invalidImage }
            avatarData = encoded
        } else { avatarData = nil }
        let updated = CraftProfileRecord(displayName: trimmed, avatarData: avatarData,
                                         avatarAssetID: avatarData == nil ? nil : assetID)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(updated).write(to: fileURL, options: .atomic)
        record = updated
    }

    enum ProfileError: Error { case invalidName, invalidImage }
}
