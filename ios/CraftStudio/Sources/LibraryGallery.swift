import SwiftUI

enum LibraryGalleryFilter: String, CaseIterable, Identifiable {
    case all, concepts, models, animations, favorites, archive
    var id: String { rawValue }
    func title(chinese: Bool) -> String {
        switch self {
        case .all: return chinese ? "全部" : "All"
        case .concepts: return chinese ? "概念图" : "Concepts"
        case .models: return chinese ? "3D 模型" : "3D models"
        case .animations: return chinese ? "动画" : "Animations"
        case .favorites: return chinese ? "收藏" : "Favorites"
        case .archive: return chinese ? "归档" : "Archive"
        }
    }
}

enum LibraryGalleryItem: Identifiable {
    case project(CraftProject, imageURL: URL?, active: Bool)
    case asset(CraftAsset, favorite: Bool)

    var id: String {
        switch self {
        case .project(let project, _, _): return "project:" + project.id
        case .asset(let asset, _): return "asset:" + asset.id
        }
    }
    var name: String {
        switch self {
        case .project(let project, _, _): return project.name
        case .asset(let asset, _): return asset.name
        }
    }
    var accessibilityID: String {
        switch self {
        case .project(let project, _, _): return "library.project." + project.id
        case .asset(let asset, _): return "asset." + asset.id
        }
    }
    var isArchived: Bool {
        switch self {
        case .project(let project, _, _): return project.isArchived
        case .asset(let asset, _): return asset.isArchived
        }
    }
    var daysRemaining: Int {
        switch self {
        case .project(let project, _, _): return project.daysRemaining
        case .asset(let asset, _): return asset.daysRemaining
        }
    }
    func caption(chinese: Bool) -> String {
        if isArchived {
            return chinese ? "剩余 \(daysRemaining) 天" : "\(daysRemaining)d left"
        }
        switch self {
        case .project(let project, _, let active):
            if active { return chinese ? "正在生成" : "Creating" }
            let count = project.concepts.filter { $0.isOriginal != true }.count
            if count == 0 {
                let hasChat = !project.turns.isEmpty
                return hasChat ? (chinese ? "未完成对话" : "Chat Draft") : (chinese ? "创作项目" : "Concept project")
            }
            return (chinese ? "\(count) 张概念图" : "\(count) " + (count == 1 ? "concept" : "concepts"))
        case .asset(let asset, _):
            if asset.isAnimated { return chinese ? "动画" : "Animation" }
            if asset.isConcept { return chinese ? "概念图" : "Concept" }
            return chinese ? "3D 模型" : "3D model"
        }
    }
}

struct LibraryGallery: View {
    let items: [LibraryGalleryItem]
    let chinese: Bool
    var onModify: ((LibraryGalleryItem) -> Void)? = nil
    var onArchive: ((LibraryGalleryItem) -> Void)? = nil
    var onRestore: ((LibraryGalleryItem) -> Void)? = nil
    var onDeletePermanently: ((LibraryGalleryItem) -> Void)? = nil
    let onSelect: (LibraryGalleryItem) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            column(0)
            column(1)
        }
    }

    private func column(_ parity: Int) -> some View {
        LazyVStack(spacing: 16) {
            ForEach(Array(items.enumerated()).filter { $0.offset % 2 == parity }, id: \.element.id) { index, item in
                Button { onSelect(item) } label: {
                    LibraryGalleryCard(item: item, chinese: chinese, aspect: [0.88, 1.10, 1.04, 0.86][index % 4])
                }
                .buttonStyle(CraftPressStyle(scale: 0.975))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(item.name + ", " + item.caption(chinese: chinese))
                .accessibilityHint(chinese ? "打开作品" : "Open your creation")
                .accessibilityIdentifier(item.accessibilityID)
                .contextMenu {
                    if item.isArchived {
                        Button {
                            onRestore?(item)
                        } label: {
                            Label(chinese ? "恢复" : "Restore", systemImage: "arrow.uturn.backward")
                        }
                        Button(role: .destructive) {
                            onDeletePermanently?(item)
                        } label: {
                            Label(chinese ? "彻底删除" : "Delete permanently", systemImage: "trash")
                        }
                    } else {
                        Button {
                            onModify?(item)
                        } label: {
                            Label(chinese ? "修改" : "Modify", systemImage: "sparkles")
                        }
                        Button(role: .destructive) {
                            onArchive?(item)
                        } label: {
                            Label(chinese ? "归档" : "Archive", systemImage: "archivebox")
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct LibraryGalleryCard: View {
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    let item: LibraryGalleryItem
    let chinese: Bool
    let aspect: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Rectangle()
                .fill(appearance.washSoft.gradient)
                .aspectRatio(aspect, contentMode: .fit)
                .overlay {
                    GeometryReader { bounds in
                        artwork.frame(width: bounds.size.width, height: bounds.size.height)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    HStack(spacing: 4) {
                        switch item {
                        case .asset(let asset, _):
                            Image(systemName: asset.isAnimated ? "film.fill" : (asset.isConcept ? "photo.fill" : "cube.fill"))
                                .font(.system(size: 8))
                        case .project(let project, _, _):
                            let hasConcepts = project.concepts.contains(where: { $0.isOriginal != true })
                            Image(systemName: hasConcepts ? "folder.fill" : "bubble.left.and.bubble.right.fill")
                                .font(.system(size: 8))
                        }
                        Text(item.caption(chinese: chinese))
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(appearance.ink)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(.regularMaterial, in: Capsule())
                    .padding(8)
                }
                .overlay(alignment: .topTrailing) {
                    if item.isArchived {
                        Text(chinese ? "剩余 \(item.daysRemaining) 天" : "\(item.daysRemaining)d left")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.88), in: Capsule())
                            .padding(6)
                    } else {
                        switch item {
                        case .asset(_, let favorite) where favorite:
                            Image(systemName: "heart.fill")
                                .font(.caption).foregroundStyle(appearance.ink)
                                .padding(8).background(.regularMaterial, in: Circle()).padding(8)
                        case .project(_, _, let active) where active:
                            ProgressView().tint(appearance.ink)
                                .padding(8).background(.regularMaterial, in: Circle()).padding(8)
                        default: EmptyView()
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(appearance.fill.opacity(0.10)))
            Text(item.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 3)
        }
    }

    @ViewBuilder private var artwork: some View {
        switch item {
        case .asset(let asset, _):
            CraftThumbnailImage(url: asset.thumbURL ?? asset.sourceImageURL, inset: 7)
        case .project(let project, let url, _):
            if let url {
                CraftCachedImage(url: url).padding(6)
            } else {
                let hasChat = !project.turns.isEmpty
                placeholder(hasChat ? "bubble.left.and.bubble.right" : "sparkles.rectangle.stack")
            }
        }
    }

    private func placeholder(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 34, weight: .light))
            .foregroundStyle(appearance.ink.opacity(0.55))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

