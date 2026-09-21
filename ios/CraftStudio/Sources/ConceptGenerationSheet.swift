import SwiftUI

struct ConceptGenerationSheet: View {
    @EnvironmentObject private var store: CraftStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    @Binding var count: Int
    @State var prompt: String
    @State private var showShortfallModal = false
    @State private var shortfallNeeded = 0
    @State private var showTokenPacks = false
    @State private var selectedBackground: StudioBackground = .grey
    let onGenerate: (Int, String) -> Void

    init(count: Binding<Int>, initialPrompt: String = "", onGenerate: @escaping (Int, String) -> Void) {
        self._count = count
        self._prompt = State(initialValue: initialPrompt)
        self._selectedBackground = State(initialValue: StudioBackground.detect(in: initialPrompt))
        self.onGenerate = onGenerate
    }

    init(count: Binding<Int>, onGenerate: @escaping (Int) -> Void) {
        self._count = count
        self._prompt = State(initialValue: "")
        self._selectedBackground = State(initialValue: .grey)
        self.onGenerate = { count, _ in onGenerate(count) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                HStack {
                    Text(store.t("Create concepts", "生成概念图"))
                        .font(.title2.bold()).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.subheadline.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .background(appearance.washSoft, in: Circle())
                    }
                    .buttonStyle(CraftPressStyle())
                    .accessibilityLabel(store.t("Cancel", "取消"))
                    .accessibilityIdentifier("concept.generation.cancel")
                }

                VStack(spacing: 6) {
                    Text(store.t("How many images?", "想生成几张图片？"))
                        .font(.headline)
                    Text(CraftImageModel.displayName(for: store.imageModelID))
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 32) {
                    countButton(delta: -1)
                    VStack(spacing: 2) {
                        Text("\(count)")
                            .font(.system(size: 52, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(reduceMotion ? .identity : .numericText(value: Double(count)))
                            .accessibilityIdentifier("concept.generation.count")
                        Text(store.t(count == 1 ? "image" : "images", "张图片"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 80)
                    countButton(delta: 1)
                }
                .padding(.vertical, 6)

                HStack(spacing: 6) {
                    ForEach(1...4, id: \.self) { index in
                        Capsule().fill(index <= count ? appearance.fill : appearance.washSoft)
                            .frame(width: index <= count ? 26 : 10, height: 6)
                    }
                }
                .accessibilityHidden(true)

                if !prompt.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(store.t("Creative Prompt", "创意设定 / Prompt"), systemImage: "sparkles.rectangle.stack")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(appearance.ink)
                            Spacer()
                            Text(store.t("Editable", "可自定义调整"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        // Studio background environment selector
                        HStack(spacing: 8) {
                            Text(store.t("Background:", "摄影棚背景："))
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                            ForEach(StudioBackground.allCases) { bg in
                                Button {
                                    selectedBackground = bg
                                    prompt = StudioBackground.applying(bg, to: prompt, chinese: store.isChinese)
                                } label: {
                                    HStack(spacing: 5) {
                                        Circle()
                                            .fill(bg == .grey ? Color(red: 0.44, green: 0.45, blue: 0.48) : (bg == .white ? Color.white : Color.black))
                                            .frame(width: 10, height: 10)
                                            .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 0.8))
                                        Text(bg.shortTitle(chinese: store.isChinese))
                                            .font(.caption2.weight(selectedBackground == bg ? .semibold : .regular))
                                    }
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(selectedBackground == bg ? appearance.washStrong : appearance.washSoft, in: Capsule())
                                    .overlay(Capsule().strokeBorder(selectedBackground == bg ? appearance.fill : Color.clear, lineWidth: 1.2))
                                }
                                .buttonStyle(CraftPressStyle(scale: 0.96))
                                .foregroundStyle(appearance.ink)
                            }
                        }
                        .padding(.vertical, 2)

                        TextField(store.t("Add your custom prompt or details here...", "在此输入或调整你的专属 Prompt、配饰、颜色或场景..."), text: $prompt, axis: .vertical)
                            .lineLimit(2...5)
                            .font(.subheadline)
                            .padding(12)
                            .background(appearance.washSoft, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(appearance.washStrong, lineWidth: 1))
                        Text(store.t("We will generate concepts with the selected studio background.", "我们将根据此 Prompt 及指定背景生成高品质概念图。"))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Text(store.t("Maximum", "最多预留")).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(store.conceptTokenCost(count: count)) Tokens")
                        .fontWeight(.semibold).monospacedDigit()
                        .contentTransition(reduceMotion ? .identity : .numericText(value: Double(store.conceptTokenCost(count: count))))
                        .accessibilityIdentifier("concept.generation.total")
                }
                .font(.subheadline)
                .padding(16)
                .background(appearance.washSoft, in: RoundedRectangle(cornerRadius: 18))

                Text(store.t("Only actual usage is charged. Unused Tokens return to your wallet.", "仅按实际用量扣除 Token，未使用部分会退回钱包。"))
                    .font(.caption).foregroundStyle(.secondary)

                if store.showPriceDetails {
                    Text(store.conceptPriceSummary(count: count))
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    let cost = store.conceptTokenCost(count: count)
                    let available = store.wallet.available + store.wallet.freeConceptTokens
                    if available < cost {
                        shortfallNeeded = cost
                        showShortfallModal = true
                        return
                    }
                    onGenerate(count, prompt.trimmingCharacters(in: .whitespacesAndNewlines))
                } label: {
                    Label(store.t("Generate concepts", "生成概念图"), systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CraftPrimary())
                .disabled(store.busy || !store.conceptPriceReady)
                .accessibilityIdentifier("concept.generation.submit")
            }
            .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 24)
        }
        .foregroundStyle(appearance.ink)
        .background { StudioAtmosphere(intensity: 0.65) }
        .presentationDetents([.fraction(0.85), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .task { await store.refreshImageModelCatalog() }
        .craftFeedback(.optionSelect, trigger: count)
        .sheet(isPresented: $showShortfallModal) {
            TokenShortfallModalView(needed: shortfallNeeded, available: store.wallet.available + store.wallet.freeConceptTokens) {
                showTokenPacks = true
            }
            .craftAmbientHost()
        }
        .sheet(isPresented: $showTokenPacks) {
            CreatorPlansView(startOnTopups: true)
                .craftAmbientHost()
        }
    }

    private func countButton(delta: Int) -> some View {
        Button {
            withAnimation(CraftMotion.gated(.snap, reduceMotion)) {
                count = min(4, max(1, count + delta))
            }
        } label: {
            Image(systemName: delta < 0 ? "minus" : "plus")
                .font(.title3.weight(.semibold))
                .frame(width: 54, height: 54)
                .contentShape(Circle())
                .background(appearance.washStrong, in: Circle())
        }
        .buttonStyle(CraftPressStyle(scale: 0.90))
        .disabled(delta < 0 ? count <= 1 : count >= 4)
        .opacity((delta < 0 ? count <= 1 : count >= 4) ? 0.35 : 1)
        .accessibilityLabel(store.t(delta < 0 ? "Fewer images" : "More images", delta < 0 ? "减少图片数量" : "增加图片数量"))
        .accessibilityIdentifier(delta < 0 ? "concept.generation.minus" : "concept.generation.plus")
    }
}
