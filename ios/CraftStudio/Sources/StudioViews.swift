import SwiftUI
import RevenueCatUI

// MARK: - Thumbnail

struct AssetThumbnail: View {
    let asset: CraftAsset
    var height: CGFloat = 150
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender

    var body: some View {
        CraftThumbnailImage(url: asset.thumbURL)
        .frame(maxWidth: .infinity).frame(height: height)
        .background(appearance.washSoft)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Library

struct LibraryView: View {
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    @EnvironmentObject var store: CraftStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searching: Bool
    @AppStorage("craftFavorites") private var favoriteIDs = ""
    @State private var query = ""
    @State private var filter: LibraryGalleryFilter = .all
    @State private var alphabetical = false
    @State private var filterCount = 0
    @State private var openCount = 0

    private var favorites: Set<String> { Set(favoriteIDs.split(separator: ",").map(String.init)) }
    private var searchText: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var privateAssets: [CraftAsset] {
        // A published sample may also have appeared in an older owned response.
        // Only the user's private collection belongs on this screen.
        store.assets.filter { !$0.isExample && $0.galleryExample != true }
    }
    private var items: [LibraryGalleryItem] {
        if filter == .archive {
            let archivedA = store.archivedAssets.map { LibraryGalleryItem.asset($0, favorite: false) }
            let archivedP = store.archivedProjects.map { project -> LibraryGalleryItem in
                let concept = store.selectedConcept(in: project)
                    ?? project.concepts.first(where: { $0.isOriginal != true })
                    ?? project.concepts.first
                let url = (concept?.imageUrl ?? project.imageUrl).flatMap(URL.init(string:))
                return .project(project, imageURL: url, active: false)
            }
            let archived = archivedA + archivedP
            let matching = archived.filter {
                searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText)
            }
            return alphabetical ? matching.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } : matching
        }
        let activeProjects = Set(store.jobs.filter(\.isActive).map(\.projectId))
        let archivedProjectIDs = Set(store.archivedProjects.map(\.id))
        let projects: [LibraryGalleryItem] = (filter == .models || filter == .animations || filter == .favorites) ? [] : store.projects
            .filter { !$0.isArchived && !archivedProjectIDs.contains($0.id) }
            .map { project in
                let concept = store.selectedConcept(in: project)
                    ?? project.concepts.first(where: { $0.isOriginal != true })
                    ?? project.concepts.first
                let url = (concept?.imageUrl ?? project.imageUrl).flatMap(URL.init(string:))
                return .project(project, imageURL: url, active: activeProjects.contains(project.id))
            }
        let archivedAssetIDs = Set(store.archivedAssets.map(\.id))
        let assets: [LibraryGalleryItem] = filter == .concepts ? [] : privateAssets
            .filter { asset in
                if asset.isArchived || archivedAssetIDs.contains(asset.id) { return false }
                if filter == .models && (asset.isAnimated || asset.isConcept) { return false }
                if filter == .animations && !asset.isAnimated { return false }
                if filter == .favorites && !favorites.contains(asset.id) { return false }
                return true
            }
            .map { .asset($0, favorite: favorites.contains($0.id)) }
        // Mix the two real collections without pretending they share timestamps.
        var combined: [LibraryGalleryItem] = []
        for index in 0..<max(projects.count, assets.count) {
            if index < projects.count { combined.append(projects[index]) }
            if index < assets.count { combined.append(assets[index]) }
        }
        var seen = Set<String>()
        let matching = combined.filter {
            seen.insert($0.id).inserted && (searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText))
        }
        return alphabetical ? matching.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } : matching
    }
    private var hasPrivateCreations: Bool { !store.projects.isEmpty || !privateAssets.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            searchField.padding(.horizontal, 20)
            filters
            if filter == .archive {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.subheadline)
                        .foregroundStyle(appearance.fill)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.t("30-Day Auto Retention", "30 天自动保留"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(appearance.ink)
                        Text(store.t("Archived creations are preserved for 30 days before being automatically purged from Firebase.", "归档的创作将保留 30 天，逾期将自动彻底清除。"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(appearance.washSoft, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 20)
                .padding(.bottom, 2)
            }
            ScrollView {
                if !store.connected {
                    Label(store.t("Saved library · Reconnect to generate or download", "已保存的资产库 · 联网后可生成或下载"), systemImage: "wifi.slash")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20).padding(.bottom, 10)
                }
                if items.isEmpty {
                    emptyState.padding(.horizontal, 22).padding(.top, 36)
                } else {
                    LibraryGallery(
                        items: items,
                        chinese: store.isChinese,
                        onModify: { item in
                            switch item {
                            case .project(let project, _, _): store.modifyProject(project)
                            case .asset(let asset, _): store.modifyAsset(asset)
                            }
                        },
                        onArchive: { item in
                            Task {
                                switch item {
                                case .project(let project, _, _): await store.archiveProject(project)
                                case .asset(let asset, _): await store.archiveAsset(asset)
                                }
                            }
                        },
                        onRestore: { item in
                            Task {
                                switch item {
                                case .project(let project, _, _): await store.restoreProject(project)
                                case .asset(let asset, _): await store.restoreAsset(asset)
                                }
                            }
                        },
                        onDeletePermanently: { item in
                            Task {
                                switch item {
                                case .project(let project, _, _): await store.deletePermanently(project)
                                case .asset(let asset, _): await store.deletePermanently(asset)
                                }
                            }
                        },
                        onSelect: { item in
                            searching = false
                            openCount += 1
                            switch item {
                            case .project(let project, _, _): store.path.append(.project(project.id))
                            case .asset(let asset, _): store.path.append(.asset(asset))
                            }
                        }
                    )
                    .padding(.horizontal, 14)
                    .padding(.bottom, 24)
                }
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await store.refresh() }
        }
        .padding(.top, 8)
        .frame(maxWidth: 650).frame(maxWidth: .infinity)
        .background { StudioAtmosphere(intensity: 0.8) }
        .toolbar(.hidden, for: .navigationBar)
        .craftFeedback(.optionSelect, trigger: filterCount)
        .craftFeedback(.lightTap, trigger: openCount)
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(store.t("Your library", "你的资产库"))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(appearance.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(store.t("Your ideas, collected.", "收藏你的每一个灵感。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                searching = false
                store.selectedTab = 0
                store.focusComposerTrigger += 1
            } label: {
                Image(systemName: "plus")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(appearance.ink)
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(CraftPressStyle())
            .accessibilityLabel(store.t("Start creating", "开始创作"))
            .accessibilityIdentifier("library.create")
        }
        .padding(.horizontal, 20)
    }

    private var filters: some View {
        HStack(spacing: 7) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(LibraryGalleryFilter.allCases) { option in
                        Button {
                            searching = false
                            filterCount += 1
                            withAnimation(CraftMotion.gated(.fade, reduceMotion)) { filter = option }
                        } label: {
                            Text(option.title(chinese: store.isChinese))
                                .font(.caption.weight(option == filter ? .semibold : .regular))
                                .foregroundStyle(option == filter ? appearance.buttonInk : appearance.ink)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 38)
                                .background(option == filter ? appearance.fill : appearance.washSoft, in: Capsule())
                        }
                        .buttonStyle(CraftPressStyle())
                        .accessibilityAddTraits(option == filter ? .isSelected : [])
                        .accessibilityIdentifier("library.filter." + option.rawValue)
                    }
                }
            }
            Menu {
                Picker(store.t("Sort library", "资产库排序"), selection: $alphabetical) {
                    Text(store.t("Gallery order", "画廊顺序")).tag(false)
                    Text(store.t("Name", "名称")).tag(true)
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(appearance.ink)
                    .frame(width: 40, height: 40)
                    .background(appearance.washSoft, in: Circle())
            }
            .accessibilityLabel(store.t("Sort library", "资产库排序"))
            .accessibilityIdentifier("library.sort")
        }
        .padding(.horizontal, 20)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(appearance.ink)
            TextField(store.t("Search your creations", "搜索作品"), text: $query)
                .font(.subheadline).focused($searching).submitLabel(.search)
                .accessibilityIdentifier("library.search")
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(CraftPressStyle())
                .frame(minWidth: 32, minHeight: 32)
                .accessibilityLabel(store.t("Clear search", "清除搜索"))
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 46)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(searching ? appearance.fill : appearance.hairline, lineWidth: 1))
    }

    private var emptyState: some View {
        let searchingOrFiltered = !searchText.isEmpty || (hasPrivateCreations && filter != .all)
        return CraftEmptyState(
            title: !searchText.isEmpty ? store.t("No matching creations", "没有匹配的作品")
                : filter == .archive ? store.t("Archive is empty", "归档文件夹为空")
                : filter == .favorites ? store.t("Keep your favorites here", "把喜欢的作品留在这里")
                : filter == .models ? store.t("Your next dimension awaits", "下一维度，等你创造")
                : filter == .animations ? store.t("Bring your characters to life", "让你的角色动起来")
                : store.t("A home for your imagination", "给你的想象一个家"),
            message: !searchText.isEmpty ? store.t("Try a different name or clear your filters.", "试试其他名称，或清除筛选。")
                : filter == .archive ? store.t("Long press any creation to archive it. Items are kept for 30 days before automatic deletion.", "长按任意作品即可移至归档。作品将保留 30 天，逾期自动彻底清除。")
                : filter == .favorites ? store.t("Tap the heart in a model's details to save it here.", "在模型信息中点按爱心，即可收藏到这里。")
                : filter == .models ? store.t("Open one of your concepts to bring it into 3D.", "打开你的概念图，让它成为 3D 模型。")
                : filter == .animations ? store.t("Open one of your concepts and tap Animate to generate a looping character animation.", "打开你的概念图，点击“生成动画”即可生成无缝循环角色动画。")
                : store.t("Your concept projects and finished 3D models will appear here. Start with a photo or a few words.", "你的概念项目和 3D 模型会保存在这里。先用照片或几句话开始创作。"),
            actionTitle: searchingOrFiltered ? store.t("Show all creations", "查看全部作品") : store.t("Start creating", "开始创作"),
            action: {
                searching = false
                if searchingOrFiltered { query = ""; filter = .all }
                else { store.selectedTab = 0 }
            })
    }
}

