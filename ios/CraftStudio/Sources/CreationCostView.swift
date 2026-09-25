import SwiftUI

struct PricingDetailsToggle: View {
    @EnvironmentObject private var store: CraftStore
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    var body: some View {
        Toggle(isOn: $store.showPriceDetails) {
            Label(store.t("Technical price details", "显示技术价格详情"), systemImage: "slider.horizontal.3")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .tint(appearance.ink)
        .accessibilityIdentifier("pricing.details.toggle")
    }
}

/// A separate destination keeps cost details out of the creative canvas.
struct CreationCostButton: View {
    @EnvironmentObject private var store: CraftStore
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    var projectID: String? = nil
    var imageCount: Int = 4
    var iconOnly = true
    @State private var open = false
    var body: some View {
        Button { open = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.forwardslash.minus")
                if !iconOnly { Text(store.t("Creation costs", "创作费用计算器")) }
            }
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(appearance.ink)
            .frame(minWidth: 44, minHeight: 44)
            .padding(.horizontal, iconOnly ? 0 : 16)
            .background(.white.opacity(0.85), in: Capsule())
        }
        .buttonStyle(CraftPressStyle())
        .accessibilityLabel(store.t("Creation cost calculator", "创作费用计算器"))
        .accessibilityIdentifier("pricing.calculator.open")
        .sheet(isPresented: $open) {
            CreationCostView(projectID: projectID, initialImageCount: imageCount)
        }
    }
}

