import SwiftUI

/// Only announce work observed in progress (or just submitted), never old library items.
struct ModelCompletionTracker {
    var watching = Set<String>()
    var announced = Set<String>()
    mutating func receive(_ jobs: [CraftJob]) -> [CraftJob] {
        watching.formUnion(jobs.filter { $0.kind == "model" && $0.isActive }.map(\.id))
        let ready = jobs.filter { $0.kind == "model" && watching.contains($0.id) && !announced.contains($0.id)
            && $0.status == "done" && $0.assets.contains { $0.modelURL != nil } }
        announced.formUnion(ready.map(\.id))
        watching.subtract(ready.map(\.id))
        watching.subtract(jobs.filter { ["failed", "partial"].contains($0.status) }.map(\.id))
        return ready
    }
}

struct CreationReadyCard: View {
    @EnvironmentObject private var store: CraftStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    var onOpen: (() -> Void)? = nil
    var body: some View {
        if let job = store.completedModelCards.first, let asset = job.assets.first(where: { $0.modelURL != nil }) {
            HStack(spacing: 10) {
                Button { if let onOpen { onOpen() } else { store.openCompletedModel() } } label: {
                    HStack(spacing: 12) {
                        AssetThumbnail(asset: asset, height: 58).frame(width: 58)
                        VStack(alignment: .leading, spacing: 4) {
                            Label(store.t("Your 3D is ready!", "你的 3D 已完成！"), systemImage: "checkmark.seal.fill").font(.headline)
                            Text(store.t("Tap to explore your creation", "点击查看你的新作品")).font(.caption)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right").font(.headline)
                    }.foregroundStyle(appearance.ink).contentShape(Rectangle())
                }.buttonStyle(CraftPressStyle()).accessibilityIdentifier("creation.openCompleted")
                Button { store.completedModelCards.removeFirst() } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                }.accessibilityLabel(store.t("Dismiss completion", "关闭完成提示"))
            }
            .padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(appearance.ink.opacity(0.18)))
            .shadow(color: appearance.ink.opacity(0.15), radius: 18, y: 5)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
            .craftFeedback(.modelReady, trigger: job.id)
        }
    }
}

struct PlayWhileCreatingCard: View {
    let job: CraftJob
    var inGames = false
    @EnvironmentObject private var store: CraftStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.craftAmbientMotion) private var ambient
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    var body: some View {
        Button {
            if inGames { store.path.append(.project(job.projectId)) }
            else { store.path.removeAll(); store.selectedTab = 3 }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: inGames ? "cube.transparent.fill" : "gamecontroller.fill")
                    .font(.system(size: 32)).symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion && ambient)
                    .frame(width: 62, height: 62).background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 20))
                VStack(alignment: .leading, spacing: 6) {
                    Text(inGames ? store.t("Your 3D is taking shape", "你的 3D 正在成形") : store.t("Play while we create", "创作不停，先玩一局"))
                        .font(.headline)
                    Text(inGames ? store.t("We’ll let you know when it’s ready.", "完成后会在这里提醒你。") : store.t("Discover community games. We’ll tell you when your 3D is ready.", "探索社区游戏，3D 完成后会提醒你。"))
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                    if inGames {
                        ProgressView(value: min(100, max(0, job.progress)), total: 100).tint(appearance.ink)
                        Text(store.t("View progress", "查看生成进度") + " · \(Int(min(100,max(0,job.progress))))%")
                            .font(.caption2.weight(.semibold))
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
            }.padding(18).foregroundStyle(appearance.ink)
                .background(LinearGradient(colors: [appearance.washStrong, appearance.washSoft], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 24))
        }.buttonStyle(CraftPressStyle()).accessibilityIdentifier("creation.playWhileWaiting")
    }
}

struct CommunityGameArtwork: View {
    let symbol: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.craftAmbientMotion) private var ambient
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22).fill(LinearGradient(colors: [appearance.washStrong, appearance.washSoft, .white], startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().stroke(appearance.ink.opacity(0.12), lineWidth: 1).frame(width: 160, height: 160).offset(x: 75, y: 20)
            Circle().fill(.white.opacity(0.5)).frame(width: 100, height: 100).offset(x: -90, y: -35)
            Image(systemName: symbol).font(.system(size: 58, weight: .light))
            Image(systemName: "sparkle").font(.title2).offset(x: 95, y: -35)
                .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion && ambient)
            Image(systemName: "sparkle").font(.caption).offset(x: -95, y: 35)
        }.foregroundStyle(appearance.ink).frame(height: 150).clipped().accessibilityHidden(true)
    }
}
