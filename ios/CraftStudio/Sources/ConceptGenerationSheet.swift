import SwiftUI

struct ConceptGenerationSheet: View {
    @EnvironmentObject private var store: CraftStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    @Binding var count: Int
    let onGenerate: (Int) -> Void

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

                HStack {
                    Text(store.t("Total", "合计")).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(store.conceptTokenCost(count: count)) Tokens")
                        .fontWeight(.semibold).monospacedDigit()
                        .contentTransition(reduceMotion ? .identity : .numericText(value: Double(store.conceptTokenCost(count: count))))
                        .accessibilityIdentifier("concept.generation.total")
                }
                .font(.subheadline)
                .padding(16)
                .background(appearance.washSoft, in: RoundedRectangle(cornerRadius: 18))

                if store.showPriceDetails {
                    Text(store.conceptPriceSummary(count: count))
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button { onGenerate(count) } label: {
                    Label(store.t("Generate concepts", "生成概念图"), systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CraftPrimary())
                .disabled(store.busy)
                .accessibilityIdentifier("concept.generation.submit")
            }
            .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 24)
        }
        .foregroundStyle(appearance.ink)
        .background { StudioAtmosphere(intensity: 0.65) }
        .presentationDetents([.height(510), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .craftFeedback(.optionSelect, trigger: count)
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
                .background(appearance.washStrong, in: Circle())
        }
        .buttonStyle(CraftPressStyle(scale: 0.90))
        .disabled(delta < 0 ? count <= 1 : count >= 4)
        .opacity((delta < 0 ? count <= 1 : count >= 4) ? 0.35 : 1)
        .accessibilityLabel(store.t(delta < 0 ? "Fewer images" : "More images", delta < 0 ? "减少图片数量" : "增加图片数量"))
        .accessibilityIdentifier(delta < 0 ? "concept.generation.minus" : "concept.generation.plus")
    }
}