// MARK: - The 3D studio

struct AssetDetailView: View {
    var onClose: (() -> Void)? = nil
    var onPlay: (() -> Void)? = nil
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    @EnvironmentObject var store: CraftStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let asset: CraftAsset

    @AppStorage("craftFavorites") private var favoriteIDs = ""
    private var isFavorite: Bool { favoriteIDs.split(separator: ",").contains(Substring(asset.id)) }

    @State private var lighting: CraftLightingPreset = .studio
    @State private var directional = 1.0
    @State private var environment = 1.0
    @State private var exposure = 1.0
    @State private var showSourceConcept = false
    private var sourceConceptURL: URL? {
        asset.sourceImageURL ?? ConceptModelActivity.sourceImage(for: asset, jobs: store.jobs, projects: store.projects)
    }
    @State private var lightingControls = false
    @State private var lightingFocus = false
    @State private var lightingExpanded = false
    @State private var fullScreen = false
    @State private var mode = "Material"
    @State private var reset = 0
    @State private var sharing: SharedFile?
    @State private var showGameHandoff = false
    @State private var exporting = false
    // Presentation-only state.
    @State private var scrollY: CGFloat = 0
    @State private var modelReady = false
    @State private var showHint = false
    @State private var playCount = 0
    @State private var exportCount = 0
    @State private var favoriteOnCount = 0
    @State private var favoriteOffCount = 0
    @Namespace private var lightingChip

