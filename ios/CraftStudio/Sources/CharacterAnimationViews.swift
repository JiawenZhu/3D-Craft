import SwiftUI

/// A finished character animation: the character image, then its loop on top.
///
/// The still is the image the animation was made from, so there is something
/// truthful to show under Reduce Motion, before the first frame decodes, and
/// whenever the ambient gate closes.
/// Downloads a character animation once and plays it from disk.
///
/// The clip lives in this account's private Storage, which needs an identity
/// header on every request, and AVPlayer cannot carry one. Fetching it first
/// also means the loop plays from local disk rather than re-streaming.
@MainActor
final class CraftAnimationFile: ObservableObject {
    @Published private(set) var localURL: URL?
    @Published private(set) var failed = false
    private static let folder = FileManager.default.temporaryDirectory.appendingPathComponent("animations", isDirectory: true)

    func load(_ remote: URL, id: String) async {
        let destination = Self.folder.appendingPathComponent(id + ".mp4")
        if FileManager.default.fileExists(atPath: destination.path) { localURL = destination; return }
        do {
            let (data, response) = try await CraftCloudMedia.data(remote)
            guard (response as? HTTPURLResponse)?.statusCode ?? 200 < 400, data.count > 1024 else { failed = true; return }
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
            localURL = destination
        } catch {
            failed = true
        }
    }
}

/// A finished character animation: the character image, then its loop on top.
///
/// The still is the image the animation was made from, so there is something
/// truthful to show under Reduce Motion, before the clip arrives, and whenever
/// the ambient gate closes.
struct CraftAnimationLoop: View {
    let url: URL
    let id: String
    var posterURL: URL?
    var cornerRadius: CGFloat = 20
    @StateObject private var file = CraftAnimationFile()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.craftAmbientMotion) private var ambient
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender

    private var playing: Bool { !reduceMotion && ambient }

    var body: some View {
        ZStack {
            appearance.washSoft
            if let posterURL { CraftThumbnailImage(url: posterURL).scaledToFit() }
            if playing, let local = file.localURL {
                CraftLoopingVideo(url: local, playing: true).id(local)
            }
        }
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(appearance.fill.opacity(0.35), lineWidth: 1))
        .task(id: url) { if playing { await file.load(url, id: id) } }
        .accessibilityLabel(Text(reduceMotion ? "Animated character, paused" : "Animated character, looping"))
    }

    /// The downloaded file, for sharing or saving.
    var fileURL: URL? { file.localURL }
}

/// An animated character on its own: the loop, and a way to take it elsewhere.
struct AnimatedCharacterDetailView: View {
    let asset: CraftAsset
    @EnvironmentObject private var store: CraftStore
    @StateObject private var file = CraftAnimationFile()
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showGadgetShowcase = false
    @State private var showCodexGameHandoff = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ZStack {
                    appearance.washSoft
                    if let poster = asset.thumbURL { CraftThumbnailImage(url: poster).scaledToFit() }
                    if !reduceMotion, let local = file.localURL {
                        CraftLoopingVideo(url: local, playing: true).id(local)
                    }
                }
                .frame(height: 340)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .accessibilityIdentifier("animation.player")

