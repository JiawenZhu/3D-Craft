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
        let activeProjects = Set(store.jobs.filter(\.isActive).map(\.projectId))
        let projects: [LibraryGalleryItem] = filter == .models || filter == .favorites ? [] : store.projects.map { project in
            let concept = store.selectedConcept(in: project)
                ?? project.concepts.first(where: { $0.isOriginal != true })
                ?? project.concepts.first
            let url = (concept?.imageUrl ?? project.imageUrl).flatMap(URL.init(string:))
            return .project(project, imageURL: url, active: activeProjects.contains(project.id))
        }
        let models: [LibraryGalleryItem] = filter == .concepts ? [] : privateAssets
            .filter { filter != .favorites || favorites.contains($0.id) }
            .map { .asset($0, favorite: favorites.contains($0.id)) }
        // Mix the two real collections without pretending they share timestamps.
        var combined: [LibraryGalleryItem] = []
        for index in 0..<max(projects.count, models.count) {
            if index < projects.count { combined.append(projects[index]) }
            if index < models.count { combined.append(models[index]) }
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
                    LibraryGallery(items: items, chinese: store.isChinese) { item in
                        searching = false
                        openCount += 1
                        switch item {
                        case .project(let project, _, _): store.path.append(.project(project.id))
                        case .asset(let asset, _): store.path.append(.asset(asset))
                        }
                    }
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
            Button { searching = false; store.selectedTab = 0 } label: {
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
                : filter == .favorites ? store.t("Keep your favorites here", "把喜欢的作品留在这里")
                : filter == .models ? store.t("Your next dimension awaits", "下一维度，等你创造")
                : store.t("A home for your imagination", "给你的想象一个家"),
            message: !searchText.isEmpty ? store.t("Try a different name or clear your filters.", "试试其他名称，或清除筛选。")
                : filter == .favorites ? store.t("Tap the heart in a model's details to save it here.", "在模型信息中点按爱心，即可收藏到这里。")
                : filter == .models ? store.t("Open one of your concepts to bring it into 3D.", "打开你的概念图，让它成为 3D 模型。")
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
                               onConcept: sourceConceptURL == nil ? nil : { showSourceConcept = true }, conceptIndex: 0)
                        .padding(.horizontal, 44)
                        .craftEntrance(1)
                    title
                }
                stage.id("studio.lightingPreview")
                if !lightingControls { details }
            }
            .padding(.horizontal, 22).padding(.vertical, 12)
            .frame(maxWidth: 650).frame(maxWidth: .infinity)
            .craftScrollProbe()
        }
        .onChange(of: lightingControls) { _, opened in
            if opened { proxy.scrollTo("studio.lightingPreview", anchor: .top) }
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
        DisclosureGroup(store.t("Lighting & model details", "灯光与模型信息"), isExpanded: $lightingExpanded) {
            VStack(alignment: .leading, spacing: 14) {
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
            .padding(.top, 14)
        }
        .font(.subheadline)
        .tint(appearance.ink)
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
            Button { showGameHandoff = true; playCount += 1 } label: {
                Label(store.t("Send to ChatGPT / Claude Code", "发送到 ChatGPT / Claude Code"), systemImage: "paperplane")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(CraftPrimary(armed: modelReady, verticalPadding: 14, cornerRadius: 16))
            .disabled(asset.modelURL == nil)
            .accessibilityIdentifier("asset.gameHandoff")

            Button(exporting ? store.t("Preparing…", "准备中……") : store.t("Export model", "导出模型")) { exportModel() }
                .font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                .contentTransition(.opacity)
                .animation(CraftMotion.gated(.fade, reduceMotion), value: exporting)
                .buttonStyle(CraftPressStyle())
                .disabled(exporting)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 16).strokeBorder(appearance.hairline))
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
        .sheet(isPresented: $deletingAccount) { AccountDeletionView() }
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
        }
        .font(.subheadline)
        .craftEntrance(5, step: 0.04)
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