    // Sized so the whole stage — model AND podium — clears the bottom inset
    // (hint + display modes + action card) at rest. A taller stage crops the
    // plinth, which is the one thing the mockup's studio shot is built around.
    private static let stageHeight: CGFloat = 380

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !lightingControls {
                    CraftSteps(selected: 1, chinese: store.isChinese,
                               titles: store.isChinese ? ["概念", "3D", "游戏"] : ["Concept", "3D", "Game"],
                               onConcept: sourceConceptURL == nil ? nil : { showSourceConcept = true }, conceptIndex: 0,
                               onGame: {
                                   playCount += 1
                                   if let onPlay { onPlay() } else { store.path.append(.games(asset)) }
                               }, gameIndex: 2)
                        .padding(.horizontal, 44)
                        .craftEntrance(1)
                    title
                }
                stage.id("studio.lightingPreview")
                if !lightingControls {
                    details
                    Color.clear.frame(height: lightingExpanded ? 260 : 120).id("studio.details.bottom")
                }
            }
            .padding(.horizontal, 22).padding(.vertical, 12)
            .frame(maxWidth: 650).frame(maxWidth: .infinity)
            .craftScrollProbe()
        }
        .onChange(of: lightingControls) { _, opened in
            if opened { proxy.scrollTo("studio.lightingPreview", anchor: .top) }
        }
        .onChange(of: lightingExpanded) { _, expanded in
            if expanded {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    proxy.scrollTo("studio.details.bottom", anchor: .bottom)
                }
            }
        }
        .onPreferenceChange(CraftScrollOffsetKey.self) { value in
            let stepped = (value / 4).rounded() * 4
            if stepped != scrollY { scrollY = stepped }
        }
        .clipped()
        .background {
            StudioAtmosphere(intensity: 1.20,
                             scrollProgress: min(1, Double(max(0, scrollY)) / 600))
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        .safeAreaInset(edge: .bottom, spacing: 0) { if !lightingControls { actionCard } }
        // ModelViewport has no load callback and must not gain one: give the
        // GLB a beat to appear, then resolve the rim light and the halo.
        .task(id: asset.id) {
            modelReady = false
            showHint = false
            try? await Task.sleep(nanoseconds: 450_000_000)
            modelReady = true
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            showHint = true
        }
        .craftFeedback(.modelReady, trigger: modelReady)
        .craftFeedback(.viewReset, trigger: reset)
        .craftFeedback(.stageToggle, trigger: fullScreen)
        .craftFeedback(.primaryAction, trigger: playCount)
        .craftFeedback(.jobSucceeded, trigger: exportCount)
        .craftFeedback(.favoriteOn, trigger: favoriteOnCount)
        .craftFeedback(.favoriteOff, trigger: favoriteOffCount)
        .sheet(isPresented: $showSourceConcept) {
            if let url = sourceConceptURL { ConceptImageInspector(imageURL: url, chinese: store.isChinese) }
        }
        .sheet(item: $sharing) { ShareSheet(url: $0.url) }
        .sheet(isPresented: $showGameHandoff) { GameHandoffView(asset: asset) }
        .overlay {
            if lightingControls {
                GeometryReader { _ in
                    ZStack(alignment: .bottom) {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { if !lightingFocus { lightingControls = false } }
                            LightingAdjustmentView(chinese: store.isChinese,
                                onClose: { lightingControls = false },
                                onFocusChange: { lightingFocus = $0 },
                                directional: $directional, environment: $environment, exposure: $exposure)
                        .fixedSize(horizontal: false, vertical: true)
                        .clipShape(RoundedRectangle(cornerRadius: 30))
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                    }
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: lightingFocus)
                }
                .transition(.opacity)
                .onDisappear { lightingFocus = false }
            }
        }
        .fullScreenCover(isPresented: $fullScreen) { fullScreenStage }
        .onAppear {
            GamePrewarmer.shared.prewarm(webBase: store.webBase)
        }
        }
    }

    // MARK: Sections

    private var topBar: some View {
        HStack {
            CraftCircleTool(icon: "arrow.left", title: store.t("Back", "返回")) {
                if let onClose { onClose() } else if !store.path.isEmpty { store.path.removeLast() }
            }
            .accessibilityIdentifier("studio.back")
            Spacer()
            Text(store.t("YOUR STUDIO", "你的工作室"))
                .font(.caption.weight(.medium)).tracking(2).foregroundStyle(.secondary)
            Spacer()
            CreationCostButton(projectID: store.jobs.first { $0.assets.contains { $0.id == asset.id } }?.projectId, imageCount: 0)
            CraftCircleTool(icon: "square.and.arrow.up", title: store.t("Export model", "导出模型")) { exportModel() }
                .disabled(exporting)
        }
        .padding(.horizontal, 22).padding(.vertical, 8)
        .craftEntrance(0)
    }

    private var title: some View {
        VStack(spacing: 6) {
            Text(asset.name)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
                .craftEntrance(2)
            Text(asset.isExample ? store.t("Studio example", "工作室示例") : store.t("Made by you", "由你创造"))
                .font(.subheadline).foregroundStyle(.secondary)
                .craftEntrance(3)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var stage: some View {
        if let url = asset.modelURL {
            CraftHeroStage(height: (lightingControls ? 430 : Self.stageHeight), style: .bare, showsAccents: false,
                           lit: modelReady, scrollOffset: scrollY) {
                ModelViewport(modelURL: url, mode: mode, resetID: reset, chinese: store.isChinese,
                              lighting: lighting, directional: directional,
                              environment: environment, exposure: exposure, softStage: true)
            }
            .frame(height: (lightingControls ? 430 : Self.stageHeight))
            .craftEntrance(4, style: .reveal)
            .overlay(alignment: .trailing) { if !lightingControls { toolStack } }
        } else {
            ContentUnavailableView(store.t("Model unavailable", "模型不可用"), systemImage: "cube")
                .frame(height: (lightingControls ? 430 : Self.stageHeight))
                .craftEntrance(4, style: .reveal)
        }
    }

    private var toolStack: some View {
        VStack(spacing: 12) {
            studioTool(icon: "arrow.triangle.2.circlepath", title: store.t("Reset view", "重置视角"), caption: store.t("Reset", "重置")) { reset += 1 }
                .symbolEffect(.bounce, value: reset)
                .craftEntrance(5, style: .slideTrailing, distance: 14)
            studioTool(icon: "sun.max", title: store.t("Adjust lighting", "调整灯光"), caption: store.t("Lighting", "灯光")) { lightingControls = true }
                .accessibilityIdentifier("lighting.adjust")
                .craftEntrance(6, style: .slideTrailing, distance: 14)
            studioTool(icon: "arrow.up.left.and.arrow.down.right", title: store.t("Full screen", "全屏"), caption: store.t("Expand", "展开")) { fullScreen = true }
                .accessibilityIdentifier("model.fullscreen")
                .craftEntrance(7, style: .slideTrailing, distance: 14)
        }
        .padding(.trailing, 2)
    }

    private func studioTool(icon: String, title: String, caption: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .medium))
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.94), in: Circle())
                    .shadow(color: appearance.ink.opacity(0.08), radius: 8, y: 4)
                Text(caption).font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(appearance.ink)
            .contentShape(Rectangle())
        }
        .buttonStyle(CraftPressStyle(scale: 0.94))
        .accessibilityLabel(title)
    }

    private var dragHint: some View {
        Label(store.t("Drag to explore · Pinch to zoom", "拖动查看 · 双指缩放"),
              systemImage: "hand.point.up.left")
            .font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .opacity(showHint ? 1 : 0)
            .animation(CraftMotion.gated(.reveal, reduceMotion), value: showHint)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    lightingExpanded.toggle()
                }
            } label: {
                HStack {
                    Label(store.t("Lighting & model details", "灯光与模型信息"), systemImage: "slider.horizontal.2.square")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(appearance.ink)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(appearance.ink.opacity(0.75))
                        .rotationEffect(.degrees(lightingExpanded ? 180 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(CraftPressStyle(scale: 0.98))
            .accessibilityIdentifier("studio.lightingToggle")

            if lightingExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    Divider().opacity(0.4)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(CraftLightingPreset.allCases) { preset in
                                let on = lighting == preset
                                Button {
                                    withAnimation(CraftMotion.gated(.snap, reduceMotion)) { lighting = preset }
                                } label: {
                                    Text(preset.title(chinese: store.isChinese))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(on ? appearance.ink : .primary)
                                        .padding(.horizontal, 16).padding(.vertical, 11)
                                        .background {
                                            if on {
                                                Capsule().fill(appearance.washStrong)
                                                    .matchedGeometryEffect(id: "lightingChip", in: lightingChip)
                                            } else {
                                                Capsule().fill(CraftTheme.panel)
                                            }
                                        }
                                }
                                .buttonStyle(CraftPressStyle())
                                .accessibilityIdentifier("lighting." + preset.rawValue)
                                .accessibilityAddTraits(on ? .isSelected : [])
                            }
                        }
                        .padding(.horizontal, 2)
                        .padding(.vertical, 2)
                    }
                    .scrollClipDisabled()

                    HStack {
                        Label("\(asset.faces.formatted())", systemImage: "triangle")
                        Spacer()
                        Text(String(format: "%.1f MB · GLB", asset.fileSizeMb))
                    }.font(.caption).foregroundStyle(.secondary)

                    Button {
                        var ids = Set(favoriteIDs.split(separator: ",").map(String.init))
                        if isFavorite { ids.remove(asset.id); favoriteOffCount += 1 }
                        else { ids.insert(asset.id); favoriteOnCount += 1 }
                        favoriteIDs = ids.sorted().joined(separator: ",")
                    } label: {
                        Label {
                            Text(store.t("Favorite", "收藏"))
                        } icon: {
                            Image(systemName: isFavorite ? "heart.fill" : "heart")
                                .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                                .foregroundStyle(isFavorite ? appearance.ink : .secondary)
                        }
                    }
                    .buttonStyle(CraftPressStyle())
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.97, anchor: .top)),
                    removal: .opacity.combined(with: .move(edge: .top))
                ))
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(appearance.fill.opacity(lightingExpanded ? 0.35 : 0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(lightingExpanded ? 0.08 : 0.03), radius: 10, y: 4)
        .id("studio.details")
        .craftEntrance(9, style: .fade)
    }

    /// The hint and the display modes sit on the gradient ABOVE the white card,
    /// the way the mockup stages them — and, critically, they stay on screen.
    /// Inside the scroll content the card would cover them, and two UI suites
    /// tap `Solid` / `Material` / `Wire` without scrolling first.
    private var actionCard: some View {
        VStack(spacing: 12) {
            dragHint
            CraftSegmented<String>(options: [
                .init("Material", store.t("Material", "材质")),
                .init("Solid", store.t("Solid", "实体")),
                .init("Wire", store.t("Wire", "线框"))
            ], selection: $mode)
                .padding(.horizontal, 22)
                .craftEntrance(8)
            bottomCard
        }
        .frame(maxWidth: 650).frame(maxWidth: .infinity)
    }

    private var bottomCard: some View {
        VStack(spacing: 10) {
            Button {
                playCount += 1
                if let onPlay { onPlay() } else { store.path.append(.games(asset)) }
            } label: {
                Label(store.t("Play in game", "带入游戏试玩"), systemImage: "gamecontroller.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(CraftPrimary(armed: modelReady, verticalPadding: 14, cornerRadius: 16))
            .disabled(asset.modelURL == nil)
            .accessibilityIdentifier("asset.playInGame")

            Button { showGameHandoff = true; playCount += 1 } label: {
                Label(store.t("Send to ChatGPT / Claude Code", "发送到 ChatGPT / Claude Code"), systemImage: "paperplane")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(CraftPressStyle())
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 16).strokeBorder(appearance.hairline))
            .disabled(asset.modelURL == nil)
            .accessibilityIdentifier("asset.gameHandoff")

            Button(exporting ? store.t("Preparing…", "准备中……") : store.t("Export model", "导出模型")) { exportModel() }
                .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                .contentTransition(.opacity)
                .animation(CraftMotion.gated(.fade, reduceMotion), value: exporting)
                .buttonStyle(CraftPressStyle())
                .disabled(exporting)
                .frame(maxWidth: .infinity, minHeight: 38)
        }
        .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .background(CraftTheme.card, in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous))
        .craftDepth(.floating)
    }

    // Retained for restoring built-in play after the handoff-focused demo.
    // The game routes and runtimes remain unchanged; this control is not rendered.
    private var builtInPlayButton: some View {
        Button {
            playCount += 1
            if let onPlay { onPlay() } else { store.path.append(.games(asset)) }
        } label: {
            Label(store.t("Try in a game", "带入游戏试玩"), systemImage: "gamecontroller")
        }
        .accessibilityIdentifier("asset.play")
    }

    private var fullScreenStage: some View {
        ZStack(alignment: .topTrailing) {
            StudioAtmosphere(intensity: 1.20)
            if let url = asset.modelURL {
                ModelViewport(modelURL: url, mode: mode, chinese: store.isChinese,
                              lighting: lighting, directional: directional,
                              environment: environment, exposure: exposure, softStage: true,
                              showsZoomControls: true)
                    .craftEntrance(0, style: .reveal)
            }
            CraftCircleTool(icon: "xmark", title: store.t("Close full screen", "退出全屏"), diameter: 50) {
                fullScreen = false
            }
            .accessibilityIdentifier("model.closeFullscreen")
            .padding()
        }
        .craftAmbientHost()
    }

    private func exportModel() {
        exporting = true
        Task {
            do { sharing = SharedFile(url: try await store.export(asset)); exportCount += 1 }
            catch { store.error = error.localizedDescription }
            exporting = false
        }
    }
}