                Text(asset.name).font(.system(size: 22, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)

                if let local = file.localURL {
                    VStack(spacing: 12) {
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            showGadgetShowcase = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "heart.circle.fill")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(.white)

                                Text(store.t("Desktop Emotional Companion", "设为桌面情绪伴侣小组件"))
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)

                                Image(systemName: "sparkles")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color(red: 1.0, green: 0.52, blue: 0.45),
                                        Color(red: 1.0, green: 0.42, blue: 0.58)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.55), Color.white.opacity(0.12)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        ),
                                        lineWidth: 1
                                    )
                            )
                            .shadow(color: Color(red: 1.0, green: 0.50, blue: 0.46).opacity(0.28), radius: 10, x: 0, y: 5)
                        }
                        .buttonStyle(CraftPressStyle(scale: 0.96))
                        .accessibilityIdentifier("animation.gadget")

                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            showCodexGameHandoff = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "chevron.left.forwardslash.chevron.right")
                                    .font(.system(size: 15, weight: .bold))
                                Text(store.t("Generate Game with Codex / Cloud Code", "发送到 Codex / Cloud Code 生成游戏"))
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(appearance.washStrong, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .foregroundStyle(appearance.ink)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(appearance.fill.opacity(0.25), lineWidth: 1)
                            )
                        }
                        .buttonStyle(CraftPressStyle(scale: 0.97))
                        .accessibilityIdentifier("animation.codexGame")

                        ShareLink(item: local) {
                            Label(store.t("Save as Phone Live Sticker / Video", "保存为手机动态贴纸 / 视频"), systemImage: "square.and.arrow.up")
                                .font(.subheadline.weight(.medium))
                        }
                        .buttonStyle(CraftPressStyle())
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                        .accessibilityIdentifier("animation.share")
                    }
                } else if file.failed {
                    Text(store.t("This animation could not be loaded. Check your connection and try again.",
                                 "无法加载这段动画，请检查网络后重试。"))
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }

                Text(store.t(
                    "Animations provide emotional companionship and live stickers for your phone, and can be handed off to Codex or Cloud Code to code custom games. (To play inside the built-in 3D physics worlds, use 3D models.)",
                    "动画角色专为情绪伴侣、手机动态贴纸及 2D 游戏动画设计，也可直接发给 Codex 或 Cloud Code 自动编写专属游戏。（如需在内置 3D 物理世界中直接试玩，请使用 3D 模型。）"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
            }
            .padding(24).frame(maxWidth: 650).frame(maxWidth: .infinity)
        }
        .background { StudioAtmosphere() }
        .navigationTitle(store.t("Animated character", "动画角色"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showGadgetShowcase) {
            CraftGadgetShowcaseView(asset: asset, localVideoURL: file.localURL) {
                showGadgetShowcase = false
            }
        }
        .sheet(isPresented: $showCodexGameHandoff) {
            CodexAnimationGameHandoffView(asset: asset, videoURL: file.localURL)
        }
        .task { if let url = asset.animationURL { await file.load(url, id: asset.id) } }
    }
}

private struct CraftVideoExample: Identifiable {
    let id: String
    let name: String
    let provider: String
    let note: String
    let sample: String?
    let sampleDetails: String

    static let all: [Self] = [
        .init(id: "atlas-seedance-2.5", name: "Seedance 2.5", provider: "Atlas",
              note: "Best source fidelity and loop continuity in our single Dragon comparison.",
              sample: "seedance-2.5", sampleDetails: "Dragon sample · 480p · 4 seconds"),
        .init(id: "atlas-seedance-2.0-mini", name: "Seedance 2.0 Mini", provider: "Atlas",
              note: "Lowest cost. Expressive motion, with a visible lighting change at the loop seam.",
              sample: "mini", sampleDetails: "Dragon sample · 480p · 4 seconds"),
        .init(id: "atlas-seedance-2.0", name: "Seedance 2.0", provider: "Atlas",
              note: "Clear head movement and a relatively stable silhouette in this sample.",
              sample: "seedance-2.0", sampleDetails: "Dragon sample · 480p · 4 seconds"),
        .init(id: "atlas-wan-3.0-prime", name: "Wan 3.0 Prime", provider: "Atlas",
              note: "Preserved the pose, though its movement was subtle in this sample.",
              sample: "wan-3.0-prime", sampleDetails: "Dragon sample · 480p · 4 seconds"),
        .init(id: "atlas-minimax-h3", name: "MiniMax H3", provider: "Atlas",
              note: "Smooth gaze and head movement; this sample was rendered at 768p.",
              sample: "minimax-h3", sampleDetails: "Dragon sample · 768p · 4 seconds"),
        .init(id: "minimax-h3", name: "MiniMax H3", provider: "fal",
              note: "Existing app option. Atlas's sample above is from a different provider.",
              sample: nil, sampleDetails: "No matching sample in this comparison"),
        .init(id: "seedance-2.5", name: "Seedance 2.5", provider: "fal",
              note: "Existing app option. Atlas's sample above is from a different provider.",
              sample: nil, sampleDetails: "No matching sample in this comparison"),
    ]
}

