import SwiftUI

/// The concept carousel — the emotional centre of the app. The centred card is
/// full size and sharp; its neighbours sit back, tilt away and soften, exactly
/// as the mockups show.
///
/// SELECTION INVARIANT: the accent ring and the check badge are driven by the
/// store's persisted selection, never by the scroll position. A past regression
/// put the outline on a neighbouring card while the caption named the selected
/// one; `centeredConceptID` therefore only ever *centres* the carousel, and
/// every write to it preserves that separation.
struct ConceptProjectView: View {
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    @EnvironmentObject var store: CraftStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @ScaledMetric(relativeTo: .title2) private var headingSize: CGFloat = 24
    let projectID: String

    @State private var refinement = ""
    @State private var inspectImage = false
    @State private var modelSource: CraftConcept?
    @State private var confirmRefine = false
    @State private var confirmMore = false
    @State private var settingsOpen = false
    @State private var centeredConceptID: String?
    @State private var submittingConceptID: String?
    @State private var watchedModelJobs: Set<String> = []
    @State private var openedModelJobs: Set<String> = []
    @State private var revealedImageJobs: Set<String> = []
    private static let artworkAnchor = "concept.artwork"

    // Presentational state only.
    @State private var scrollY: CGFloat = 0
    @State private var stepShown = 0
    @State private var refineOpen = false
    @State private var browseTick = 0
    @State private var make3DTaps = 0
    @State private var animateSource: CraftConcept?
    @State private var preferredModelEngine = "tripo"
    @State private var preferredAnimationModel = "atlas-minimax-h3"

    var project: CraftProject? { store.projects.first { $0.id == projectID } }
    var selected: CraftConcept? { project.flatMap { store.selectedConcept(in: $0) } }
    var jobs: [CraftJob] { store.jobs.filter { $0.projectId == projectID } }
    var active: Bool { jobs.contains { $0.isActive } }
    private var selectedModelJob: CraftJob? {
        selected.flatMap { ConceptModelActivity.latestJob(for: $0, jobs: jobs) }
    }

    private var modelCompletionRevision: [String] {
        jobs.filter { $0.kind == "model" }.map { $0.id + ":" + $0.status + ":" + $0.assets.map { $0.id + ($0.modelUrl ?? "") }.joined(separator: ",") }
    }
    private func revealFinishedModel() {
        // The root completion card offers explicit navigation, also while playing.
    }

