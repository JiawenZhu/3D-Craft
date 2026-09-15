import SwiftUI

struct PlannerModelPicker: View {
    @EnvironmentObject private var store: CraftStore
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    @State private var accountOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                expanded.toggle()
                if expanded { Task { await store.refreshAIAccount() } }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.t("Prompt planning model", "提示词规划模型")).font(.caption).foregroundStyle(.secondary)
                        if store.showPriceDetails { Text(store.plannerPriceLabel(store.plannerModelID)).font(.caption).foregroundStyle(.secondary) }
                        Text(store.plannerDisplayName).font(.subheadline.weight(.semibold)).foregroundStyle(appearance.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down").rotationEffect(.degrees(expanded ? 180 : 0)).foregroundStyle(appearance.ink)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("planner.picker")
                .accessibilityValue(expanded ? store.t("Expanded", "已展开") : store.t("Collapsed", "已收起"))

            if expanded {
                modelRow(id: CraftPlannerModel.defaultID, name: CraftPlannerModel.defaultName)
                if CraftAIAccount.enabledForRelease {
                ForEach(store.aiAccount.models) { model in modelRow(id: model.id, name: model.name) }
                if let selected = store.selectedPlannerModel, !selected.reasoningEfforts.isEmpty {
                    Picker(store.t("Planning effort", "规划思考程度"), selection: $store.plannerEffort) {
                        ForEach(selected.reasoningEfforts, id: \.self) { effort in Text(effortName(effort)).tag(effort) }
                    }.tint(appearance.ink).accessibilityIdentifier("planner.effort")
                    Text(store.t("Lower effort gives a faster planning pass. It does not change the image model or 3D settings.",
                                 "较低思考程度可加快提示词规划，不会改变生图模型或 3D 设置。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if store.plannerModelID != CraftPlannerModel.defaultID, store.selectedPlannerModel == nil {
                    Text(store.t("This saved planning model is unavailable. Connect its account or choose Gemini.",
                                 "已保存的规划模型当前不可用，请连接账户或选择 Gemini。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                }
                Text(store.t("Plans the instructions and reference views before the image model renders them.",
                             "先规划提示词和参考视角，再由生图模型绘制图片。"))
                    .font(.caption).foregroundStyle(.secondary)
                if CraftAIAccount.enabledForRelease {
                Button { accountOpen = true } label: {
                    Label(store.aiAccount.connected ? store.t("Manage ChatGPT connection", "管理 ChatGPT 连接") : store.t("Connect ChatGPT for more models", "连接 ChatGPT 使用更多模型"),
                          systemImage: "person.crop.circle")
                }.buttonStyle(CraftSecondary()).accessibilityIdentifier("planner.account")
                }
            }
        }
        .padding(14).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 20))
        .disabled(store.busy)
        .animation(CraftMotion.gated(.glide, reduceMotion), value: expanded)
        .sheet(isPresented: $accountOpen) { AIAccountView() }
    }

    private func modelRow(id: String, name: String) -> some View {
        Button { store.selectPlanner(id) } label: {
            HStack(spacing: 10) {
                Image(systemName: id == store.plannerModelID ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(appearance.ink)
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    if store.showPriceDetails { Text(store.plannerPriceLabel(id)).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(id == store.plannerModelID ? appearance.wash : .white, in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(CraftPressStyle()).accessibilityIdentifier("planner.model." + id)
            .accessibilityAddTraits(id == store.plannerModelID ? .isSelected : [])
    }
    private func effortName(_ value: String) -> String {
        let labels = ["none": store.t("None · Fastest", "无额外思考 · 最快"), "minimal": store.t("Minimal", "极低"),
                      "low": store.t("Low · Fast", "低 · 快速"), "medium": store.t("Medium", "中"), "high": store.t("High", "高")]
        return labels[value] ?? value
    }
}