/// Confirms what the character will do, how long the loop is, and what it costs
/// before any Tokens are reserved.
struct AnimationGenerationSheet: View {
    let concept: CraftConcept
    let chinese: Bool
    let onGenerate: (String, String, String, String) -> Void   // model, motion, resolution, duration
    @EnvironmentObject private var store: CraftStore
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    @Environment(\.dismiss) private var dismiss
    @State private var model = "atlas-seedance-2.5"
    @State private var motion = ""
    @State private var resolution = "480p"
    @State private var duration = "4"
    @State private var cost: Int?
    @State private var loading = true
    @State private var showShortfallModal = false
    @State private var shortfallNeeded = 0
    @State private var showTokenPacks = false
    @State private var showModelChoices = false
    @State private var playingSample = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var selectedExample: CraftVideoExample {
        CraftVideoExample.all.first { $0.id == model } ?? CraftVideoExample.all[0]
    }

    private func t(_ en: String, _ zh: String) -> String { chinese ? zh : en }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(t("Bring this character to life", "让这个角色动起来"))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text(t("A short silent loop that starts and ends on the same pose, so it repeats cleanly. Use it in a game, a video, or anywhere you like.",
                           "生成一段无声循环动画，首尾同一姿势，可以无缝重复播放。可用于游戏、视频或任何你喜欢的地方。"))
                        .font(.subheadline).foregroundStyle(.secondary)

                    if let url = URL(string: concept.imageUrl) {
                        CraftThumbnailImage(url: url).scaledToFit()
                            .frame(height: 180).frame(maxWidth: .infinity)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }

                    modelChoice

