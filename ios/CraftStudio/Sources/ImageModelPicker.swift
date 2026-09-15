import SwiftUI

struct CraftImageModel: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let provider: String
    let available: Bool
    let quality: String
    let imageSize: String
    let unavailableReason: String?

    static let defaultID = "gemini-3-pro-image"
    static let placeholders: [CraftImageModel] = [
        .init(id: defaultID, name: "Gemini 3 Pro Image · Nano Banana Pro", provider: "Google", available: false, quality: "Pro", imageSize: "2K", unavailableReason: nil),
        .init(id: "codex-gpt-image-2", name: "GPT Image 2 · ChatGPT account", provider: "chatgpt", available: false, quality: "Account default", imageSize: "Native", unavailableReason: nil)
    ]
    static func restoredSelection(_ stored: String?) -> String {
        stored == "gpt-image-2.5-sunburst" ? defaultID : stored ?? defaultID
    }
    static func displayName(for id: String) -> String {
        placeholders.first { $0.id == (id == "gpt-image-2" ? "codex-gpt-image-2" : id) }?.name ?? id
    }
}

/// Selection names the exact renderer; unavailable providers never fall back.
struct ImageModelPicker: View {
    @EnvironmentObject private var store: CraftStore
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    @State private var accountOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { expanded.toggle() } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        if store.showPriceDetails { Text(store.priceLabel(store.imageModelID)).font(.caption).foregroundStyle(.secondary) }
                        Text(store.t("Concept image model", "概念图生图模型")).font(.caption).foregroundStyle(.secondary)
                        Text(CraftImageModel.displayName(for: store.imageModelID))
                            .font(.subheadline.weight(.semibold)).foregroundStyle(appearance.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down").rotationEffect(.degrees(expanded ? 180 : 0))
                        .foregroundStyle(appearance.ink)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("imageModel.picker")
                .accessibilityValue(expanded ? store.t("Expanded", "已展开") : store.t("Collapsed", "已收起"))
            if expanded {
            VStack(spacing: 10) {
                ForEach(store.imageModels) { model in
                    Button {
                        store.imageModelID = model.id
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: model.id == store.imageModelID ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(appearance.ink).padding(.top, 2)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(model.name).font(.subheadline.weight(.semibold))
                                if store.showPriceDetails { Text(store.priceLabel(model.id)).font(.caption).foregroundStyle(appearance.ink) }
                                if store.showPriceDetails, let price = store.modelPrices[model.id] {
                                    Text(store.isChinese ? price.noteZh : price.note).font(.caption2).foregroundStyle(.secondary)
                                }
                                Text(model.id).font(.caption2.monospaced()).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("\(model.provider) · \(model.imageSize) · \(model.quality)")
                                    .font(.caption).foregroundStyle(appearance.ink)
                                if !model.available {
                                    Text(store.imageModelsLoaded
                                         ? (model.id == "codex-gpt-image-2" ? store.t("Connect your ChatGPT account", "连接自己的 ChatGPT 账户") : store.t("Check connection", "请检查网络连接"))
                                         : store.t("Checking availability…", "正在检查可用状态……"))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(model.id == store.imageModelID ? appearance.wash : .white,
                                        in: RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(CraftPressStyle())
                        .accessibilityIdentifier("imageModel." + model.id)
                        .accessibilityAddTraits(model.id == store.imageModelID ? .isSelected : [])
                }
                Text(store.t("Gemini works without a ChatGPT account. Connect your own ChatGPT account to optionally use GPT Image 2.", "无需 ChatGPT 账户即可使用 Gemini；连接自己的 ChatGPT 账户后，可选择 GPT Image 2。"))
                    .font(.caption).foregroundStyle(.secondary)
                if let selected = store.selectedImageModel, !selected.available, store.imageModelsLoaded {
                    if selected.id == "codex-gpt-image-2" {
                        Button(store.t("Connect ChatGPT", "连接 ChatGPT")) { accountOpen = true }
                            .buttonStyle(CraftSecondary()).accessibilityIdentifier("imageModel.account")
                    } else {
                        Text(store.t("Gemini is currently unavailable. Please try again later.", "Gemini 暂不可用，请稍后重试。"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.padding(.top, 12)
            }
        }
        .tint(appearance.ink)
        .padding(14).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 20))
        .disabled(store.busy)
        .animation(CraftMotion.gated(.glide, reduceMotion), value: expanded)
        .animation(CraftMotion.gated(.snap, reduceMotion), value: store.imageModelID)
        .sheet(isPresented: $accountOpen) { AIAccountView() }
    }
}
