import SwiftUI

enum GalleryHomeCategory: String, CaseIterable, Identifiable {
    case characters, objects
    case userCreated = "user-created"
    var id: String { rawValue }
    func title(chinese: Bool) -> String {
        switch self {
        case .userCreated: return chinese ? "我的创作" : "User created"
        case .characters: return chinese ? "角色" : "Characters"
        case .objects: return chinese ? "物件" : "Objects"
        }
    }
    func includes(_ asset: CraftAsset) -> Bool {
        if asset.isArchived { return false }
        let character = ["character", "flying", "creature", "animal", "humanoid", "animated character"].contains(asset.kind.lowercased())
        return self == .userCreated || (self == .characters ? character : !character)
    }
    /// Public discovery and the owner's creations are distinct sources. Legacy
    /// uncurated examples must never leak into the public category tabs.
    func assets(owned: [CraftAsset], examples: [CraftAsset]) -> [CraftAsset] {
        let source: [CraftAsset]
        if self == .userCreated {
            source = owned.filter { !$0.isExample && $0.galleryExample != true && !$0.isArchived }
        } else {
            let curated = examples.filter { $0.galleryExample == true }
            source = curated.isEmpty ? examples.filter { $0.id == "bundled-lantern" } : curated
        }
        var seen = Set<String>()
        return source.filter { seen.insert($0.id).inserted && includes($0) }
    }

    static func label(for asset: CraftAsset, chinese: Bool) -> String {
        if asset.isAnimated {
            return chinese ? "动画" : "Animation"
        }
        if asset.isConcept {
            return chinese ? "概念图" : "Concept"
        }
        switch asset.kind.lowercased() {
        case "vehicle", "car": return chinese ? "载具" : "Vehicle"
        case "world", "environment", "scene", "building": return chinese ? "场景" : "World"
        case "character", "flying", "creature", "animal", "humanoid": return chinese ? "角色" : "Character"
        default: return chinese ? "3D 模型" : "3D model"
        }
    }
}

/// Two independent columns keep the artwork's staggered rhythm without a
/// nested scroll view. Every card still opens its real underlying asset.
struct GalleryHomeGrid: View {
    let assets: [CraftAsset]
    let chinese: Bool
    var isFavorite: ((CraftAsset) -> Bool)? = nil
    var onModify: ((CraftAsset) -> Void)? = nil
    var onFavorite: ((CraftAsset) -> Void)? = nil
    var onUnfavorite: ((CraftAsset) -> Void)? = nil
    var onArchive: ((CraftAsset) -> Void)? = nil
    let onSelect: (CraftAsset) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            column(parity: 0)
            column(parity: 1)
        }
    }

    private func column(parity: Int) -> some View {
        LazyVStack(spacing: 10) {
            ForEach(Array(assets.enumerated()).filter { $0.offset % 2 == parity }, id: \.element.id) { index, asset in
                Button { onSelect(asset) } label: {
                    GalleryHomeTile(asset: asset, chinese: chinese, isFavorite: isFavorite?(asset) ?? false, aspect: aspect(index: index, asset: asset))
                }
                .buttonStyle(CraftPressStyle(scale: 0.97))
                .accessibilityLabel(asset.name + ", " + GalleryHomeCategory.label(for: asset, chinese: chinese))
                .accessibilityHint(chinese ? "打开 3D 工作室" : "Open in the 3D studio")
                .accessibilityIdentifier("creation.asset." + asset.id)
                .contextMenu {
                    if !asset.isExample {
                        if isFavorite?(asset) == true {
                            Button {
                                onUnfavorite?(asset)
                            } label: {
                                Label(chinese ? "移出收藏" : "Remove from Favorites", systemImage: "heart.slash")
                            }
                        } else {
                            Button {
                                onFavorite?(asset)
                            } label: {
                                Label(chinese ? "加入收藏" : "Add to Favorites", systemImage: "heart")
                            }
                        }
                        Button {
                            onModify?(asset)
                        } label: {
                            Label(chinese ? "修改" : "Modify", systemImage: "sparkles")
                        }
                        Button(role: .destructive) {
                            onArchive?(asset)
                        } label: {
                            Label(chinese ? "归档" : "Archive", systemImage: "archivebox")
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func aspect(index: Int, asset: CraftAsset) -> CGFloat {
        // Keep broad vehicles and worlds broad even when filtering moves them
        // into the first slot; standing characters retain their full silhouette.
        switch asset.kind.lowercased() {
        case "vehicle", "car": return 1.25
        case "world", "environment", "scene", "building": return index.isMultiple(of: 2) ? 1.08 : 0.96
        default: return index.isMultiple(of: 2) ? 0.82 : 1.02
        }
    }
}

private struct GalleryHomeTile: View {
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    let asset: CraftAsset
    let chinese: Bool
    var isFavorite: Bool = false
    let aspect: CGFloat

    private var artworkURL: URL? {
        // Curated examples can include an intentional illustrated setting.
        // User asset thumbnails retain the existing transparent display path.
        asset.isExample ? (asset.sourceImageURL ?? asset.thumbUrl.flatMap(URL.init(string:)) ?? asset.thumbURL) : (asset.thumbURL ?? asset.sourceImageURL)
    }

    var body: some View {
        Rectangle()
            .fill(appearance.washSoft.gradient)
            .aspectRatio(aspect, contentMode: .fit)
            .overlay {
                GeometryReader { bounds in
                    if asset.isExample && artworkURL?.isFileURL != true {
                        CraftCachedImage(url: artworkURL, contentMode: .fill)
                        .frame(width: bounds.size.width, height: bounds.size.height)
                        .clipped()
                    } else {
                        CraftThumbnailImage(url: artworkURL, inset: 4)
                            .frame(width: bounds.size.width, height: bounds.size.height)
                    }
                }
            }
            .overlay(alignment: asset.kind == "vehicle" ? .bottomTrailing : .bottomLeading) {
                HStack(spacing: 4) {
                    if asset.isAnimated {
                        Image(systemName: "film.fill").font(.system(size: 8))
                    } else if asset.isConcept {
                        Image(systemName: "photo.fill").font(.system(size: 8))
                    }
                    Text(GalleryHomeCategory.label(for: asset, chinese: chinese))
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(appearance.ink)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(.regularMaterial, in: Capsule())
                .padding(8)
            }
            .overlay(alignment: .topTrailing) {
                if asset.isArchived {
                    Text(chinese ? "剩余 \(asset.daysRemaining) 天" : "\(asset.daysRemaining)d left")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.88), in: Capsule())
                        .padding(6)
                } else if isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.pink)
                        .padding(6)
                        .background(.regularMaterial, in: Circle())
                        .padding(6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(appearance.fill.opacity(0.10)))
            .accessibilityElement(children: .ignore)
    }

    private var fallback: some View {
        VStack(spacing: 8) {
            Image(systemName: "cube.transparent").font(.title)
            Text(asset.name).font(.caption).multilineTextAlignment(.center).lineLimit(3)
        }
        .foregroundStyle(appearance.ink)
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