                    VStack(alignment: .leading, spacing: 8) {
                        Text(t("What should it do?", "让它做什么？")).font(.subheadline.weight(.semibold))
                        TextField(t("Optional, e.g. it waves and smiles", "可选，例如：挥手微笑"), text: $motion, axis: .vertical)
                            .lineLimit(2...4).textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("animation.motion")
                        Text(t("Left empty, the character breathes, blinks and shifts gently.",
                               "留空时，角色会自然呼吸、眨眼并轻轻晃动。"))
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    let durationOptions: [(String, String)] = model == "minimax-h3"
                        ? [("5", t("5 seconds", "5 秒"))]
                        : [("4", t("4 seconds", "4 秒")), ("6", t("6 seconds", "6 秒"))]

                    picker(t("Length", "时长"), selection: $duration,
                           options: durationOptions,
                           identifier: "animation.duration")

                    let resolutionOptions: [(String, String)] = model == "minimax-h3"
                        ? [("480p", t("Standard (480P)", "标清 (480P)")), ("768p", t("High (768P)", "高清 (768P)"))]
                        : model == "atlas-minimax-h3"
                        ? [("768p", t("Standard (768P)", "标准 (768P)")), ("2K", t("High (2K)", "高清 (2K)"))]
                        : [("480p", t("Standard (480P)", "标准 (480P)")), ("720p", t("High (720P)", "高清 (720P)"))]

                    picker(t("Quality", "画质"), selection: $resolution,
                           options: resolutionOptions,
                           identifier: "animation.resolution")

                    costRow
                }
                .padding(24).frame(maxWidth: 650).frame(maxWidth: .infinity)
            }
            .background { StudioAtmosphere() }
            .navigationTitle(t("Animate", "生成动画"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("Cancel", "取消")) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) { generateButton }
            .onChange(of: model) { _, newModel in
                if newModel == "minimax-h3" {
                    duration = "5"
                    resolution = "480p"
                } else if newModel == "atlas-minimax-h3" {
                    duration = "4"
                    resolution = "768p"
                } else {
                    duration = "4"
                    resolution = "480p"
                }
                playingSample = false
            }
            .task(id: model + resolution + duration) { await refreshCost() }
            .sheet(isPresented: $showModelChoices) { modelChoices }
            .sheet(isPresented: $showShortfallModal) {
                TokenShortfallModalView(needed: shortfallNeeded, available: store.wallet.available) {
                    showTokenPacks = true
                }
                .craftAmbientHost()
            }
            .sheet(isPresented: $showTokenPacks) {
                CreatorPlansView(startOnTopups: true)
                    .craftAmbientHost()
            }
        }
    }

    private var modelChoice: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t("Animation model", "动画模型")).font(.subheadline.weight(.semibold))
            Button { showModelChoices = true } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedExample.name).font(.headline)
                        Text(selectedExample.provider).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                }
                .padding(14)
                .background(appearance.washSoft, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("animation.model")
            Text(selectedExample.note).font(.caption).foregroundStyle(.secondary)
            if let sample = selectedExample.sample,
               let url = Bundle.main.url(forResource: sample, withExtension: "mp4", subdirectory: "VideoComparisons") {
                ZStack {
                    RoundedRectangle(cornerRadius: 18).fill(appearance.washSoft)
                    if let poster = Bundle.main.url(forResource: sample, withExtension: "jpg", subdirectory: "VideoComparisons"),
                       let bitmap = UIImage(contentsOfFile: poster.path) {
                        Image(uiImage: bitmap).resizable().scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    if playingSample && !reduceMotion {
                        CraftLoopingVideo(url: url, playing: true, videoGravity: .resizeAspect)
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .accessibilityLabel(selectedExample.sampleDetails)
                HStack {
                    Text(selectedExample.sampleDetails)
                        .font(.caption.weight(.medium))
                    Spacer()
                    Button {
                        playingSample.toggle()
                    } label: {
                        Label(playingSample ? t("Pause", "暂停") : t("Play sample", "播放样片"),
                              systemImage: playingSample ? "pause.fill" : "play.fill")
                    }
                    .disabled(reduceMotion)
                }
                .padding(10)
                .background(appearance.washSoft, in: RoundedRectangle(cornerRadius: 14))
                Text(t("One Dragon test clip. Your character and result will differ.",
                       "这是一次龙角色测试样片；你的角色和结果会有所不同。"))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var modelChoices: some View {
        NavigationStack {
            List(CraftVideoExample.all) { example in
                Button {
                    model = example.id
                    showModelChoices = false
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: example.id == model ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(appearance.ink)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(example.name).font(.headline)
                            Text("\(example.provider) · \(example.note)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
            }
            .navigationTitle(t("Choose animation model", "选择动画模型"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button(t("Done", "完成")) { showModelChoices = false }
            }}
        }
    }

    private func picker(_ title: String, selection: Binding<String>,
                        options: [(String, String)], identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            Picker(title, selection: selection) {
                ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
            }.pickerStyle(.segmented).accessibilityIdentifier(identifier)
        }
    }

    private var costRow: some View {
        HStack {
            Label(t("Cost", "费用"), systemImage: "circle.hexagongrid.fill")
                .font(.subheadline.weight(.semibold))
            Spacer()
            if loading { ProgressView() }
            else if let cost {
                Text("\(cost) Tokens").font(.subheadline.weight(.semibold)).monospacedDigit()
                    .accessibilityIdentifier("animation.cost")
            } else {
                Text(t("Price pending", "价格待确认")).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(14).background(appearance.washSoft, in: RoundedRectangle(cornerRadius: 16))
    }

    private var generateButton: some View {
        VStack(spacing: 6) {
            Button {
                guard let cost else { return }
                if store.wallet.available < cost {
                    shortfallNeeded = cost
                    showShortfallModal = true
                    return
                }
                onGenerate(model, motion.trimmingCharacters(in: .whitespacesAndNewlines), resolution, duration)
                dismiss()
            } label: {
                Label(t("Generate animation", "生成动画"), systemImage: "sparkles")
            }
            .buttonStyle(CraftPrimary(armed: cost != nil && !store.busy, busy: store.busy,
                                      verticalPadding: 14, cornerRadius: 16))
            .disabled(cost == nil || store.busy)
            .accessibilityIdentifier("animation.generate")
            if let cost, store.wallet.available < cost {
                Button {
                    shortfallNeeded = cost
                    showShortfallModal = true
                } label: {
                    Text(t("You need \(cost) Tokens. Tap to top up.", "需要 \(cost) 个 Token，请先补充。"))
                        .font(.caption)
                        .foregroundStyle(appearance.ink)
                        .underline()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private func refreshCost() async {
        loading = true
        cost = await store.animationCost(model: model, resolution: resolution, duration: duration)
        loading = false
    }
}

// MARK: - Codex & Cloud Code Game Handoff

struct CodexAnimationGameHandoffView: View {
    let asset: CraftAsset
    let videoURL: URL?
    @EnvironmentObject private var store: CraftStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    @State private var selectedTemplate = 0
    @State private var customIdea = ""
    @State private var copiedPrompt = false
    @State private var copiedCommand = false

    private struct GameTemplate {
        let titleEn: String
        let titleZh: String
        let icon: String
        let descEn: String
        let descZh: String
    }

    private let templates: [GameTemplate] = [
        GameTemplate(
            titleEn: "Emotional Pet & Companion Game",
            titleZh: "互动电子宠物 / 情绪陪伴小游戏",
            icon: "heart.fill",
            descEn: "Interactive desktop/mobile companion with hunger, happiness, audio reactions and ambient effects.",
            descZh: "互动桌面/手机陪伴小游戏，包含喂食互动、心情动作、音效反馈与治愈背景氛围。"
        ),
        GameTemplate(
            titleEn: "2D Action Platformer",
            titleZh: "2D 动作冒险横版过关",
            icon: "figure.run",
            descEn: "Side-scrolling game with responsive jump, dash physics, enemy patrols and collectibles.",
            descZh: "横版过关冒险，支持跳跃、冲刺、敌人巡逻机制与收集物金币。"
        ),
        GameTemplate(
            titleEn: "2D Endless Runner",
            titleZh: "2D 无尽跳跃跑酷",
            icon: "flame.fill",
            descEn: "Fast-paced single-tap runner where character dodges hazards and collects stars.",
            descZh: "单指跳跃跑酷，角色奔跑躲避障碍并收集星星冲击最高分。"
        )
    ]

    private var promptText: String {
        let tmpl = templates[selectedTemplate]
        let genreTitle = store.isChinese ? tmpl.titleZh : tmpl.titleEn
        let genreDesc = store.isChinese ? tmpl.descZh : tmpl.descEn
        let characterName = asset.name
        let assetLink = asset.animationURL?.absoluteString ?? (videoURL?.lastPathComponent ?? "character_loop.mp4")

        if store.isChinese {
            return """
你是一名资深游戏开发工程师。请使用 Codex / Cloud Code 为动画角色 “\(characterName)” 编写一个完整的 2D Web 游戏。

【角色动画素材】
- 角色名称: \(characterName)
- 动画循环视频/素材: \(assetLink)
- 动画特性: 4秒循环动作，首尾无缝衔接，富含生动的情绪与动态

【游戏蓝图】
- 类型: \(genreTitle)
- 玩法设计: \(genreDesc)
\(customIdea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "- 额外玩法要求: " + customIdea.trimmingCharacters(in: .whitespacesAndNewlines))

【技术规范与交付要求】
1. 单文件纯 HTML5 Canvas 或 Phaser 3 架构，直接保存为 index.html 即可在浏览器运行。
2. 完美适配移动端触屏与键盘控制 (WASD / 空格 / 点击)。
3. 使用角色循环动画作为主角的核心动画状态。
4. 计分系统、最高分本地存储 (localStorage) 以及音效反馈。
5. 精美的主题视觉设计与 Game Over 重试结算面板。
"""
        } else {
            return """
You are a senior indie game developer. Use Codex / Cloud Code to build a complete 2D Web game featuring "\(characterName)".

[Character Animation Asset]
- Character Name: \(characterName)
- Looping Animation Asset: \(assetLink)
- Trait: Seamless 4-second looping motion with rich personality

[Game Blueprint]
- Genre: \(genreTitle)
- Design: \(genreDesc)
\(customIdea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "- Custom Notes: " + customIdea.trimmingCharacters(in: .whitespacesAndNewlines))

[Technical Requirements]
1. Self-contained HTML5 Canvas or Phaser 3 application that runs out of the box in a single index.html.
2. Dual controls: mobile touch buttons and keyboard (WASD / Space).
3. Integrate the character looping animation seamlessly into gameplay states.
4. Score tracking, high-score persistence (localStorage), and audio/visual feedback.
5. Polished game start screen and game over recap dialog.
"""
        }
    }

    private var cliCommand: String {
        let characterName = asset.name
        let tmpl = templates[selectedTemplate]
        let genreTitle = store.isChinese ? tmpl.titleZh : tmpl.titleEn
        return "agy -p \"Create a 2D web sprite game featuring \(characterName) (\(genreTitle)). Looping animation URL: \(asset.animationURL?.absoluteString ?? "")\" --dangerously-skip-permissions"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    bannerCard
                    characterCard
                    templateSection
                    customNotesSection
                    promptSection
                    cliSection
                    exportSection
                }
                .padding(20)
            }
            .background { StudioAtmosphere() }
            .navigationTitle(store.t("Generate Game with Codex", "Codex / Cloud Code 游戏生成"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(store.t("Done", "完成")) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var bannerCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 20))
                .foregroundStyle(appearance.ink)
            VStack(alignment: .leading, spacing: 4) {
                Text(store.t("Direct Game Generation", "直接由 AI 编码生成游戏"))
                    .font(.headline)
                Text(store.t(
                    "Animated characters (2D loops) are directly sent to Codex or Cloud Code to code custom games. (3D models are placed into the built-in 3D game engine.)",
                    "动画角色（2D 循环动画）直接发送给 Codex 或 Cloud Code 自动编写专属游戏；3D 模型则可在内置 3D 物理引擎中直接试玩。"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(appearance.washSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var characterCard: some View {
        HStack(spacing: 14) {
            ZStack {
                appearance.washStrong
                if let poster = asset.thumbURL {
                    CraftThumbnailImage(url: poster).scaledToFill()
                } else {
                    Image(systemName: "film")
                        .font(.system(size: 24))
                        .foregroundStyle(appearance.ink)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(asset.name).font(.headline)
                Text(store.t("4-second seamless loop · 2D Game Asset", "4秒无缝循环 · 2D 游戏动画素材"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var templateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(store.t("Select Game Blueprint", "选择游戏玩法蓝图")).font(.headline)
            ForEach(0..<templates.count, id: \.self) { index in
                let tmpl = templates[index]
                let isSelected = selectedTemplate == index
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    selectedTemplate = index
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: tmpl.icon)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(isSelected ? appearance.ink : .secondary)
                            .frame(width: 34, height: 34)
                            .background(isSelected ? appearance.washStrong : Color.black.opacity(0.04), in: Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.isChinese ? tmpl.titleZh : tmpl.titleEn)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(store.isChinese ? tmpl.descZh : tmpl.descEn)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(appearance.ink)
                        }
                    }
                    .padding(12)
                    .background(isSelected ? appearance.washSoft : Color.white.opacity(0.6),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(isSelected ? appearance.fill : Color.clear, lineWidth: 1.5)
                    )
                }
                .buttonStyle(CraftPressStyle())
            }
        }
    }

    private var customNotesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.t("Custom Gameplay Notes (Optional)", "自定义玩法说明（可选）")).font(.subheadline.weight(.semibold))
            TextField(store.t("e.g. Add jump sound effects, retro pixel background...", "例如：添加跳跃音效、复古像素街道背景……"), text: $customIdea)
                .textFieldStyle(.roundedBorder)
                .font(.subheadline)
        }
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(store.t("Codex / Cloud Code Prompt", "Codex / Cloud Code 编写提示词")).font(.headline)
                Spacer()
                Button {
                    UIPasteboard.general.string = promptText
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    copiedPrompt = true
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        copiedPrompt = false
                    }
                } label: {
                    Label(copiedPrompt ? store.t("Copied!", "已复制！") : store.t("Copy Prompt", "复制 Prompt"),
                          systemImage: copiedPrompt ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(CraftPressStyle())
                .foregroundStyle(appearance.ink)
            }

            Text(promptText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var cliSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(store.t("Antigravity CLI (agy)", "Antigravity CLI 指令 (agy)"), systemImage: "terminal")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    UIPasteboard.general.string = cliCommand
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    copiedCommand = true
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        copiedCommand = false
                    }
                } label: {
                    Text(copiedCommand ? store.t("Copied!", "已复制！") : store.t("Copy Command", "复制指令"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(appearance.ink)
                }
                .buttonStyle(CraftPressStyle())
            }

            Text(cliCommand)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(appearance.ink)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(appearance.washStrong, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var exportSection: some View {
        Group {
            if let local = videoURL {
                ShareLink(item: local) {
                    Label(store.t("Export Animation Asset (.mp4)", "导出动画素材包 (.mp4)"), systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(appearance.washStrong, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .foregroundStyle(appearance.ink)
                .buttonStyle(CraftPressStyle())
            }
        }
    }
}
