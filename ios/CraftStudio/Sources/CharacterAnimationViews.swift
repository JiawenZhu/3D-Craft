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
                    VStack(spacing: 10) {
                        ShareLink(item: local) {
                            Label(store.t("Share or save this loop", "分享或保存动画"), systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(CraftPrimary(verticalPadding: 14, cornerRadius: 16))
                        .accessibilityIdentifier("animation.share")

                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            showGadgetShowcase = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "square.stack.3d.up.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.white)

                                Text(store.t("Add to Desktop Gadget", "设为桌面组件"))
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
                                        Color(red: 1.0, green: 0.56, blue: 0.42),
                                        Color(red: 1.0, green: 0.46, blue: 0.54)
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
                    }
                } else if file.failed {
                    Text(store.t("This animation could not be loaded. Check your connection and try again.",
                                 "无法加载这段动画，请检查网络后重试。"))
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }

                Text(store.t("A silent 4-second loop that ends where it starts, so it repeats cleanly in a game or a video.",
                             "无声循环动画，首尾一致，可在游戏或视频中无缝重复播放。"))
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
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
        .task { if let url = asset.animationURL { await file.load(url, id: asset.id) } }
    }
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
    @State private var model = "minimax-h3"
    @State private var motion = ""
    @State private var resolution = "480p"
    @State private var duration = "5"
    @State private var cost: Int?
    @State private var loading = true
    @State private var showShortfallModal = false
    @State private var shortfallNeeded = 0
    @State private var showTokenPacks = false

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

                    VStack(alignment: .leading, spacing: 8) {
                        picker(t("Animation Model", "动画模型"), selection: $model,
                               options: [("minimax-h3", t("MiniMax Hailuo 02", "MiniMax 海螺 02")),
                                         ("seedance-2.5", t("Seedance 2.5", "Seedance 2.5"))],
                               identifier: "animation.model")
                        Text(model == "minimax-h3"
                             ? t("Vivid expressions · Stable accessories · High value", "表情生动自然 · 配饰结构稳定 · 高性价比")
                             : t("Fluid cloth physics · Dramatic jump hangtime", "流体布料质感 · 舒展跳跃滞空"))
                            .font(.caption).foregroundStyle(.secondary)
                    }

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
                    if resolution == "720p" { resolution = "768p" }
                    else if resolution != "480p" && resolution != "768p" { resolution = "480p" }
                } else {
                    if duration == "5" { duration = "4" }
                    if resolution == "768p" { resolution = "720p" }
                    else if resolution != "480p" && resolution != "720p" { resolution = "480p" }
                }
            }
            .task(id: model + resolution + duration) { await refreshCost() }
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
