import SwiftUI
import UIKit

/// Four native pipeline nodes, driven by the job's actual state.
///
/// This is where the user waits, so the card is alive — but only ever in ways
/// that are honest: a spinning arc and a travelling connector say "work is
/// happening", the bar and the percentage say only what the service reported,
/// and the bar is driven by a CURVE so it can never overshoot into a number the
/// backend did not send.
///
/// Three discrete, individually gated loops replace the old 30 fps
/// `TimelineView`, which redrew the whole card — including a per-frame shadow
/// radius — every frame it was on screen.
struct GenerationJourneyView: View {
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    let job: CraftJob
    let sourceURL: URL?
    let selectedConceptURL: URL?
    let chinese: Bool
    var coreConcept: String? = nil
    /// Optional future structured backend stage; existing messages remain valid.
    var stage: String? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.craftAmbientMotion) private var ambient
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    // Presentational state only.
    @State private var arcSpin = false
    @State private var connectorSweep = false
    @State private var startTick = 0

    private let coral = Color(red: 0.65, green: 0.19, blue: 0.12)
    private var lilac: Color { appearance.ink }
    private var modelJob: Bool { job.kind.lowercased() == "model" }
    private var running: Bool { job.status.lowercased() == "running" }
    private var done: Bool { ["done", "completed", "succeeded"].contains(job.status.lowercased()) }
    private var failed: Bool { ["failed", "error"].contains(job.status.lowercased()) }
    private var partial: Bool { job.status.lowercased() == "partial" }
    private var percentage: Double { job.progress.isFinite ? min(100, max(0, job.progress)) : 0 }
    /// The single gate every continuous loop in this file is built behind.
    private var animates: Bool { running && !reduceMotion && ambient && contrast != .increased }
    private func t(_ en: String, _ zh: String) -> String { chinese ? zh : en }

    private var activeStep: Int {
        if done { return modelJob ? 3 : 2 }
        let detail = (stage ?? job.message).lowercased()
        if modelJob {
            if job.status == "queued" || detail.contains("preparing reference") || detail == "queued" { return 1 }
            return 2
        }
        if detail == "analyzing_reference" { return 1 }
        if detail.contains("render") || detail.contains("image") || detail.contains("saved") || detail.contains("concept") || percentage > 0 { return 2 }
        return 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if modelJob && job.isActive { PlayWhileCreatingCard(job: job) }
            header

            VStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { index in
                    node(index)
                    if index < 3 { connector(after: index) }
                }
            }

            progressBlock
        }
        .padding(20)
        .background(CraftTheme.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(edgeColor, lineWidth: contrast == .increased ? 1.5 : 1)
        )
        .craftDepth(.card)
        .animation(CraftMotion.gated(.glide, reduceMotion), value: statusLabel)
        .craftEntrance(0, distance: 24)
        .onChange(of: animates, initial: true) { _, on in updateLoops(on) }
        .onChange(of: running, initial: true) { _, on in if on { startTick += 1 } }
        .craftFeedback(.jobStarted, trigger: startTick)
        .craftFeedback(.stepAdvance, trigger: activeStep)
        .craftFeedback(.jobSucceeded, trigger: done)
        .craftFeedback(.jobFailed, trigger: failed)
        .craftFeedback(.jobWarning, trigger: partial)
        .accessibilityIdentifier("generationJourney")
    }

    /// The only two `repeatForever` animations in this file, both installed and
    /// torn down by the `animates` gate and nothing else.
    private func updateLoops(_ on: Bool) {
        if on {
            arcSpin = false
            connectorSweep = false
            withAnimation(CraftMotion.orbit.repeatForever(autoreverses: false)) { arcSpin = true }
            withAnimation(CraftMotion.travel.repeatForever(autoreverses: false)) { connectorSweep = true }
        } else {
            withAnimation(nil) {
                arcSpin = false
                connectorSweep = false
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(t("YOUR CREATION JOURNEY", "你的创作旅程"))
                    .font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(lilac)
                titleReveal(modelJob ? t("From your image to 3D", "从你的图片到 3D")
                                     : t("An idea taking shape", "让灵感逐渐成形"))
            }
            Spacer(minLength: 8)
            statusChip
        }
    }

    /// The title writes itself in. Long strings and large Dynamic Type fall back
    /// to one whole-string entrance, because a row of per-glyph `Text`s cannot
    /// wrap.
    @ViewBuilder private func titleReveal(_ text: String) -> some View {
        if text.count <= 28, dynamicTypeSize <= .xxLarge, !reduceMotion {
            HStack(spacing: 0) {
                ForEach(Array(text.enumerated()), id: \.offset) { index, character in
                    Text(String(character))
                        .craftEntrance(index, distance: 6, step: 0.018)
                }
            }
            .font(.title3.weight(.semibold))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
        } else {
            Text(text).font(.title3.weight(.semibold)).craftEntrance(0)
        }
    }

    private var statusChip: some View {
        HStack(spacing: 6) {
            if running {
                Circle().fill(lilac).frame(width: 7, height: 7)
                    .craftBreathe(active: running, from: 0.45, to: 1.0, period: 1.6)
                    .accessibilityHidden(true)
            }
            Text(statusLabel)
                .font(.caption.weight(.semibold))
                .contentTransition(.opacity)
        }
        .foregroundStyle(statusColor)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(statusColor.opacity(0.1), in: Capsule())
    }

    private var statusLabel: String {
        if done { return t("Ready", "已完成") }
        if failed { return t("Needs attention", "需要处理") }
        if running { return t("Creating", "创作中") }
        if job.status == "queued" { return t("Queued", "排队中") }
        return t("Paused", "已暂停")
    }

    private var statusColor: Color {
        if failed { return coral }
        if done { return .green }
        return lilac
    }

    private var edgeColor: Color {
        if contrast == .increased { return .black.opacity(0.3) }
        if failed { return coral.opacity(0.35) }
        if done { return Color.green.opacity(0.35) }
        return CraftTheme.hairline
    }

    // MARK: - Nodes

    private func completed(_ index: Int) -> Bool {
        if !modelJob && index == 3 { return false }
        return done ? index <= activeStep : index < activeStep
    }

    private func node(_ index: Int) -> some View {
        let active = index == activeStep && !done
        let success = completed(index)
        let alarmed = failed && active
        return HStack(alignment: .top, spacing: 13) {
            badge(index, active: active, success: success, alarmed: alarmed)
            card(index, active: active)
        }
    }

    private func badge(_ index: Int, active: Bool, success: Bool, alarmed: Bool) -> some View {
        ZStack {
            Circle().fill(active ? appearance.fill.opacity(0.06) : Color.black.opacity(0.03))

            // Static ring. The old pulsing stroke opacity and shadow radius are gone.
            Circle().strokeBorder(alarmed ? coral.opacity(0.7)
                                          : active ? appearance.fill.opacity(0.45)
                                                   : Color.black.opacity(0.14))

            // Completion: the ring draws itself closed once, then stays.
            Circle().trim(from: 0, to: success ? 1 : 0)
                .stroke(Color.green.opacity(0.55), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(CraftMotion.gated(.reveal, reduceMotion, reduced: nil), value: success)

            // The one live indicator on the card. Structurally absent when the
            // gate is closed, so the loop is never even installed.
            if active && animates {
                Circle().trim(from: 0, to: 0.28)
                    .stroke(appearance.deep, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(arcSpin ? 360 : 0))
            }

            Image(systemName: glyph(index, success: success, alarmed: alarmed))
                .font(.system(size: index == 3 && success ? 14 : 12, weight: .semibold))
                .foregroundStyle(success ? Color.green
                                         : alarmed ? coral
                                                   : active ? lilac : Color.secondary)
                .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace.downUp))
                .craftSymbolPop((index == 3 && success) || alarmed, reduceMotion: reduceMotion)
        }
        .frame(width: 30, height: 30)
        .animation(CraftMotion.gated(.snap, reduceMotion), value: success)
        .accessibilityHidden(true)
    }

    private func card(_ index: Int, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title(index)).font(.subheadline.weight(.semibold))
                Spacer(minLength: 4)
                if active && running {
                    Text(t("NOW", "当前"))
                        .font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(lilac)
                        .transition(reduceMotion ? .opacity
                                                 : .scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .animation(CraftMotion.gated(.pop, reduceMotion), value: activeStep)

            Text(detail(index)).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if index == 0 {
                referenceImage(modelJob ? (selectedConceptURL ?? sourceURL) : sourceURL)
            }
            if index == 1, !modelJob, let coreConcept,
               !coreConcept.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(coreConcept).font(.caption).foregroundStyle(Color.primary.opacity(0.85))
                    .padding(11).frame(maxWidth: .infinity, alignment: .leading)
                    .background(appearance.washSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            if index == 2, !modelJob, let selectedConceptURL { referenceImage(selectedConceptURL) }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(active ? appearance.fill.opacity(0.06) : Color.black.opacity(0.018),
                    in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .strokeBorder(active ? appearance.fill.opacity(0.28) : Color.black.opacity(0.06))
        )
        .animation(CraftMotion.gated(.brush, reduceMotion), value: active)
    }

    private func connector(after index: Int) -> some View {
        let filled = completed(index + 1)
        let live = running && index + 1 == activeStep
        return HStack {
            ZStack(alignment: .top) {
                Capsule().fill(Color.black.opacity(0.08)).frame(width: 1)
                Capsule().fill(Color.green.opacity(0.30)).frame(width: 1)
                    .scaleEffect(y: filled ? 1 : 0, anchor: .top)
                    .animation(CraftMotion.gated(.glide, reduceMotion, reduced: nil), value: filled)
                if live && animates {
                    // One masked capsule of light per connector, on a single
                    // Core Animation loop. The old per-frame offset dot is gone.
                    Capsule()
                        .fill(LinearGradient(colors: [.clear, appearance.deep, .clear],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: 2, height: 10)
                        .offset(y: connectorSweep ? 22 : -10)
                } else if live {
                    Capsule().fill(appearance.fill.opacity(0.55))
                        .frame(width: 2, height: 7).offset(y: 7)
                }
            }
            .frame(width: 30, height: 22)
            .clipped()
            Spacer()
        }
        .accessibilityHidden(true)
    }

    // MARK: - Reported progress

    private var progressBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(t("Reported progress", "服务返回的进度")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(percentage))%")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .craftNumeric(Int(percentage), reduceMotion: reduceMotion)
                    .accessibilityLabel(t("Reported progress \(Int(percentage)) percent",
                                          "服务返回进度百分之 \(Int(percentage))"))
            }

            meter

            if !job.message.isEmpty {
                Text(job.message).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if failed, let error = job.error, !error.isEmpty {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(coral).fixedSize(horizontal: false, vertical: true)
            }
            if running {
                Text(t("Progress updates when the service reports a change. Your work continues if you leave this screen.",
                       "进度会随服务返回的状态更新。离开此页面后任务仍会继续。"))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    /// A curve, never a spring: a spring would overshoot past the percentage the
    /// service actually reported.
    private var meter: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.07))
                Capsule()
                    .fill(failed ? AnyShapeStyle(coral) : AnyShapeStyle(appearance.gradient))
                    .frame(width: geometry.size.width * min(1, max(0, percentage / 100)))
            }
        }
        .frame(height: 8)
        .animation(CraftMotion.gated(.meter, reduceMotion), value: percentage)
        .accessibilityHidden(true)
    }

    @ViewBuilder private func referenceImage(_ url: URL?) -> some View {
        if let url {
            Group {
                if url.isFileURL, let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image { image.resizable().scaledToFit() }
                        else {
                            Label(t("Reference image", "参考图片"), systemImage: "photo")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity).frame(height: 110)
            .background(appearance.washSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            Label(t("Created from your words", "从你的文字开始创作"), systemImage: "text.alignleft")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Copy

    private func glyph(_ index: Int, success: Bool, alarmed: Bool) -> String {
        if success { return index == 3 ? "checkmark.seal.fill" : "checkmark" }
        if alarmed { return "exclamationmark.triangle" }
        return icon(index)
    }

    private func icon(_ index: Int) -> String {
        if modelJob { return ["photo", "clock", "cube.transparent", "checkmark.seal"][index] }
        return [sourceURL == nil ? "text.alignleft" : "photo", "text.badge.star", "sparkles", "cube.transparent"][index]
    }
    private func title(_ index: Int) -> String {
        if modelJob { return [t("Selected concept", "已选概念图"), t("Prepare & queue", "准备与排队"), t("3D reconstruction", "三维重建"), t("Your asset", "你的资产")][index] }
        return [t("Your reference", "你的参考"), t("Shape the prompt", "整理创作描述"), t("Create concepts", "生成概念图"), t("Make it 3D", "生成 3D")][index]
    }
    private func detail(_ index: Int) -> String {
        if modelJob {
            return [t("The chosen image guides this reconstruction.", "使用你选中的图片指导本次重建。"),
                    t("Prepare the reference and wait for the model service.", "准备参考图并等待模型服务。"),
                    t("Build the shape and texture from your concept.", "根据概念图构建形状和纹理。"),
                    done ? t("Ready to inspect, export, or try in a game.", "可以检查、导出或在游戏中试玩。") : t("Available after reconstruction completes.", "重建完成后即可查看。")][index]
        }
        return [t("Your photo or words are the starting point.", "使用你的照片或文字作为起点。"),
                t("Prepare a clear description for concept generation.", "准备清晰的描述以生成概念图。"),
                done ? t("Concepts are ready for your review.", "概念图已生成，等待你挑选。") : t("Render the same subject from the requested camera views.", "围绕同一个主体生成所需视角。"),
                t("Next: select a concept and confirm 3D generation separately.", "下一步：挑选概念图，再单独确认生成 3D。")][index]
    }
}
