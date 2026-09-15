import SwiftUI
import StoreKit
import RevenueCat
import RevenueCatUI

/// Commercial catalog is intentionally separate from the legacy review wallet.
struct CreatorPlanCatalog: Decodable {
    struct Plan: Decodable, Identifiable {
        let id: String
        let name: String
        let period: String
        let usd: String
        let credits: Int
        let package: String?
    }
    struct Topup: Decodable, Identifiable {
        let id: String
        let name: String
        let period: String
        let usd: String
        let credits: Int
        let package: String?
    }
    struct Example: Decodable {
        let completeCreationCredits: Int
        let fourConceptCreationCredits: Int
        let rodinOnlyCredits: Int
    }
    let plans: [Plan]
    let topups: [Topup]?
    let example: Example
    static var bundled: CreatorPlanCatalog? {
        guard let url = Bundle.main.url(forResource: "CommercePlans", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}

/// App-owned presentation; RevenueCat and StoreKit handle purchase authorization.
struct CreatorPlansView: View {
    @EnvironmentObject private var store: CraftStore
    @EnvironmentObject private var billing: BillingManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var topups = false
    @State private var selectedID = "craft.creator.monthly.v1"
    @State private var purchasing = false
    @State private var message: String?
    @State private var failed = false
    @State private var showCosts = false

    private let catalog = CreatorPlanCatalog.bundled
    private let green = CraftAppearance.emerald.ink
    private let mint = CraftAppearance.emerald.fill
    private let canvas = Color(red: 244/255, green: 250/255, blue: 247/255)
    private func t(_ en: String, _ zh: String) -> String { store.t(en, zh) }
    private var credits: Int {
        if topups { return catalog?.topups?.first { $0.id == selectedID }?.credits ?? 0 }
        return catalog?.plans.first { $0.id == selectedID }?.credits ?? 0
    }
    private var price: String? { billing.package(for: selectedID)?.localizedPriceString }
    private var currentPlan: Bool { !topups && billing.hasCreatorEntitlement && billing.activePlanID == selectedID }
    private var monthlyToWeekly: Bool {
        !topups && billing.hasCreatorEntitlement && billing.activePlanID == "craft.creator.monthly.v1"
            && selectedID == "craft.creator.weekly.v1"
    }
    private var period: String { selectedID == "craft.creator.weekly.v1" ? t("week", "周") : t("month", "月") }
    private var cta: String {
        if purchasing { return t("Please wait…", "请稍候……") }
        if currentPlan { return t("Current plan", "当前套餐") }
        if monthlyToWeekly { return t("Monthly plan active", "月订阅生效中") }
        guard let price else { return t("Reload prices", "重新加载价格") }
        return topups ? t("Get \(credits) Tokens · \(price)", "购买 \(credits) Tokens · \(price)")
                      : t("Subscribe · \(price)/\(period)", "订阅 · \(price)/\(period)")
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    hero(height: typeSize.isAccessibilitySize ? 160 : min(200, max(120, geometry.size.height * 0.21)))
                    VStack(spacing: 14) {
                        categoryPicker
                        if topups {
                            ForEach(catalog?.topups ?? []) { pack in
                                option(id: pack.id, title: t("\(pack.credits) Tokens", "\(pack.credits) Tokens"),
                                       subtitle: t("One-time · Never expires", "一次购买 · 永不过期"),
                                       usd: pack.usd, interval: nil)
                            }
                        } else {
                            ForEach((catalog?.plans ?? []).sorted { $0.period == "month" && $1.period != "month" }) { plan in
                                option(id: plan.id, title: plan.period == "month" ? t("Monthly", "月订阅") : t("Weekly", "周订阅"),
                                       subtitle: plan.period == "month" ? t("\(plan.credits) Tokens / month", "每月 \(plan.credits) Tokens") : t("\(plan.credits) Tokens / week", "每周 \(plan.credits) Tokens"),
                                       usd: plan.usd, interval: plan.period == "month" ? t("month", "月") : t("week", "周"))
                            }
                        }
                        if let unit = store.modelTokenCost("rodin") ?? catalog?.example.rodinOnlyCredits, unit > 0 {
                            Text(t("≈ \(credits / unit) Rodin objects · 3D only", "约 \(credits / unit) 个 Rodin 模型 · 仅计算 3D"))
                                .font(.caption.weight(.medium)).foregroundStyle(green)
                            Text(t("3D only. Images and chat may use additional Tokens. Costs vary by model.", "仅计算 3D。图片和对话可能另耗 Tokens，费用随模型不同。"))
                                .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                        if let message {
                            Label(message, systemImage: failed ? "exclamationmark.circle" : "checkmark.circle")
                                .font(.footnote).foregroundStyle(failed ? Color.red : green)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("paywall.message")
                        }
                        DisclosureGroup(t("How Tokens work", "Tokens 如何使用"), isExpanded: $showCosts) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(t("Your own ChatGPT prompts and images: 0 app Tokens. 3D costs depend on your chosen model and include the 15% service fee.", "使用自己的 ChatGPT 提示词和图片：0 App Tokens。3D 按所选模型计费，已含 15% 服务费。"))
                                Text(t("See the Token cost before each creation. Unused paid Tokens roll over.", "每次创作前确认 Token 费用，未使用的付费 Tokens 可结转。"))
                                Text(t("Weekly to monthly: Apple handles the new charge and any prorated refund for the unused weekly period. Check Apple's confirmation before paying.", "周订阅升级月订阅：Apple 处理新套餐扣款及周订阅未使用时段的按比例退款，请以 Apple 确认页为准。"))
                                Text(t("Cancel to stop future renewals. Cancellation does not automatically refund the current period; refund requests are handled by Apple.", "取消后停止后续续费，本期不会因取消自动退款；退款申请由 Apple 处理。"))
                            }.font(.caption).foregroundStyle(green.opacity(0.8)).padding(.top, 8)
                        }.font(.caption.weight(.semibold)).tint(green)
                    }
                    .padding(22)
                    .frame(maxWidth: 560)
                    .background(.white, in: RoundedRectangle(cornerRadius: 30))
                }.frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { purchaseFooter }
            .background(canvas)
        }
        .tint(green)
        .accessibilityIdentifier("paywall.custom")
        .task {
            await billing.loadProducts()
            if let uid = CraftAccount.shared.uid {
                await billing.checkRevenueCatStatus(userId: uid)
                try? await billing.reconcileWallet(store: store, force: true)
            }
        }
    }

    private func hero(height: CGFloat) -> some View {
        VStack(spacing: 8) {
            HStack {
                Label("3D Craft", systemImage: "cube.fill").font(.headline).foregroundStyle(green)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.subheadline.weight(.semibold))
                        .frame(width: 44, height: 44).background(.white.opacity(0.85), in: Circle())
                }.accessibilityLabel(t("Close", "关闭")).accessibilityIdentifier("paywall.close")
            }
            Text(t("Big adventures.\nStart with one idea.", "大大的冒险，\n从一个灵感开始。"))
                .font(.system(size: 27, weight: .bold, design: .rounded)).tracking(-0.7)
                .multilineTextAlignment(.center).foregroundStyle(green)
                .fixedSize(horizontal: false, vertical: true)
            ZStack {
                Ellipse().fill(mint.opacity(0.16)).frame(width: height * 1.35, height: height * 0.86).rotationEffect(.degrees(-16))
                Ellipse().stroke(green.opacity(0.12), lineWidth: 1).frame(width: height * 1.55, height: height * 0.9).rotationEffect(.degrees(-16))
                Image("PaywallExplorer").resizable().scaledToFit()
                    .blendMode(.multiply)
                    .mask(RadialGradient(stops: [.init(color: .white, location: 0.72), .init(color: .clear, location: 1)], center: .center, startRadius: 0, endRadius: height * 0.7))
                    .accessibilityLabel(t("Lantern Explorer, a 3D Craft character", "3D Craft 提灯探险猫角色"))
            }.frame(height: height)
            Text(t("Your ideas. Ready for 3D.", "创造角色、概念图与 3D 模型。"))
                .font(.subheadline).foregroundStyle(green.opacity(0.8)).multilineTextAlignment(.center)
        }.padding(.horizontal, 24).padding(.top, 6).padding(.bottom, 18)
    }

    private var categoryPicker: some View {
        HStack(spacing: 4) {
            category(t("Subscriptions", "订阅"), isTopup: false)
            category(t("Token packs", "Token 包"), isTopup: true)
        }.padding(4).background(canvas, in: Capsule())
    }
    private func category(_ title: String, isTopup: Bool) -> some View {
        Button {
            topups = isTopup
            selectedID = isTopup ? (catalog?.topups?.first?.id ?? "craft.credits.small.v1") : "craft.creator.monthly.v1"
            message = nil
        } label: {
            Text(title).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(topups == isTopup ? mint.opacity(0.5) : .clear, in: Capsule())
        }.disabled(purchasing).accessibilityAddTraits(topups == isTopup ? [.isSelected] : [])
        .accessibilityIdentifier(isTopup ? "paywall.topups" : "paywall.subscriptions")
    }
    private func option(id: String, title: String, subtitle: String, usd: String, interval: String?) -> some View {
        let selected = selectedID == id
        let displayPrice = billing.displayPrice(for: id) ?? "US$\(usd)"
        return Button { selectedID = id; message = nil } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(selected ? green : green.opacity(0.3))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(green.opacity(0.8))
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(displayPrice).font(.headline).monospacedDigit()
                    Text(interval.map { "/\($0)" } ?? t("once", "一次性")).font(.caption).foregroundStyle(green.opacity(0.8))
                }
            }.foregroundStyle(green).padding(16).frame(maxWidth: .infinity, minHeight: 78)
                .background(selected ? mint.opacity(0.15) : .white, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(selected ? green : green.opacity(0.14), lineWidth: selected ? 2 : 1))
        }.buttonStyle(.plain).disabled(purchasing)
         .accessibilityAddTraits(selected ? [.isSelected] : [])
         .accessibilityIdentifier("paywall.option.\(id)")
    }
    private var purchaseFooter: some View {
        VStack(spacing: 10) {
            Button {
                if price == nil {
                    Task {
                        message = nil
                        await billing.loadProducts()
                        failed = price == nil
                        message = failed
                            ? t("Apple has not made this Token pack available yet. Please try again later. No purchase was made and no Tokens were charged.", "Apple 暂未提供此商品，请稍后重试。尚未购买，也未扣除 Tokens。")
                            : t("Prices loaded. Tap the purchase button to continue with Apple.", "价格已加载，请点击购买按钮继续 Apple 付款。")
                    }
                }
                else { buy() }
            } label: {
                HStack {
                    if purchasing || billing.isLoading { ProgressView().tint(.white) }
                    Text(cta).font(.headline)
                }.frame(maxWidth: .infinity, minHeight: 52)
                    .background(green, in: Capsule()).foregroundStyle(.white)
            }.disabled(purchasing || billing.isLoading || currentPlan)
             .disabled(monthlyToWeekly)
             .accessibilityIdentifier("paywall.purchase")
            if monthlyToWeekly {
                Text(t("Your monthly plan continues until its end date. Manage future plan changes with Apple below.", "当前月订阅持续至到期日。可在下方通过 Apple 管理下一期套餐。"))
                    .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Text(topups ? t("One-time purchase. No automatic renewal.", "一次性购买，不会自动续费。")
                        : t("Renews every \(period) until cancelled. No free trial.", "每\(period)自动续订，直到取消。无免费试用。"))
                .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if billing.hasCreatorEntitlement, let managementURL = billing.customerInfo?.managementURL {
                Link(t("Manage or cancel subscription", "管理或取消订阅"), destination: managementURL)
                    .font(.caption.weight(.medium)).accessibilityIdentifier("paywall.manageSubscription")
            }
            HStack(spacing: 22) {
                Button(t("Restore", "恢复购买")) { restore() }.disabled(purchasing)
                    .accessibilityIdentifier("paywall.restore")
                Link(t("Terms", "条款"), destination: URL(string: "https://3d-craft.web.app/terms")!)
                Link(t("Privacy", "隐私"), destination: URL(string: "https://3d-craft.web.app/privacy")!)
            }.font(.caption.weight(.medium)).padding(.vertical, 3)
        }.padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 8)
         .frame(maxWidth: 560).frame(maxWidth: .infinity)
         .background(.white.shadow(.drop(color: green.opacity(0.06), radius: 12, y: -5)))
    }

    private func buy() {
        guard !purchasing, let uid = CraftAccount.shared.uid else {
            failed = true; message = t("Sign in to your 3D Craft account before purchasing.", "请先登录 3D Craft 账户再购买。")
            return
        }
        let id = selectedID
        purchasing = true; message = nil; failed = false
        Task {
            defer { purchasing = false }
            do {
                try await billing.ensurePurchaseAccount(uid)
                await billing.refreshEntitlements()
                guard !(id == "craft.creator.weekly.v1" && billing.hasCreatorEntitlement && billing.activePlanID == "craft.creator.monthly.v1") else {
                    message = t("Your monthly plan is active. Use Manage subscription for future changes.", "当前月订阅生效中，请通过管理订阅设置下一期变更。")
                    return
                }
                guard let package = billing.package(for: id) else {
                    throw CraftError(message: t("This product is unavailable. Please reload prices and try again.", "此商品暂不可用，请重新加载价格后再试。"))
                }
                guard CraftAccount.shared.uid == uid else { throw CraftError(message: "Please sign in again before purchasing.") }
                let (_, cancelled) = try await billing.purchase(package: package)
                if cancelled { return }
                guard let tid = billing.lastPurchaseTransactionID, let actualID = billing.lastPurchaseProductID else {
                    try await billing.reconcileWallet(store: store, force: true)
                    message = t("Apple returned no new transaction. Your current purchases have been checked.", "Apple 未返回新交易，已核对当前购买记录。")
                    return
                }
                let delivery = BillingManager.PendingCredit(userID: uid, productID: actualID, transactionID: tid, showSuccess: actualID == id)
                billing.rememberCredit(delivery)
                do {
                    guard CraftAccount.shared.uid == uid else { throw CraftError(message: "Sign in to the purchasing account to sync Tokens.") }
                    try await store.creditRevenueCatPurchase(productID: actualID, transactionID: tid, presentPurchase: actualID == id)
                    billing.acknowledgeCredit(delivery)
                    message = actualID == id
                        ? t("Purchase synced. Your balance is \(store.wallet.available) Tokens.", "购买已同步，当前余额为 \(store.wallet.available) Tokens。")
                        : t("Apple returned your existing subscription. No extra Tokens were added for a future plan change.", "Apple 返回了现有订阅；尚未生效的套餐变更不会额外发放 Tokens。")
                } catch {
                    failed = true
                    message = t("Purchase confirmed, but Tokens have not synced yet. Please use Restore; do not purchase again.", "购买已确认，但 Tokens 尚未同步。请使用恢复购买，无需再次购买。")
                }
            } catch {
                if (error as NSError).code == RevenueCat.ErrorCode.purchaseCancelledError.rawValue { return }
                if billing.state == .pendingApproval {
                    message = t("Waiting for Apple approval. Tokens will be added after approval; no need to purchase again.", "正在等待 Apple 批准，批准后 Tokens 会到账，无需重复购买。")
                    return
                }
                failed = true; message = error.localizedDescription
            }
        }
    }
    private func restore() {
        guard !purchasing, let uid = CraftAccount.shared.uid else { return }
        purchasing = true; message = nil; failed = false
        Task {
            defer { purchasing = false }
            do {
                try await billing.ensurePurchaseAccount(uid)
                _ = try await billing.restoreRevenueCatPurchases()
                guard CraftAccount.shared.uid == uid else { throw CraftError(message: "Sign in to the purchasing account to restore Tokens.") }
                try await billing.reconcileWallet(store: store, force: true)
                await store.refresh()
                message = t("Purchases checked. Your current Token balance is \(store.wallet.available).", "已检查购买记录，当前 Token 余额为 \(store.wallet.available)。")
            } catch { failed = true; message = error.localizedDescription }
        }
    }
}