struct SharedFile: Identifiable { let id = UUID(); let url: URL }

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Profile

struct ProfileView: View {
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    @EnvironmentObject var store: CraftStore
    @ObservedObject private var profile = CraftProfile.shared
    @ObservedObject private var account = CraftAccount.shared

    @State private var editingProfile = false
    @State private var aiAccountOpen = false
    @State private var showCustomerCenter = false
    @State private var deletingAccount = false
    @State private var apiAccessOpen = false
    @State private var showIntroduction = false
    @State private var showArchiveFolder = false
    @State private var scrollY: CGFloat = 0
    @State private var rowCount = 0

    var body: some View {
        Group {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    headline
                    identityRow
                    accountSection
                    CraftAIPrivacySettings()
                    AppearanceSettingsView()
                    PricingDetailsToggle()
                    CreationCostButton(iconOnly: false)
                    preview
                    settingsRows
                }
                .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 28)
                .frame(maxWidth: 650).frame(maxWidth: .infinity)
                .craftScrollProbe()
            }
            .onPreferenceChange(CraftScrollOffsetKey.self) { value in
                let stepped = (value / 4).rounded() * 4
                if stepped != scrollY { scrollY = stepped }
            }
        }
        .background {
            StudioAtmosphere(intensity: 1.10,
                             scrollProgress: min(1, Double(max(0, scrollY)) / 600))
        }
        .craftFeedback(.optionSelect, trigger: rowCount)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $editingProfile) { ProfileEditorView() }
        .sheet(isPresented: $aiAccountOpen) { AIAccountView() }
        .sheet(isPresented: $showArchiveFolder) { ProfileArchiveSheet() }
        .sheet(isPresented: $deletingAccount) { AccountDeletionView() }
        .sheet(isPresented: $apiAccessOpen) { APIAccessView() }
        .fullScreenCover(isPresented: $showIntroduction) {
            CraftIntroductionView {
                showIntroduction = false
            }
            .environmentObject(store)
        }
        .presentCustomerCenter(isPresented: $showCustomerCenter)
    }

    private var header: some View {
        HStack {
            CraftBrand()
            Spacer()
        }
        .craftEntrance(0)
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(store.t("Your space.", "你的空间。"))
            Text(store.t("Your style.", "你的风格。")).foregroundStyle(appearance.ink)
        }
        .font(.system(size: 36, weight: .bold, design: .rounded))
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .craftEntrance(1)
    }

    private var identityRow: some View {
        Button { editingProfile = true } label: {
            HStack(spacing: 14) {
                CraftAvatar(size: 68)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.displayName(chinese: store.isChinese)).font(.title3.bold()).lineLimit(2)
                    Text(store.t("Edit name & avatar", "编辑名称与头像"))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(CraftPressStyle(scale: 0.985))
        .accessibilityIdentifier("profile.edit")
        .accessibilityLabel(profile.displayName(chinese: store.isChinese) + " · " + store.t("Edit profile", "编辑个人资料"))
        .craftEntrance(2)
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(store.t("3D Craft account", "3D Craft 账户")).font(.headline)
            Text(account.email).font(.subheadline).foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text(store.t("Your synced creations stay saved when you sign out.", "退出登录后，已同步的作品仍会保留。"))
                .font(.footnote).foregroundStyle(.secondary)
            Button { account.signOut() } label: {
                Label(store.t("Sign out", "退出登录"), systemImage: "rectangle.portrait.and.arrow.right")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(appearance.washStrong, in: Capsule())
            }
            .foregroundStyle(appearance.ink)
            .buttonStyle(CraftPressStyle())
            .accessibilityIdentifier("profile.signOut")
            Button(role: .destructive) { deletingAccount = true } label: {
                Label(store.t("Delete account", "删除账户"), systemImage: "person.crop.circle.badge.minus")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }.accessibilityIdentifier("profile.deleteAccount")
        }
        .padding(18)
        .craftSurface(.raised, cornerRadius: 20)
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(store.t("Preview", "预览")).font(.title3.bold())
            Button { store.selectedTab = 0 } label: { CraftPreview(chinese: store.isChinese) }
                .buttonStyle(CraftLiftStyle(scale: 1.015))
        }
        .craftEntrance(4, style: .popIn)
    }

    private var settingsRows: some View {
        VStack(spacing: 4) {
            if CraftAIAccount.enabledForRelease {
            navigationRow("brain.head.profile", store.aiAccount.connected
                ? store.t("ChatGPT connected", "ChatGPT 已连接") : store.t("Connect ChatGPT", "连接 ChatGPT")) {
                aiAccountOpen = true
            }.accessibilityIdentifier("profile.aiAccount")
            Divider().opacity(0.4)
            }

            Toggle(isOn: $store.isChinese) {
                rowLabel("globe", store.t("Chinese interface", "中文界面"))
            }
            .tint(appearance.ink)
            .accessibilityIdentifier("languageChinese")
            .frame(minHeight: 52)
            .onChange(of: store.isChinese) { _, _ in rowCount += 1 }

            Divider().opacity(0.4)

            navigationRow("sparkles.tv", store.t("Product Tour & Features", "产品介绍与功能演示")) {
                showIntroduction = true
            }
            .accessibilityIdentifier("profile.introTour")

            Divider().opacity(0.4)

            navigationRow("wallet.pass", store.t("Wallet & activity", "余额与使用记录")) {
                store.path.append(.wallet)
            }

            Divider().opacity(0.4)

            navigationRow("sparkles", store.t("Creator Plans & Top-up", "创作者计划与充值")) {
                store.showPaywall = true
            }

            Divider().opacity(0.4)

            navigationRow("creditcard", store.t("Membership & Subscriptions", "订阅与会员服务")) {
                showCustomerCenter = true
            }

            if account.uid != nil {
                Divider().opacity(0.4)

                navigationRow("key.horizontal", store.t("API access", "API 访问")) {
                    apiAccessOpen = true
                }.accessibilityIdentifier("profile.apiAccess")
            }

            Divider().opacity(0.4)

            archiveFolderRow
        }
        .font(.subheadline)
        .craftEntrance(5, step: 0.04)
    }

    private var archiveFolderRow: some View {
        Button {
            showArchiveFolder = true
        } label: {
            HStack {
                rowLabel("archivebox", store.t("Archive Folder", "归档文件夹"))
                let totalArchived = store.archivedAssets.count + store.archivedProjects.count
                if totalArchived > 0 {
                    Text("\(totalArchived)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(appearance.ink)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(appearance.washStrong, in: Capsule())
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(CraftPressStyle(scale: 0.99))
        .accessibilityIdentifier("profile.archiveFolder")
    }

    private func navigationRow(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                rowLabel(icon, title)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(CraftPressStyle(scale: 0.99))
    }

    private func rowLabel(_ icon: String, _ title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(appearance.ink)
                .frame(width: 34, height: 34)
                .background(appearance.washSoft, in: Circle())
            Text(title).foregroundStyle(.primary)
        }
    }

}

// MARK: - Wallet

struct WalletView: View {
    @EnvironmentObject private var billing: BillingManager
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    @EnvironmentObject var store: CraftStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var topUpCount = 0
    @State private var animatedBalance: Int?
    @State private var rewardVisible = false
    @State private var rewardTokens = 0
    @State private var purchaseFeedback = 0

    private var visibleBalance: Int {
        animatedBalance ?? store.walletCelebration.map { $0.balance - $0.tokens } ?? store.wallet.available
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(visibleBalance) Tokens")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .craftNumeric(visibleBalance, reduceMotion: reduceMotion)
                        .accessibilityLabel(store.t("Token balance", "Token 余额"))
                        .accessibilityValue("\(store.wallet.available)")
                        .accessibilityIdentifier("wallet.balanceValue")
                    if rewardTokens > 0 {
                        Label("+\(rewardTokens.formatted()) Tokens", systemImage: "checkmark.circle.fill")
                            .font(.title3.bold()).foregroundStyle(appearance.ink)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(CraftTheme.card, in: Capsule())
                            .scaleEffect(reduceMotion ? 1 : (rewardVisible ? 1 : 0.85))
                            .offset(y: reduceMotion ? 0 : (rewardVisible ? 0 : -8))
                            .opacity(rewardVisible ? 1 : 0)
                            .accessibilityIdentifier("wallet.purchaseReward")
                    }
                    Text(store.wallet.environment == "SANDBOX"
                         ? store.t("Apple Sandbox test balance", "Apple 沙盒测试余额")
                         : store.t("Available for your next creation", "可用于下一次创作"))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(appearance.wash, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .craftEntrance(0, style: .popIn)
                .id("wallet.balance")

                if let message = billing.walletSyncMessage {
                    HStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath").foregroundStyle(appearance.ink)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.t("Purchase sync", "购买同步")).font(.subheadline.bold())
                            Text(message).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Button(store.t("Retry", "重试")) {
                            Task { try? await billing.reconcileWallet(store: store, force: true) }
                        }.disabled(billing.syncingWallet).frame(minHeight: 44)
                    }.padding(16).background(CraftTheme.card, in: RoundedRectangle(cornerRadius: 20))
                }

                if let packs = store.wallet.packAvailable {
                    amountRow(store.t("Token packs · Never expire", "代币包 · 永不过期"), packs, index: 1)
                }
                if let expiry = store.wallet.subscriptionExpiresAt, expiry > Date() {
                    VStack(alignment: .leading, spacing: 6) {
                        amountRow(store.t("Current plan Tokens", "本期订阅 Tokens"), store.wallet.subscriptionAvailable, index: 1)
                        Text(store.t("Expires ", "到期时间：") + expiry.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16)
                    }
                }
                amountRow(store.t("Free concept credit", "免费概念额度"), store.wallet.freeConceptTokens, index: 1)
                amountRow(store.t("Reserved for active jobs", "进行中任务预留"), store.wallet.reserved, index: 2)

                Button { topUpCount += 1; store.showPaywall = true } label: {
                    Text(store.t("Get more Tokens", "获取更多 Tokens"))
                }
                .buttonStyle(CraftPrimary(armed: true))
                .craftEntrance(3)

                if !store.wallet.ledger.isEmpty {
                    Text(store.t("Activity", "使用记录")).font(.title3.bold()).craftEntrance(4)
                    ForEach(Array(store.wallet.ledger.enumerated()), id: \.element.id) { index, entry in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(activityTitle(entry.description))
                                    .font(.subheadline).lineLimit(2)
                                Text(entry.date, style: .date)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Text(entry.description == "reserve"
                                 ? store.t("\(abs(entry.amount)) held", "预留 \(abs(entry.amount))")
                                 : entry.amount.formatted(.number.sign(strategy: .always())))
                                .font(.subheadline.weight(.semibold)).monospacedDigit()
                                .foregroundStyle(entry.amount < 0 ? .secondary : appearance.ink)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(CraftTheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .craftDepth(.card)
                        .craftEntrance(index + 5, step: 0.04)
                    }
                }
            }
            .padding(.horizontal, 22).padding(.vertical, 12)
            .frame(maxWidth: 650).frame(maxWidth: .infinity)
        }
        .onChange(of: store.walletCelebration?.id, initial: true) { _, id in
            if id != nil { proxy.scrollTo("wallet.balance", anchor: .top) }
        }
        }
        .background { StudioAtmosphere(intensity: 0.90) }
        .craftFeedback(.primaryAction, trigger: topUpCount)
        .craftFeedback(.purchaseSucceeded, trigger: purchaseFeedback)
        .task(id: store.walletCelebration?.id) {
            guard let receipt = store.walletCelebration else { return }
            animatedBalance = receipt.balance - receipt.tokens
            rewardVisible = false
            rewardTokens = receipt.tokens
            // The paywall has dismissed; let Wallet finish its navigation transition
            // before showing the reward and changing the visible balance.
            do { try await Task.sleep(for: .milliseconds(550)) } catch { return }
            guard store.walletCelebration?.id == receipt.id else { return }
            store.markPurchaseAnimationVisible(receipt)
            purchaseFeedback += 1
            withAnimation(reduceMotion ? nil : .spring(response: 0.65, dampingFraction: 0.75)) {
                rewardVisible = true
            }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 1.15)) {
                animatedBalance = receipt.balance
            }
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.35)) { rewardVisible = false }
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            animatedBalance = nil; rewardTokens = 0
            if store.walletCelebration?.id == receipt.id { store.walletCelebration = nil }
        }
        .onDisappear {
            // A sheet/navigation transition can hide Wallet before the reward is
            // visible. Keep that receipt so the next appearance can show it.
            if rewardVisible { store.walletCelebration = nil }
            animatedBalance = nil; rewardTokens = 0; rewardVisible = false
        }
        .navigationTitle(store.t("Wallet", "钱包"))
    }

    private func amountRow(_ title: String, _ value: Int, index: Int) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            Text("\(value)").font(.subheadline.weight(.semibold)).monospacedDigit()
                .craftNumeric(value, reduceMotion: reduceMotion)
        }
        .font(.subheadline)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CraftTheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .craftDepth(.card)
        .craftEntrance(index, step: 0.04)
    }

    private func activityTitle(_ kind: String) -> String {
        switch kind {
        case "reserve": return store.t("Generation reservation · not an extra charge", "生成预留 · 非额外扣费")
        case "settle": return store.t("Completed generation · final cost", "生成结算 · 最终消耗")
        case "chat_reservation": return store.t("Tokens reserved for AI reply", "AI 回复预留 Tokens")
        case "chat_complete": return store.t("AI reply ready · unused Tokens returned", "AI 回复已完成 · 已退回未使用 Tokens")
        case "chat_refund": return store.t("Unused chat Tokens returned", "已退回未使用的对话 Tokens")
        case "planning_reservation": return store.t("Tokens reserved for prompt improvement", "优化描述预留 Tokens")
        case "planning_complete": return store.t("Prompt ready · unused Tokens returned", "描述已优化 · 已退回未使用 Tokens")
        case "planning_refund": return store.t("Unused planning Tokens returned", "已退回未使用的规划 Tokens")
        case "generation_reservation": return store.t("Tokens reserved for generation", "生成任务预留 Tokens")
        case "generation_complete": return store.t("3D completed · reserved Tokens used", "3D 已完成 · 已使用预留 Tokens")
        case "generation_refund": return store.t("Unused generation Tokens returned", "已退回未使用的生成 Tokens")
        case "review_credit": return store.t("Free testing Tokens", "免费测试额度")
        case "development_purchase": return store.t("Test purchase credit", "测试购买额度")
        case "sandbox_purchase": return store.t("Purchase · Sandbox test", "购买到账 · 沙盒测试")
        case "verified_purchase": return store.t("Purchase · Tokens added", "购买到账")
        case "purchase_refund": return store.t("Apple purchase refund", "Apple 购买退款")
        case "subscription_expiry": return store.t("Previous plan Tokens expired", "上期订阅 Tokens 已到期")
        case "subscription_refund": return store.t("Refunded plan Tokens removed", "已移除退款订阅的 Tokens")
        case "review_reconciliation": return store.t("Review balance adjustment", "测试余额调整")
        default: return store.t("Token adjustment", "额度调整")
        }
    }
}