struct CreationCostView: View {
    @EnvironmentObject private var store: CraftStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    @State private var selectedProject: String
    @State private var imageCount: Int
    @State private var includeModel = true
    @State private var engine = "tripo"
    init(projectID: String?, initialImageCount: Int) {
        _selectedProject = State(initialValue: projectID ?? "")
        _imageCount = State(initialValue: initialImageCount)
    }
    private var usage: CraftSpendSummary {
        CraftSpendSummary(jobs: store.jobs, projectID: selectedProject.isEmpty ? nil : selectedProject)
    }
    private var planned: Int? {
        guard let model = includeModel ? store.modelTokenCost(engine) : 0 else { return nil }
        return store.conceptTokenCost(count: imageCount) + model
    }
    private var knownProviderEstimate: Double? {
        let imageCost: Double?
        if imageCount == 0 || store.imageModelID == "codex-gpt-image-2" { imageCost = 0 }
        else if let rate = store.modelPrices[store.imageModelID], rate.unit == "image", let price = rate.unitUsd { imageCost = price * Double(imageCount) }
        else { imageCost = nil }
        let modelCost: Double? = includeModel ? store.modelPrices[engine]?.modelCost(views: 1) : 0
        guard let imageCost, let modelCost else { return nil }
        return imageCost + modelCost
    }


    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Picker(store.t("Scope", "统计范围"), selection: $selectedProject) {
                        Text(store.t("All creations", "全部创作")).tag("")
                        ForEach(store.projects) { project in Text(project.name).tag(project.id) }
                    }.tint(appearance.ink).accessibilityIdentifier("pricing.scope")
                    spendingCard
                    budgetCard
                    PricingDetailsToggle()
                    if store.showPriceDetails { technicalDetails }
                }
                .padding(22)
            }
            .accessibilityIdentifier("pricing.calculator.scroll")
            .background { StudioAtmosphere(intensity: 0.65) }
            .navigationTitle(store.t("Creation costs", "创作费用"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(store.t("Done", "完成")) { dismiss() }.accessibilityIdentifier("pricing.calculator.done") } }
            .refreshable { await store.refresh() }
            .task { await store.refresh() }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: planned)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: store.showPriceDetails)
        }
        .tint(appearance.ink)
        .preferredColorScheme(.light)
    }

    private var spendingCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(store.t("Consumed so far", "已消耗"), systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(store.t("APP CREDITS", "APP 积分")).font(.caption2.weight(.semibold)).tracking(1)
            }.foregroundStyle(appearance.ink)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(usage.spent)").font(.system(size: 48, weight: .bold, design: .rounded))
                    .contentTransition(.numericText()).accessibilityIdentifier("pricing.spent")
                Text("Tokens").font(.headline).foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(appearance.ink.opacity(0.12))
                    if usage.spent > 0 {
                        Capsule().fill(appearance.ink)
                            .frame(width: geometry.size.width * Double(usage.spent(model: false)) / Double(usage.spent))
                    }
                }
            }.frame(height: 7).accessibilityHidden(true)
            spendRow(store.t("Concepts & refinements", "概念图与修改"), icon: "photo.on.rectangle", value: usage.spent(kind: "concepts"))
            spendRow(store.t("3D models", "3D 模型"), icon: "cube.transparent", value: usage.spent(kind: "model"))
            if usage.spent(kind: "animation") > 0 {
                spendRow(store.t("Character animations", "角色动画"), icon: "film.stack", value: usage.spent(kind: "animation"))
            }
            Divider().opacity(0.5)
            HStack {
                Label(store.t("In progress · Reserved", "处理中 · 已预留"), systemImage: "clock")
                Spacer()
                Text("\(usage.reserved) Tokens").monospacedDigit()
            }.font(.caption).foregroundStyle(.secondary)
            Text(store.t("Reserved credits are not counted as consumed. Unused credits are returned when a job settles.", "预留积分不计入已消耗；任务结算时会退回未使用积分。"))
                .font(.caption2).foregroundStyle(.secondary)
            if usage.unrecorded > 0 {
                Text(store.t("\(usage.unrecorded) older records have no recorded cost and are excluded.", "\(usage.unrecorded) 条历史记录缺少费用，未计入总数。"))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if !store.connected { Text(store.t("Offline · Last saved usage", "离线 · 显示上次保存的用量")).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(22)
        .background(LinearGradient(colors: [appearance.wash, .white], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(appearance.hairline, lineWidth: 1))
    }

    private var budgetCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(store.t("Plan your next step", "计算下一步预算"), systemImage: "sparkles").font(.headline)
            Stepper(value: $imageCount, in: 0...4) {
                Label(store.t("\(imageCount) concept images", "\(imageCount) 张概念图"), systemImage: "photo")
            }.accessibilityIdentifier("pricing.budget.images")
            Toggle(isOn: $includeModel) {
                Label(store.t("Add a 3D model", "再生成一个 3D 模型"), systemImage: "cube")
            }.accessibilityIdentifier("pricing.budget.model")
            if includeModel {
                Picker(store.t("3D engine", "3D 引擎"), selection: $engine) {
                    Text("Tripo H3.1").tag("tripo")
                    Text("Seed3D 2.0").tag("seed3d")
                    Text("Rodin (Ultra)").tag("rodin")
                    Text("Hunyuan Rapid").tag("hunyuan-rapid")
                    Text("Hunyuan Pro").tag("hunyuan-pro")
                    Text("HI3D v2.1 Fast").tag("hi3d-fast")
                    Text("HI3D v2.1 Pro").tag("hi3d-pro")
                    Text("HI3D v3.0 Quality").tag("hi3d-quality")
                    Text("HI3D v3.0 Master").tag("hi3d-master")
                    Text("Meshy v7").tag("meshy-single")
                    Text("Meshy v7 Multi").tag("meshy-multi")
                    Text("TRELLIS.2").tag("trellis-2")
                    Text(store.t("Hunyuan 2 · Textured", "Hunyuan 2 · 带纹理")).tag("hunyuan3d-2.1")
                    Text(store.t("Hunyuan 2 · White mesh", "Hunyuan 2 · 白模")).tag("hunyuan3d-2-white")
                    if store.cloudModelEngineIDs.contains("hybrid") {
                        Text("Hybrid").tag("hybrid")
                    }
                }
            }
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.t("Planned credits", "预计积分")).font(.subheadline.weight(.semibold))
                    Text(store.t("Not yet spent", "尚未消费")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(planned.map { "\($0) Tokens" } ?? store.t("Price pending", "价格待确认")).font(.title3.bold()).foregroundStyle(appearance.ink)
                    .contentTransition(.numericText()).accessibilityIdentifier("pricing.budget.total")
            }
            Text(store.t("Images \(store.conceptTokenCost(count: imageCount)) + 3D \(includeModel ? store.modelTokenLabel(engine) : "0 Tokens"). Generation is confirmed separately.", "图片 \(store.conceptTokenCost(count: imageCount)) + 3D \(includeModel ? store.modelTokenLabel(engine) : "0 Tokens")。实际生成时会另行确认。"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(22).background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 28))
        .craftDepth(.card)
    }

    private var technicalDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(store.t("Provider estimate · USD", "供应商成本估算 · 美元")).font(.headline)
            if imageCount > 0 { Text(store.conceptPriceSummary(count: imageCount)) }
            if includeModel { Text("3D · " + store.modelPriceLabel(engine)) }
            Divider()
            Text(store.t("15% service fee on costs paid by 3D Craft. Your own ChatGPT chat and image usage costs 0 app Tokens.", "仅 3D Craft 支付的供应商费用加收 15% 服务费。使用你自己的 ChatGPT 对话和图片服务为 0 App Tokens。"))
            if let subtotal = knownProviderEstimate {
                Text(store.t("Known image + 3D portion: \(CraftModelPrice.usd(subtotal))", "已知图片与 3D 部分：\(CraftModelPrice.usd(subtotal))"))
                Text(store.t("Service fee on this portion: \(CraftModelPrice.usd(subtotal * store.serviceFeeRate))", "此部分服务费：\(CraftModelPrice.usd(subtotal * store.serviceFeeRate))"))
                Text(store.t("Including fee: \(CraftModelPrice.usd(subtotal * (1 + store.serviceFeeRate)))", "含服务费：\(CraftModelPrice.usd(subtotal * (1 + store.serviceFeeRate)))"))
            }
            Text(store.t("The confirmed 3D Token price is shown before generation. This calculator estimates future work and does not charge your wallet.", "生成前会显示本次 3D 所需的 Tokens。此计算器仅估算后续创作费用，不会扣除钱包余额。"))
            Text(store.t("API dollar costs are estimates, not recorded charges. Actual token usage and provider invoices determine the dollar total.", "美元为 API 成本估算，并非已扣款。实际 token 用量和供应商账单决定美元总额。"))
            Text(store.t("Rates verified ", "价格核实日期：") + store.pricesVerifiedAt)
        }.font(.caption).foregroundStyle(.secondary)
            .padding(18).background(appearance.washSoft, in: RoundedRectangle(cornerRadius: 22))
            .accessibilityIdentifier("pricing.calculator.technical")
    }
    private func spendRow(_ title: String, icon: String, value: Int) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Text("\(value) Tokens").fontWeight(.semibold).monospacedDigit()
        }.font(.subheadline)
    }
}
