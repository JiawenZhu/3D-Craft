import SwiftUI
import UIKit

/// Confirm the selected source and settings, with provider cost estimates
/// displayed separately from the existing app Token reservation.
struct ModelGenerationSheet: View {
    @EnvironmentObject private var store: CraftStore
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    let concept: CraftConcept
    let chinese: Bool
    var relatedViews: [CraftConcept] = []
    var offersMultiView: Bool = false
    let onGenerate: (_ engine: String, _ quality: String, _ effort: String, _ selectedIDs: [String], _ prompt: String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var engine = "rodin"
    @State private var quality = "default"
    @State private var effort = "high"
    @State private var imageReady = false
    @State private var previewImage: UIImage?
    @State private var previewLoading = true
    @State private var previewAttempt = UUID()
    @State private var submitted = false
    @State private var useMultiView = false
    @State private var checkedIDs: Set<String> = []
    @State private var submitCount = 0
    @State private var scrollY: CGFloat = 0
    @State private var modelPrompt = ""
    @FocusState private var promptFocused: Bool
    @State private var improvingPrompt = false
    @State private var promptMaxTokens: Int?
    @State private var promptSuggestion: String?
    @State private var promptImprovementError: String?
    @State private var promptTask: Task<Void, Never>?

    private let canvas = Color.white
    private var lilac: Color { appearance.ink }
    private let coral = Color(red: 0.65, green: 0.19, blue: 0.12)
    private func t(_ en: String, _ zh: String) -> String { chinese ? zh : en }
    private var imageURL: URL? {
        guard let url = URL(string: concept.imageUrl), ["http", "https", "file"].contains(url.scheme ?? "") else { return nil }
        return url
    }
    private var eligibleViews: [CraftConcept] {
        var seenIDs: Set<String> = []
        var seenDirections: Set<String> = []
        return ([concept] + relatedViews).filter { view in
            guard seenIDs.insert(view.id).inserted else { return false }
            if ["hunyuan3d-2.1","hunyuan3d-2-white","hybrid"].contains(engine) {
                guard let direction = view.direction?.lowercased(), ["front", "back", "left"].contains(direction), seenDirections.insert(direction).inserted else { return false }
            }
            return true
        }
    }
    private var supportsMultiView: Bool {
        guard offersMultiView, eligibleViews.contains(where: { $0.id == concept.id }) else { return false }
        return ["hunyuan3d-2.1","hunyuan3d-2-white","hybrid"].contains(engine) ? eligibleViews.count == 3 : eligibleViews.count >= 2
    }
    private var selectedIDs: [String] {
        guard useMultiView && supportsMultiView else { return [] }
        return eligibleViews.filter { $0.id == concept.id || checkedIDs.contains($0.id) }.map(\.id)
    }
    private var selectionValid: Bool {
        guard useMultiView else { return true }
        return supportsMultiView && (["hunyuan3d-2.1","hunyuan3d-2-white","hybrid"].contains(engine) ? selectedIDs.count == 3 : (2...5).contains(selectedIDs.count))
    }
    private var tokenCost: Int? { store.modelTokenCost(engine, views: max(1, selectedIDs.count), effort: effort) }
    private var tokenLabel: String { store.modelTokenLabel(engine, views: max(1, selectedIDs.count), effort: effort) }
    private var supportsPrompt: Bool { engine == "rodin" }
    private var trimmedPrompt: String { modelPrompt.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var promptValid: Bool { modelPrompt.unicodeScalars.count <= 800 && (supportsPrompt || trimmedPrompt.isEmpty) }
    private var ready: Bool { imageReady && !submitted && !improvingPrompt && selectionValid && tokenCost != nil && promptValid }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    headline
                    sourceCard
                    settingsCard
                    promptCard
                    costCard
                    if tokenCost == nil {
                        Text(t("Pricing for these views is not confirmed. Select one image or choose another model.", "这些视角的价格尚未确认，请选择单张图片或其他模型。"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    PricingDetailsToggle()
                    CreationCostButton(projectID: concept.projectId, imageCount: 0, iconOnly: false)
                }
                .padding(22)
                .craftScrollProbe()
            }
            .onPreferenceChange(CraftScrollOffsetKey.self) { scrollY = $0 }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) { bottomBar }
            .background { StudioAtmosphere(intensity: 1.15, scrollProgress: min(1, Double(scrollY) / 600)) }
            .navigationTitle(t("Confirm 3D generation", "确认生成 3D"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button(t("Cancel", "取消")) { dismiss() }.foregroundStyle(.secondary) } }
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button(t("Done", "完成")) { promptFocused = false } } }
            .onChange(of: engine) { _, _ in
                if !supportsMultiView { useMultiView = false }
                checkedIDs = Set(eligibleViews.prefix(5).map(\.id))
            }
            .onChange(of: useMultiView) { _, enabled in
                if enabled { checkedIDs = Set(eligibleViews.prefix(5).map(\.id)) }
            }
        }
        .preferredColorScheme(.light)
        .craftFeedback(.primaryAction, trigger: submitCount)
        .craftFeedback(.modelReady, trigger: imageReady)
        .craftAmbientHost()
        .task(id: store.plannerModelID) {
            promptMaxTokens = nil
            promptImprovementError = nil
            if modelPrompt.isEmpty, let pending = store.pendingModelPromptText(concept.id) { modelPrompt = pending }
            do { promptMaxTokens = try await store.modelPromptQuote() }
            catch { promptImprovementError = error.localizedDescription }
        }
        .onDisappear { promptTask?.cancel() }
    }

    // MARK: - Sections

    private var headline: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 8) {
                Text(t("Your concept.\nThe next dimension.", "你的概念，\n即将成为三维。"))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .craftEntrance(0)
                Text(t("Start with your image. Add directions with Rodin.", "以图片为起点，使用 Rodin 添加文字描述。"))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .craftEntrance(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            CraftAccentCube(size: 36, period: 6.7, delay: 0.3)
                .offset(x: 2, y: -4)
                .craftParallax(0.22, offset: scrollY)
                .craftEntrance(2, style: .popIn)
        }
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            preview
                .frame(maxWidth: .infinity).frame(height: 270)
                .background(appearance.washSoft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .craftShimmer(active: !imageReady, cornerRadius: 20, base: appearance.washSoft)
                .id(previewAttempt)

            Text(concept.name).font(.headline)

            HStack(spacing: 9) {
                Image(systemName: "photo.badge.checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(lilac)
                    .frame(width: 26, height: 26)
                    .background(appearance.washSoft, in: Circle())
                    .craftSymbolPop(imageReady, reduceMotion: reduceMotion)
                    .accessibilityHidden(true)
                Text(t("Selected source · Preserved for this generation", "已选来源 · 本次生成将保留此参考"))
                    .font(.caption).foregroundStyle(lilac)
            }
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .craftDepth(.raised)
        .craftEntrance(3, style: .reveal)
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text(t("Generation settings", "生成设置")).font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                settingLabel(t("3D engine", "3D 引擎"), icon: "cube.transparent")
                Picker(t("3D engine", "3D 引擎"), selection: $engine) {
                    Text("Rodin (Ultra) · " + store.modelTokenLabel("rodin", views: max(1, selectedIDs.count), effort: effort) + (store.showPriceDetails ? " · " + store.modelPriceLabel("rodin", views: max(1, selectedIDs.count), effort: effort) : "")).tag("rodin")
                    Text("TRELLIS.2 · " + store.modelTokenLabel("trellis-2", views: max(1, selectedIDs.count), effort: effort) + (store.showPriceDetails ? " · " + store.modelPriceLabel("trellis-2", views: max(1, selectedIDs.count), effort: effort) : "")).tag("trellis-2")
                    Text(t("Hunyuan 2 · Textured · ", "Hunyuan 2 · 带纹理 · ") + store.modelTokenLabel("hunyuan3d-2.1", views: max(1, selectedIDs.count), effort: effort) + (store.showPriceDetails ? " · " + store.modelPriceLabel("hunyuan3d-2.1", views: max(1, selectedIDs.count), effort: effort) : "")).tag("hunyuan3d-2.1")
                    Text(t("Hunyuan 2 · White mesh · ", "Hunyuan 2 · 白模 · ") + store.modelTokenLabel("hunyuan3d-2-white", views: max(1, selectedIDs.count), effort: effort) + (store.showPriceDetails ? " · " + store.modelPriceLabel("hunyuan3d-2-white", views: max(1, selectedIDs.count), effort: effort) : "")).tag("hunyuan3d-2-white")
                    if store.cloudModelEngineIDs.contains("hybrid") {
                        Text("Hybrid · " + store.modelTokenLabel("hybrid", views: max(1, selectedIDs.count), effort: effort) + (store.showPriceDetails ? " · " + store.modelPriceLabel("hybrid", views: max(1, selectedIDs.count), effort: effort) : "")).tag("hybrid")
                    }
                }.pickerStyle(.menu).tint(lilac).frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("modelEnginePicker")
            }

            if engine == "hunyuan3d-2-white" {
                Text(t("White mesh · geometry only, without color or texture.", "白模 · 仅生成几何形状，不含颜色或纹理。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if offersMultiView {
                Divider().opacity(0.4)
                Toggle(t("Use checked views", "使用已勾选视角"), isOn: $useMultiView)
                    .font(.subheadline.weight(.medium))
                    .tint(lilac).disabled(!supportsMultiView)
                if useMultiView && supportsMultiView {
                    Text(["hunyuan3d-2.1", "hunyuan3d-2-white", "hybrid"].contains(engine)
                         ? t("3 views: front + back + left → one 3D object", "3 张视图：正面＋背面＋左侧 → 一个 3D 物体")
                         : t("Multiple views of one object → one 3D object", "同一物体的多个视角 → 一个 3D 物体"))
                        .font(.caption.weight(.medium)).foregroundStyle(lilac)
                    if ["trellis-2", "hybrid"].contains(engine) {
                        Text(t("Multi-view uses 1024p resolution.", "多视角使用 1024p 分辨率。"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(spacing: 9) {
                        ForEach(Array(eligibleViews.enumerated()), id: \.element.id) { index, view in
                            let primary = view.id == concept.id
                            let checked = primary || checkedIDs.contains(view.id)
                            Toggle(isOn: Binding(get: { checked }, set: { on in
                                if on { checkedIDs.insert(view.id) } else { checkedIDs.remove(view.id) }
                            })) {
                                HStack(spacing: 10) {
                                    CraftCachedImage(url: URL(string: view.imageUrl))
                                        .frame(width: 46, height: 46)
                                        .background(appearance.washSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(view.direction.map { directionLabel($0) } ?? view.name).font(.subheadline)
                                        if primary { Text(t("Selected source · Always included", "已选来源 · 始终包含")).font(.caption2).foregroundStyle(.secondary) }
                                    }
                                }
                            }
                            .disabled(primary).tint(lilac)
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(checked ? appearance.washSoft : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .animation(CraftMotion.gated(.snap, reduceMotion), value: checked)
                            .craftEntrance(index, step: 0.05)
                        }
                    }
                    .transition(.opacity)
                    if !selectionValid {
                        Label(["hunyuan3d-2.1","hunyuan3d-2-white","hybrid"].contains(engine) ? t("Select front, back, and left views together.", "请同时选择正面、背面和左侧视图。") : t("Select between 2 and 5 views, including the source.", "请选择 2 到 5 个视角，包含已选来源。"),
                              systemImage: "exclamationmark.circle")
                            .font(.caption).foregroundStyle(coral)
                            .transition(.opacity)
                    }
                }
                Text(supportsMultiView
                     ? t("Only the reviewed view set is available. All checked images must show the same single subject.", "仅提供已检查的视角组。所有勾选图片必须是同一个单独主体。")
                     : t("This source does not have the required checked views for this engine. Single-image generation will be used.", "此来源缺少该引擎所需的已检查视角，将使用单图生成。"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Divider().opacity(0.4)

            settingLabel(t("Quality mode", "质量模式"), icon: "slider.horizontal.3")
            CraftSegmented(options: [.init("default", t("Default", "标准")),
                                     .init("speedy", t("Speedy", "快速"))],
                           selection: $quality, height: 44)
            Text(quality == "speedy"
                 ? t("A quicker pass with reduced generation settings. Fine details may be less defined.", "使用较低生成参数加快处理，精细细节可能减少。")
                 : t("Uses the engine's regular generation mode.", "使用引擎的常规生成模式。"))
                .font(.caption).foregroundStyle(.secondary)
                .contentTransition(.opacity)
                .animation(CraftMotion.gated(.brush, reduceMotion), value: quality)

            Divider().opacity(0.4)

            HStack {
                settingLabel(t("Detail effort", "细节精度"), icon: "sparkles")
                Spacer()
                Picker(t("Detail effort", "细节精度"), selection: $effort) {
                    Text(t("Extra low", "极低")).tag("extreme-low")
                    Text(t("Low", "低")).tag("low")
                    Text(t("Medium", "中")).tag("medium")
                    Text(t("High", "高")).tag("high")
                    Text(t("Extra high", "极高")).tag("extreme-high")
                }.pickerStyle(.menu).tint(lilac)
            }
            Text(t("Higher effort may take longer. Available detail depends on the engine; it does not guarantee a perfect mesh. Engine availability is checked when you submit.", "更高精度可能需要更长时间，实际细节取决于引擎，不保证模型完全无瑕疵。提交时会检查引擎是否可用。"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .craftDepth(.card)
        .animation(CraftMotion.gated(.glide, reduceMotion), value: useMultiView)
        .animation(CraftMotion.gated(.glide, reduceMotion), value: selectionValid)
        .craftEntrance(4)
    }

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(t("3D prompt", "3D 描述"), systemImage: "text.bubble")
                .font(.headline)
            if supportsPrompt {
                Text(t("Optional · Your image and these words guide Rodin together.", "选填 · Rodin 会同时参考图片和这里的文字。"))
                    .font(.subheadline).foregroundStyle(.secondary)
                TextField(t("Describe the shape, appearance, or layout you want…", "描述你想要的形状、外观或空间布局……"), text: $modelPrompt, axis: .vertical)
                    .lineLimit(4...8).focused($promptFocused)
                    .padding(14).background(appearance.washSoft, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityIdentifier("modelPromptField")
                HStack {
                    if let original = store.projects.first(where: { $0.id == concept.projectId })?.prompt,
                       !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button(t("Use original description", "使用原始描述")) { modelPrompt = original }
                            .disabled(!trimmedPrompt.isEmpty)
                    }
                    Spacer()
                    Text("\(modelPrompt.unicodeScalars.count)/800")
                        .foregroundStyle(modelPrompt.unicodeScalars.count > 800 ? coral : .secondary)
                }.font(.caption)
                PlannerModelPicker().disabled(improvingPrompt)
                Button {
                    guard let promptMaxTokens else { return }
                    promptFocused = false
                    improvingPrompt = true; promptImprovementError = nil; promptSuggestion = nil
                    let original = modelPrompt
                    promptTask = Task { @MainActor in
                        defer { improvingPrompt = false }
                        do {
                            let suggestion = try await store.improveModelPrompt(concept, text: original, maxTokens: promptMaxTokens)
                            guard !Task.isCancelled else { return }
                            promptSuggestion = suggestion
                        } catch {
                            guard !Task.isCancelled else { return }
                            promptImprovementError = error.localizedDescription
                        }
                    }
                } label: {
                    HStack {
                        if improvingPrompt { ProgressView() }
                        Label(improvingPrompt ? t("Improving prompt…", "正在优化描述……") : t("Improve with AI", "用 AI 优化描述"), systemImage: "sparkles")
                    }
                }.disabled(improvingPrompt || promptMaxTokens == nil || !imageReady || modelPrompt.unicodeScalars.count > 4000)
                    .accessibilityIdentifier("modelImprovePrompt")
                if let promptMaxTokens {
                    Text(t("Up to \(promptMaxTokens) Tokens · charged by actual usage; unused reservation returned.", "最多 \(promptMaxTokens) Token · 按实际用量结算，未使用的预留会退回。"))
                        .font(.caption).foregroundStyle(appearance.ink)
                }
                Text(t("Uses your selected planning model and this image. Review the suggestion before using it. This does not start 3D generation.", "使用你选择的规划模型和这张图片。请先检查建议再采用，不会自动开始 3D 生成。"))
                    .font(.caption).foregroundStyle(.secondary)
                if let promptImprovementError { Text(promptImprovementError).font(.caption).foregroundStyle(coral) }
                if let suggestion = promptSuggestion {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(t("Suggested prompt", "建议描述")).font(.subheadline.bold())
                        Text(suggestion).font(.subheadline).textSelection(.enabled)
                        HStack {
                            Button(t("Use this prompt", "采用此描述")) { modelPrompt = suggestion; promptSuggestion = nil }
                                .accessibilityIdentifier("modelAcceptPrompt")
                            Spacer()
                            Button(t("Keep mine", "保留原文")) { promptSuggestion = nil }
                        }.font(.subheadline.weight(.semibold))
                    }.padding(14).background(appearance.washSoft, in: RoundedRectangle(cornerRadius: 16))
                }
                Text(t("For example: keep the swing’s frame and canopy, with a seat sized for a game character. Swinging motion is added when you build the game.", "例如：保留秋千的支架和顶棚，座椅留出游戏角色乘坐的空间。摆动效果在制作游戏时添加。"))
                    .font(.caption).foregroundStyle(.secondary)
                Text(t("For faces, describe the visible features you want to preserve. An exact likeness is not guaranteed.", "人物可描述需要保留的可见面部特征，但无法保证完全还原本人。"))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(t("This model follows images only. Edit your concept image first, or use Rodin to combine images with written directions.", "此模型仅参考图片。请先修改概念图，或使用 Rodin 同时参考图片与文字描述。"))
                    .font(.subheadline).foregroundStyle(.secondary)
                Button(t("Use Rodin · Image + prompt", "使用 Rodin · 图片＋文字")) { engine = "rodin" }
                    .accessibilityIdentifier("modelUsePromptEngine")
                if !trimmedPrompt.isEmpty {
                    Text(t("Your written directions are still here. Choose Rodin to apply them, or clear them to continue with images only.", "你的文字描述仍然保留。请选择 Rodin 应用这些描述，或清空后仅使用图片生成。"))
                        .font(.caption).foregroundStyle(coral)
                    Button(t("Clear prompt · Use images only", "清空描述 · 仅使用图片")) { modelPrompt = "" }
                }
            }
            if modelPrompt.unicodeScalars.count > 800 {
                Text(t("Shorten the prompt to 800 characters before generating.", "请将描述缩短至 800 字以内再生成。"))
                    .font(.caption).foregroundStyle(coral)
            }
        }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 26))
            .craftDepth(.card)
    }

    private var costCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "circle.hexagongrid.fill")
                .foregroundStyle(lilac).font(.title3)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.75), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(engine == "hunyuan3d-2-white" ? t("One white mesh · No texture", "一个白模 · 不含纹理") : t("One textured 3D asset", "一个带纹理 3D 资产")).font(.subheadline.weight(.semibold))
                if store.showPriceDetails {
                Text(t("API estimate: ", "API 成本估算：") + store.modelPriceLabel(engine, views: max(1, selectedIDs.count), effort: effort))
                    .font(.headline).foregroundStyle(lilac).accessibilityIdentifier("pricing.model.total")
                if let price = store.modelPrices[engine] {
                    if let base = (selectedIDs.count > 1 ? price.multiUnitUsd : price.unitUsd), let total = price.modelCost(views: max(1, selectedIDs.count), effort: effort) {
                        Text(t("Base \(CraftModelPrice.usd(base)) + options \(CraftModelPrice.usd(max(0, total - base)))", "基础 \(CraftModelPrice.usd(base)) + 附加选项 \(CraftModelPrice.usd(max(0, total - base)))"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text(chinese ? price.noteZh : price.note).font(.caption).foregroundStyle(.secondary)
                }
                }
                Text(t("App Tokens · Service fee included", "App Tokens · 已含服务费")).font(.caption.weight(.semibold))
                Text(t("The selected model’s provider cost plus service fee, rounded up to whole Tokens. Reserved when you confirm.", "按所选模型成本加服务费计算，向上取整为 Tokens，确认后预留。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text(tokenLabel)
                .font(.title2.bold()).foregroundStyle(lilac)
                .craftNumeric(tokenCost ?? 0, reduceMotion: reduceMotion)
        }
        .padding(18)
        .background(appearance.wash, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(appearance.hairline, lineWidth: 1)
        )
        .craftEntrance(5)
    }

    private var bottomBar: some View {
        Button {
            guard ready else { return }
            submitted = true
            submitCount += 1
            promptFocused = false
            onGenerate(engine, quality, effort, selectedIDs, supportsPrompt ? trimmedPrompt : nil)
            dismiss()
        } label: {
            Label(t("Generate 3D · \(tokenLabel)", "生成 3D · \(tokenLabel)"), systemImage: "cube.transparent")
        }
        .buttonStyle(CraftPrimary(armed: ready, busy: submitted))
        .disabled(!ready)
        .accessibilityIdentifier("confirmModelGeneration")
        .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 14)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 28, bottomLeadingRadius: 0,
                                   bottomTrailingRadius: 0, topTrailingRadius: 28,
                                   style: .continuous)
                .fill(canvas)
                .shadow(color: .black.opacity(0.06), radius: 18, y: -5)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Pieces

    private func directionLabel(_ direction: String) -> String {
        switch direction.lowercased() {
        case "front": return t("Front", "正面")
        case "back": return t("Back", "背面")
        case "left": return t("Left", "左侧")
        case "right": return t("Right", "右侧")
        default: return direction
        }
    }

    private func settingLabel(_ text: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(lilac)
                .frame(width: 30, height: 30)
                .background(appearance.washSoft, in: Circle())
                .accessibilityHidden(true)
            Text(text).font(.subheadline.weight(.medium)).foregroundStyle(.black.opacity(0.85))
        }
    }

    private var preview: some View {
        Group {
            if let previewImage {
                Image(uiImage: previewImage).resizable().scaledToFit()
                    .accessibilityIdentifier("model.sourcePreview")
            } else if previewLoading {
                VStack(spacing: 12) {
                    ProgressView().tint(lilac)
                    Text(t("Loading your selected image…", "正在加载你选中的图片……"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else { previewError }
        }
        .task(id: previewAttempt) {
            imageReady = false; previewImage = nil; previewLoading = true
            let uid = CraftAccount.shared.uid
            let data: Data?
            if let url = imageURL { data = await CraftImageCache.shared.data(for: url) }
            else { data = nil }
            guard !Task.isCancelled, CraftAccount.shared.uid == uid else { return }
            // Use the same authenticated, unmodified-source preview pipeline as
            // the concept card. Never make private images public to display them.
            previewImage = data.flatMap { UIImage(data: $0) }
            imageReady = previewImage != nil
            previewLoading = false
        }
    }

    private var previewError: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.badge.exclamationmark").font(.title2).foregroundStyle(coral)
            Text(t("The selected image could not be loaded. Confirm its preview before generating.", "无法加载所选图片，请先确认图片预览再生成。"))
                .font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button(t("Retry image", "重试加载")) { imageReady = false; previewAttempt = UUID() }.tint(lilac)
        }.padding(20)
    }
}