// MARK: - Profile Archive Sheet

private enum ArchivedCreation: Identifiable {
    case asset(CraftAsset)
    case project(CraftProject)

    var id: String {
        switch self {
        case .asset(let a): return "asset:" + a.id
        case .project(let p): return "project:" + p.id
        }
    }
    var name: String {
        switch self {
        case .asset(let a): return a.name
        case .project(let p): return p.name
        }
    }
    var daysRemaining: Int {
        switch self {
        case .asset(let a): return a.daysRemaining
        case .project(let p): return p.daysRemaining
        }
    }
    func kindTitle(chinese: Bool) -> String {
        switch self {
        case .asset(let a): return a.kindTitle(chinese: chinese)
        case .project: return chinese ? "项目灵感" : "Project"
        }
    }
    var imageURL: URL? {
        switch self {
        case .asset(let a): return a.thumbURL ?? a.sourceImageURL
        case .project(let p): return (p.concepts.first(where: { $0.isOriginal != true })?.imageUrl ?? p.imageUrl).flatMap(URL.init(string:))
        }
    }
    var kindIcon: String {
        switch self {
        case .asset(let a): return a.kindIcon
        case .project: return "folder.fill"
        }
    }
}

struct ProfileArchiveSheet: View {
    @EnvironmentObject private var store: CraftStore
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    @Environment(\.dismiss) private var dismiss
    @State private var itemToDelete: ArchivedCreation?
    @State private var showDeleteConfirmation = false
    @State private var restoringItemId: String?
    @State private var restoredNotice: String?