    /// Leave room for the thumbnail rail and selected concept above the action.
    private var cardHeight: CGFloat { verticalSizeClass == .compact ? 230 : 286 }
    private var refineReady: Bool {
        !refinement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !store.busy && !active
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                CraftSteps(selected: stepShown, chinese: store.isChinese)
                    .padding(.horizontal, 40)
                    .craftEntrance(0)

                Text(store.t("Find their personality.", "找到角色的个性。"))
                    .font(.system(size: headingSize, weight: .bold, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.isHeader)
                    .craftEntrance(1)

                if let prompt = project?.prompt, !prompt.isEmpty {
                    promptChip(prompt).craftEntrance(3)
                }

                if let project, !project.concepts.isEmpty {
                    carousel(project).craftEntrance(4, style: .reveal).id(Self.artworkAnchor)
                }

                if let concept = selected {
                    conceptDetails(concept)
                    if let project { thumbnails(project) }
                    if let job = selectedModelJob, job.status == "done", submittingConceptID == nil,
                       let asset = job.assets.first, let url = asset.modelURL {
                        finishedPreview(asset, url: url)
                    }
                    refineSection()
                } else if project?.concepts.isEmpty == false {
                    Label(store.t("Select a photo or concept above to continue to 3D.",
                                  "请先选择上方的原图或概念图，再生成 3D。"),
                          systemImage: "hand.tap")
                        .foregroundStyle(.secondary)
                        .craftPanel()
                        .craftEntrance(5)
                }

                ForEach(jobs.filter { $0.isActive }) { job in journey(job) }
                if let job = selectedModelJob, !job.isActive {
                    DisclosureGroup(store.t("Your 3D generation journey", "这次 3D 的生成过程")) { journey(job) }
                        .font(.subheadline).tint(appearance.ink)
                }

                ForEach(jobs.flatMap(\.assets)) { asset in
                    Button { store.path.append(.asset(asset)) } label: {
                        HStack {
                            Image(systemName: asset.isAnimated ? "film.stack" : "cube.fill").foregroundStyle(appearance.ink)
                            Text(store.t(asset.isAnimated ? "Open character animation" : "Open finished 3D asset",
                                         asset.isAnimated ? "查看角色动画" : "查看已完成的 3D 资产"))
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                        }
                        .craftPanel()
                    }
                    .buttonStyle(CraftPressStyle())
                    .craftEntrance(7)
                }

                if let latest = jobs.first(where: { $0.kind != "model" }), !latest.isActive {
                    if let warnings = latest.warnings, !warnings.isEmpty {
                        DisclosureGroup {
                            Text(warnings.joined(separator: "\n"))
                                .font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                        } label: {
                            Label(store.t("Review view consistency before combining", "组合视角前检查一致性"),
                                  systemImage: "exclamationmark.triangle").font(.subheadline)
                        }
                        .tint(appearance.ink)
                        .craftEntrance(8)
                    }
                    DisclosureGroup(store.t("View generation journey", "查看生成过程")) { journey(latest) }
                        .font(.subheadline).tint(appearance.ink)
                        .craftEntrance(8)
                }

                ForEach(jobs.filter { candidate in
                    (candidate.status == "failed" || candidate.status == "partial")
                        && jobs.first(where: { $0.kind == candidate.kind })?.id == candidate.id
                }) { job in
                    VStack(alignment: .leading, spacing: 10) {
                        Label(job.status == "partial"
                                ? store.t("Saved views are ready. Unused Tokens were returned.",
                                          "已保存的视角可以使用，未使用额度已退回。")
                                : store.t("This attempt could not finish. Your source is saved and unused Tokens were returned.",
                                          "本次生成未完成。源图已保存，未使用额度已退回。"),
                              systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                        if job.status == "failed", job.usedAtlas,
                           let source = project?.concepts.first(where: { $0.id == job.selectedConceptId }) {
                            Button {
                                if job.kind == "animation" {
                                    preferredAnimationModel = "minimax-h3"
                                    animateSource = source
                                } else if job.kind == "model" {
                                    preferredModelEngine = "rodin"
                                    modelSource = source
                                }
                            } label: {
                                Label(store.t(job.kind == "animation" ? "Choose fal animation model" : "Choose fal 3D model",
                                              job.kind == "animation" ? "选择 fal 动画模型" : "选择 fal 3D 模型"),
                                      systemImage: "arrow.triangle.branch")
                            }
                            .buttonStyle(CraftSecondary())
                            .disabled(store.busy || active)
                            .accessibilityIdentifier("generation.chooseFal")
                        }
                    }
                    .craftPanel()
                        .craftEntrance(9)
                }
            }
            .padding(.horizontal, 22).padding(.vertical, 12)
            .frame(maxWidth: 650).frame(maxWidth: .infinity)
            .craftScrollProbe()
        }
        .onChange(of: project?.concepts.map(\.id) ?? []) { previous, current in
            guard let arrived = current.first(where: { !previous.contains($0) }) else { return }
            // Reveal the first result of this request. Later angles must not
            // pull the carousel away while the user inspects or selects it.
            let requestID = jobs.first(where: { $0.kind != "model" })?.id ?? "initial"
            guard revealedImageJobs.insert(requestID).inserted else { return }
            centeredConceptID = arrived
            withAnimation(CraftMotion.gated(.glide, reduceMotion)) {
                proxy.scrollTo(Self.artworkAnchor, anchor: .top)
            }
        }
        .onChange(of: submittingConceptID) { _, id in
            guard id != nil else { return }
            withAnimation(CraftMotion.gated(.glide, reduceMotion)) {
                proxy.scrollTo(Self.artworkAnchor, anchor: .top)
            }
        }
        }
        .onPreferenceChange(CraftScrollOffsetKey.self) { scrollY = $0 }
        .background { StudioAtmosphere(intensity: 1.0, scrollProgress: min(1, Double(scrollY) / 600)) }
        .navigationTitle(store.t("Concept studio", "概念工作室")).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 2) {
                    CreationCostButton(projectID: projectID)
                    Button { settingsOpen = true } label: {
                        Image(systemName: "slider.horizontal.3").frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel(store.t("Concept settings", "概念图设置"))
                    .accessibilityIdentifier("concept.settings")
                }
            }
        }
        .onAppear { revealFinishedModel() }
        .onChange(of: modelCompletionRevision) { _, _ in revealFinishedModel() }
        .onChange(of: scenePhase) { _, _ in revealFinishedModel() }
        .onChange(of: store.path) { _, _ in revealFinishedModel() }
        .onChange(of: inspectImage) { _, _ in revealFinishedModel() }
        .onChange(of: settingsOpen) { _, _ in revealFinishedModel() }
        .craftFeedback(.cardSelect, trigger: selected?.id)
        .craftFeedback(.optionSelect, trigger: browseTick)
        .task {
            // Arriving here *is* the advance from Idea to Concept, so let the
            // rail draw it once instead of presenting it already finished.
            guard stepShown == 0 else { return }
            if reduceMotion || voiceOver { stepShown = 1; return }
            try? await Task.sleep(nanoseconds: 380_000_000)
            stepShown = 1
        }
        .safeAreaInset(edge: .bottom) {
            Group {
                if let concept = selected { generateBar(concept) }
            }
            .animation(CraftMotion.gated(.cinema, reduceMotion), value: selected?.id)
        }
        .fullScreenCover(isPresented: $inspectImage) {
            if let selected, let url = URL(string: selected.imageUrl) {
                ConceptImageInspector(imageURL: url, chinese: store.isChinese)
                    .craftEntrance(0, style: .reveal)
            }
        }
        .sheet(item: $modelSource, onDismiss: { preferredModelEngine = "tripo" }) { source in
            ModelGenerationSheet(concept: source, chinese: store.isChinese,
                                 relatedViews: checkedViews(for: source),
                                 offersMultiView: !checkedViews(for: source).isEmpty,
                                 suggestedEngine: preferredModelEngine) { engine, quality, effort, ids, prompt in
                modelSource = nil
                centeredConceptID = source.id
                submittingConceptID = source.id
                let previousJobs = Set(jobs.map(\.id))
                Task {
                    await store.generateModel(source, engine: engine, quality: quality, effort: effort, conceptIds: ids, modelPrompt: prompt)
                    submittingConceptID = nil
                    // Also catch a fast completion returned by the first refresh.
                    watchedModelJobs.formUnion(jobs.filter { $0.kind == "model" && !previousJobs.contains($0.id) }.map(\.id))
                    revealFinishedModel()
                }
            }
        }
        .sheet(item: $animateSource, onDismiss: { preferredAnimationModel = "atlas-minimax-h3" }) { source in
            AnimationGenerationSheet(concept: source, chinese: store.isChinese,
                                     suggestedModel: preferredAnimationModel) { model, motion, resolution, duration in
                animateSource = nil
                centeredConceptID = source.id
                submittingConceptID = source.id
                Task {
                    await store.generateAnimation(source, model: model, motion: motion, resolution: resolution, duration: duration)
                    submittingConceptID = nil
                }
            }
        }
        .sheet(isPresented: $settingsOpen) { conceptSettings }
        .confirmationDialog(store.t("Create a refined concept for \(store.conceptTokenCost(count: 1)) Tokens?", "使用 \(store.conceptTokenCost(count: 1)) Tokens 生成修改后的概念图？"),
                            isPresented: $confirmRefine, titleVisibility: .visible) {
            Button(store.t("Refine concept", "修改概念图")) {
                if let selected { Task { await store.refine(selected, prompt: refinement); refinement = "" } }
            }
        }
    }

    // MARK: - The prompt chip

    private func promptChip(_ prompt: String) -> some View {
        HStack(spacing: 12) {
            Text(prompt)
                .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 44)
        .frame(maxWidth: .infinity, alignment: .leading)
        .craftSurface(.sunken, cornerRadius: 18)
    }

    // MARK: - The carousel

    private func carousel(_ project: CraftProject) -> some View {
        GeometryReader { geometry in
            let cardWidth = min(geometry.size.width - 72, 300)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(project.concepts) { concept in
                        card(concept, width: cardWidth)
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 10)
            }
            .contentMargins(.horizontal, (geometry.size.width - cardWidth) / 2, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .accessibilityIdentifier("concept.carousel")
            .scrollPosition(id: $centeredConceptID, anchor: .center)
            .onAppear { centeredConceptID = selected?.id }
            .onChange(of: selected?.id) { _, id in
                centeredConceptID = id
            }
            .onChange(of: centeredConceptID) { _, id in
                // Settling on a card the user has not chosen yet is browsing,
                // not choosing: it ticks, it never selects.
                if let id, id != selected?.id { browseTick += 1 }
            }
        }
        .frame(height: cardHeight + 22)
    }

    private func card(_ concept: CraftConcept, width: CGFloat) -> some View {
        let isSelected = selected?.id == concept.id
        let sourceJob = ConceptModelActivity.latestJob(for: concept, jobs: jobs)
        return Button {
            store.selectConcept(concept)
            // Recenter even when the selected card is tapped again after browsing.
            withAnimation(CraftMotion.gated(.snap, reduceMotion, reduced: nil)) {
                centeredConceptID = concept.id
            }
        } label: {
            AsyncImage(url: URL(string: concept.imageUrl)) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit().padding(10)
                } else if phase.error != nil {
                    Label(store.t("Image unavailable", "图片不可用"), systemImage: "photo.badge.exclamationmark")
                        .font(.caption)
                } else {
                    // One shimmer at a time: only the card being looked at.
                    Color.clear.craftShimmer(active: centeredConceptID == concept.id,
                                             cornerRadius: 26, base: appearance.washSoft)
                }
            }
            .frame(width: width, height: cardHeight)
            .background(isSelected ? appearance.wash : appearance.washSoft,
                        in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(alignment: .topTrailing) { checkBadge(isSelected).padding(14) }
            .overlay {
                if ConceptModelActivity.isWorking(on: concept, jobs: jobs, submittingID: submittingConceptID) {
                    ConceptReconstructionOverlay(job: sourceJob?.isActive == true ? sourceJob : nil,
                                                 chinese: store.isChinese)
                }
            }
            .craftSelectionRing(isSelected, color: appearance.fill, cornerRadius: 26)
        }
        .buttonStyle(CraftLiftStyle(scale: 1.02))
        .id(concept.id)
        .accessibilityIdentifier("concept.select." + concept.id)
        .accessibilityLabel(label(concept))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .craftCarouselItem(scale: 0.12, dim: 0.36, yaw: 8, blur: 2)
    }

    private func thumbnails(_ project: CraftProject) -> some View {
        GeometryReader { geometry in
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(project.concepts) { concept in
                        let isSelected = selected?.id == concept.id
                        Button {
                            store.selectConcept(concept)
                            withAnimation(CraftMotion.gated(.snap, reduceMotion, reduced: nil)) {
                                centeredConceptID = concept.id
                            }
                        } label: {
                            AsyncImage(url: URL(string: concept.imageUrl)) { phase in
                                if let image = phase.image {
                                    image.resizable().scaledToFit().padding(3)
                                } else {
                                    Image(systemName: "photo").foregroundStyle(appearance.ink)
                                }
                            }
                            .frame(width: 86, height: 72)
                            .background(appearance.washSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 13))
                            .overlay(RoundedRectangle(cornerRadius: 13)
                                .strokeBorder(isSelected ? appearance.fill : Color.clear, lineWidth: 2))
                        }
                        .buttonStyle(CraftPressStyle())
                        .id(concept.id)
                        .accessibilityLabel(label(concept))
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .accessibilityIdentifier("concept.thumbnail." + concept.id)
                    }
                }
                .padding(.horizontal, 3)
                .padding(.vertical, 3)
                .frame(minWidth: geometry.size.width)
            }
            .onAppear {
                if let id = selected?.id { proxy.scrollTo(id, anchor: .center) }
            }
            .onChange(of: selected?.id) { _, id in
                guard let id else { return }
                withAnimation(CraftMotion.gated(.glide, reduceMotion)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
        }
        .frame(height: 78)
        .accessibilityIdentifier("concept.thumbnails")
    }

    /// The mockup's filled accent disc with a plain checkmark. Always present, so
    /// it scales in on `pop` without a transition fighting the scroll phase.
    private func checkBadge(_ isSelected: Bool) -> some View {
        ZStack {
            Circle().fill(appearance.gradient)
                .shadow(color: appearance.deep.opacity(0.34), radius: 8, y: 3)
            Image(systemName: "checkmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(appearance.buttonInk)
                .craftSymbolPop(isSelected, reduceMotion: reduceMotion)
        }
        .frame(width: 34, height: 34)
        .scaleEffect(isSelected || reduceMotion ? 1 : 0.5)
        .opacity(isSelected ? 1 : 0)
        .animation(CraftMotion.gated(.pop, reduceMotion), value: isSelected)
        .accessibilityHidden(true)
    }

    // MARK: - The chosen concept

    private func conceptDetails(_ concept: CraftConcept) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button { inspectImage = true } label: {
                HStack(spacing: 6) {
                    Text(label(concept))
                        .font(.subheadline.weight(.medium))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "arrow.up.left.and.arrow.down.right").font(.caption2)
                }
                .foregroundStyle(appearance.ink)
                .frame(minHeight: 44)
            }
            .buttonStyle(CraftPressStyle())
            .accessibilityIdentifier("concept.inspect")
            .accessibilityLabel(store.t("Explore the details: ", "查看细节：") + label(concept))
            Spacer(minLength: 0)
            Button {
                withAnimation(CraftMotion.gated(.glide, reduceMotion)) { refineOpen.toggle() }
            } label: {
                Label(store.t("Refine", "调整"), systemImage: "slider.horizontal.3")
                    .font(.subheadline)
                    .fixedSize()
                    .frame(minHeight: 44)
            }
            .buttonStyle(CraftPressStyle())
            .foregroundStyle(appearance.ink)
            .accessibilityLabel(store.t("Refine this concept", "调整这张概念图"))
            .accessibilityIdentifier("concept.refine")
        }
        .frame(maxWidth: .infinity)
        .animation(CraftMotion.gated(.glide, reduceMotion), value: concept.id)
    }

    @ViewBuilder private func refineSection() -> some View {
        if refineOpen {
            VStack(alignment: .leading, spacing: 12) {
                Text(store.t("Refine the selected image", "调整选中的图片")).font(.headline)
                TextField(store.t("Describe the changes to this image…", "描述对这张图的修改……"),
                          text: $refinement, axis: .vertical)
                    .lineLimit(2...4)
                if store.showPriceDetails { Text(store.conceptPriceSummary(count: 1)).font(.caption).foregroundStyle(.secondary) }
                Button(store.t("Refine · \(store.conceptTokenCost(count: 1)) Tokens", "修改 · \(store.conceptTokenCost(count: 1)) Tokens")) { confirmRefine = true }
                    .buttonStyle(CraftSecondary())
                    .opacity(refineReady ? 1 : 0.5)
                    .disabled(!refineReady)
            }
            .craftPanel(22)
            .transition(.opacity)
        }
    }

    private var conceptSettings: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let selected {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(label(selected)).font(.headline)
                            Text(store.t("Your selected image becomes the 3D source.", "你选中的图片将作为 3D 源图。"))
                                .font(.caption).foregroundStyle(.secondary)
                            if let model = selected.imageModel {
                                Text(CraftImageModel.displayName(for: model))
                                    .font(.caption).foregroundStyle(appearance.ink)
                            }
                        }
                    }
                    PlannerModelPicker().disabled(store.busy || active)
                    ImageModelPicker().disabled(store.busy || active)
                    PricingDetailsToggle()
                    if store.showPriceDetails {
                        Text(store.conceptPriceSummary(count: 4)).font(.caption).foregroundStyle(.secondary)
                    }
                    Button(store.t("Create 4 candidate views · \(store.conceptTokenCost(count: 4)) Tokens", "生成 4 张视角概念图 · \(store.conceptTokenCost(count: 4)) Tokens")) {
                        confirmMore = true
                    }
                    .buttonStyle(CraftSecondary())
                    .disabled(store.busy || active)
                    .accessibilityIdentifier("concept.createMore")
                }
                .padding(22)
            }
            .background { StudioAtmosphere(intensity: 0.8) }
            .navigationTitle(store.t("Concept settings", "概念图设置"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.t("Done", "完成")) { settingsOpen = false }
                        .accessibilityIdentifier("concept.settings.done")
                }
            }
            .confirmationDialog(store.t("Generate 4 candidate views for \(store.conceptTokenCost(count: 4)) Tokens?", "使用 \(store.conceptTokenCost(count: 4)) Tokens 生成 4 张视角概念图？"),
                                isPresented: $confirmMore, titleVisibility: .visible) {
                Button(store.t("Generate concepts", "生成概念图")) {
                    settingsOpen = false
                    Task { await store.addConcepts(to: projectID, count: 4) }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .tint(appearance.ink)
        .craftAmbientHost()
    }

    // MARK: - The bottom bar

    private func finishedPreview(_ asset: CraftAsset, url: URL) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(store.t("Your 3D is ready", "你的 3D 已完成"), systemImage: "checkmark.circle.fill")
                .font(.headline).foregroundStyle(appearance.ink)
            ModelViewport(modelURL: url, chinese: store.isChinese, softStage: true)
                .frame(height: 280)
                .background(appearance.washSoft, in: RoundedRectangle(cornerRadius: 24))
                .clipShape(RoundedRectangle(cornerRadius: 24))
            Button { store.path.append(.asset(asset)) } label: {
                Label(store.t("Explore your 3D", "查看你的 3D"), systemImage: "arrow.up.right")
            }.buttonStyle(CraftSecondary()).accessibilityIdentifier("concept.openFinishedModel")
        }.accessibilityIdentifier("concept.finishedModel")
    }

    private func generateBar(_ concept: CraftConcept) -> some View {
        let working = ConceptModelActivity.isWorking(on: concept, jobs: jobs, submittingID: submittingConceptID)
        return VStack(spacing: 8) {
            Button {
                make3DTaps += 1
                modelSource = concept
            } label: {
                Label(working ? store.t("Creating your 3D…", "正在生成你的 3D……")
                              : store.t("Generate 3D model", "生成 3D 模型"), systemImage: "cube")
            }
            .buttonStyle(CraftPrimary(armed: !store.busy && !active, busy: store.busy, verticalPadding: 14, cornerRadius: 16))
            .disabled(store.busy || active || submittingConceptID != nil)
            .accessibilityIdentifier("concept.make3D")
            Button {
                animateSource = concept
            } label: {
                Label(store.t("Animate this character", "让角色动起来"), systemImage: "wand.and.stars")
            }
            .buttonStyle(CraftSecondary())
            .disabled(store.busy || submittingConceptID != nil)
            .accessibilityIdentifier("concept.animate")
            Text(store.t("Choose a model to see its Token cost before generating.", "选择模型后确认对应的 Token 费用。"))
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 8)
        .frame(maxWidth: 650).frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 28, bottomLeadingRadius: 0,
                                   bottomTrailingRadius: 0, topTrailingRadius: 28,
                                   style: .continuous)
                .fill(Color.white)
                .craftDepth(.floating)
                .ignoresSafeArea(edges: .bottom)
        }
        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        .craftFeedback(.primaryAction, trigger: make3DTaps)
    }

    // MARK: - Data

    private func label(_ concept: CraftConcept) -> String {
        if concept.isOriginal == true { return store.t("Original · Direct 3D", "原图 · 直接生成 3D") }
        let titles = ["front": store.t("Front", "正面"), "back": store.t("Back", "背面"),
                      "left": store.t("Left", "左侧"), "right": store.t("Right", "右侧")]
        return concept.direction.flatMap { titles[$0] } ?? concept.label ?? concept.name
    }

    private func checkedViews(for concept: CraftConcept) -> [CraftConcept] {
        guard concept.isOriginal != true,
              let job = jobs.first(where: {
                  $0.viewsUsable == true && $0.status == "done"
                      && ($0.concepts ?? []).contains { $0.id == concept.id }
              })
        else { return [] }
        return (job.concepts ?? []).filter {
            $0.isOriginal != true && ["front", "back", "left", "right"].contains($0.direction ?? "")
        }
    }

    private func journey(_ job: CraftJob) -> some View {
        GenerationJourneyView(
            job: job,
            sourceURL: project?.imageUrl.flatMap(URL.init(string:)),
            selectedConceptURL: job.kind == "model"
                ? job.selectedImageUrl.flatMap(URL.init(string:))
                : (job.concepts?.first?.imageUrl).flatMap(URL.init(string:)),
            chinese: store.isChinese,
            coreConcept: job.coreConcept,
            stage: job.stage)
    }
}