    private var archivedCreations: [ArchivedCreation] {
        var list: [ArchivedCreation] = []
        for asset in store.archivedAssets {
            list.append(.asset(asset))
        }
        for project in store.archivedProjects {
            list.append(.project(project))
        }
        return list
    }

    var body: some View {
        NavigationStack {
            Group {
                if archivedCreations.isEmpty {
                    VStack(spacing: 18) {
                        ContentUnavailableView(
                            store.t("Archive is Empty", "归档文件夹为空"),
                            systemImage: "archivebox",
                            description: Text(store.t("Creations you archive from the library will appear here for 30 days before permanent deletion.", "在资料库中长按并归档的作品将保留在此处30天，期满自动彻底删除。"))
                        )
                        if restoredNotice != nil {
                            Button {
                                dismiss()
                                store.selectedTab = 1
                            } label: {
                                Label(store.t("Go to Library", "前往资料库"), systemImage: "square.grid.2x2")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .background(appearance.washStrong, in: Capsule())
                            }
                            .foregroundStyle(appearance.ink)
                            .buttonStyle(CraftPressStyle())
                        }
                    }
                    .padding(24)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            headerNotice
                            if let notice = restoredNotice {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text(notice)
                                        .font(.caption.weight(.medium))
                                    Spacer()
                                    Button(store.t("View in Library", "在资料库查看")) {
                                        dismiss()
                                        store.selectedTab = 1
                                    }
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(appearance.ink)
                                }
                                .padding(12)
                                .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            ForEach(archivedCreations) { item in
                                archiveItemRow(item)
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .background { StudioAtmosphere() }
            .navigationTitle(store.t("Archive Folder", "归档文件夹"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(store.t("Done", "完成")) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .confirmationDialog(
                store.t("Delete Permanently?", "确认彻底删除？"),
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button(store.t("Delete Permanently", "彻底删除"), role: .destructive) {
                    if let target = itemToDelete {
                        Task {
                            switch target {
                            case .asset(let a): await store.deletePermanently(a)
                            case .project(let p): await store.deletePermanently(p)
                            }
                        }
                    }
                }
                Button(store.t("Cancel", "取消"), role: .cancel) {}
            } message: {
                Text(store.t("This action cannot be undone. The creation will be permanently deleted from Firebase.", "此操作无法撤销。作品将从 Firebase 云端彻底删除。"))
            }
            .task {
                await store.loadArchived()
            }
        }
    }

    private var headerNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(appearance.ink)
                .font(.system(size: 16))
            Text(store.t("Archived items are kept for 30 days. You can restore any item back to your Library at any time.", "归档作品保留30天。你随时可以点击恢复，作品将立即回到资料库。"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(appearance.washSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func archiveItemRow(_ item: ArchivedCreation) -> some View {
        HStack(spacing: 14) {
            ZStack {
                appearance.washStrong
                if let thumb = item.imageURL {
                    CraftThumbnailImage(url: thumb, inset: 2)
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: item.kindIcon)
                        .font(.system(size: 24))
                        .foregroundStyle(appearance.ink.opacity(0.7))
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(item.kindTitle(chinese: store.isChinese))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(appearance.ink)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(appearance.washStrong, in: Capsule())
                }

                Text(store.isChinese ? "⏳ 剩余 \(item.daysRemaining) 天" : "⏳ \(item.daysRemaining)d left")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Button {
                    restoringItemId = item.id
                    Task {
                        switch item {
                        case .asset(let a): await store.restoreAsset(a)
                        case .project(let p): await store.restoreProject(p)
                        }
                        restoringItemId = nil
                        restoredNotice = store.t("Restored \"\(item.name)\" to Library", "已恢复 “\(item.name)” 到资料库")
                    }
                } label: {
                    if restoringItemId == item.id {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(store.t("Restore", "恢复"), systemImage: "arrow.uturn.backward")
                            .font(.caption.weight(.semibold))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(appearance.washStrong, in: Capsule())
                .foregroundStyle(appearance.ink)
                .buttonStyle(CraftPressStyle())

                Button {
                    itemToDelete = item
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.red.opacity(0.85))
                        .padding(8)
                        .background(Color.red.opacity(0.1), in: Circle())
                }
                .buttonStyle(CraftPressStyle())
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(appearance.fill.opacity(0.18), lineWidth: 1)
        )
    }
}

