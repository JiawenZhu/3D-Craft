import SwiftUI
import StoreKit

/// Tokens, presence and hierarchy — with every cost, disclosure and
/// "local test purchase" sentence unchanged from the reviewed build.
struct PaywallView: View {
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    @EnvironmentObject var store: CraftStore
    @EnvironmentObject var billing: BillingManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showBillingTest = false
    @State private var selectedID = "craft.creator.weekly300"
    @State private var processing = false
    @State private var purchaseError: String?
    @State private var confirmation: String?
    @State private var legalPage: LegalPage?
    @State private var successCount = 0
    @State private var failureCount = 0
    @State private var scrollY: CGFloat = 0

    private let panel = CraftTheme.panel
    private let rose = Color(red: 0.65, green: 0.19, blue: 0.12)
    private var lilac: Color { appearance.ink }
    private var accent: LinearGradient { appearance.gradient }
    private var selectedProduct: Product? { billing.products.first { $0.id == selectedID } }

    var startOnTopups: Bool = false

    var body: some View {
        CreatorPlansView(startOnTopups: startOnTopups).preferredColorScheme(.light)
    }

    // MARK: - The free testing card (the primary path in this build)

    private var testingCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 11) {
                Image(systemName: "sparkles")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(lilac)
                    .frame(width: 40, height: 40)
                    .background(appearance.washStrong, in: Circle())
                    .accessibilityHidden(true)
                Text(store.t("Generation testing", "生成能力测试"))
                    .font(.title2.bold())
            }
            .accessibilityElement(children: .combine)
            .craftEntrance(0)

            Text(store.t("No subscription needed. Use free test Tokens to create concepts and 3D models with the real generation pipeline.", "无需订阅。使用免费测试额度，直接体验真实的概念图和 3D 模型生成。"))
                .foregroundStyle(.secondary)
                .craftEntrance(1)

            Text(store.t("Available: \(store.wallet.available) test Tokens", "可用：\(store.wallet.available) 测试 Tokens"))
                .font(.headline)
                .craftNumeric(store.wallet.available, reduceMotion: reduceMotion)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(appearance.wash, in: Capsule(style: .continuous))
                .craftEntrance(2, style: .popIn)

            Button {
                Task { await store.replenishTestCredits() }
            } label: {
                Text(store.t("Refill to 1,000 test Tokens", "免费补充至 1,000 测试 Tokens"))
            }
            // Armed only while a refill would actually change something, so the
            // capsule never sweeps at rest.
            .buttonStyle(CraftPrimary(armed: !showBillingTest && store.wallet.available < 1000,
                                      busy: store.busy))
            .accessibilityIdentifier("refillTestCredits")
            .craftEntrance(3)

            Text(store.t("For local review only. No payment or subscription is created.", "仅限本地测试，不会付款或创建订阅。"))
                .font(.caption).foregroundStyle(.secondary)
                .craftEntrance(4)
        }
        .padding(20)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .craftDepth(.raised)
    }

    // MARK: - The optional StoreKit test surface

    private var billingDisclosure: some View {
        DisclosureGroup(isExpanded: $showBillingTest) {
            VStack(alignment: .leading, spacing: 22) {
                Label(store.t("StoreKit test · No real charges", "StoreKit 测试 · 不会实际扣费"), systemImage: "testtube.2")
                    .font(.caption.weight(.semibold)).foregroundStyle(lilac)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(lilac.opacity(0.1), in: Capsule())

                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 42)).foregroundStyle(accent)
                    Text(store.t("Big ideas.\nMade into 3D.", "把奇思妙想，\n变成 3D。"))
                        .font(.system(size: 36, weight: .bold, design: .rounded)).tracking(-1)
                    Text(store.t("Choose a plan. Create at your own pace.", "选择适合你的额度，按自己的节奏创作。"))
                        .font(.subheadline).foregroundStyle(.black.opacity(0.6))
                }

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.t("Your balance", "当前余额")).font(.caption).foregroundStyle(.black.opacity(0.55))
                        Text("\(store.wallet.available) Tokens").font(.title3.bold())
                            .craftNumeric(store.wallet.available, reduceMotion: reduceMotion)
                    }
                    Spacer()
                    Image(systemName: "circle.hexagongrid.fill").font(.title2).foregroundStyle(accent)
                }
                .padding(18)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .craftDepth(.card)

                VStack(spacing: 12) {
                    productCard(id: "craft.creator.weekly300", title: store.t("Creator Weekly", "创作者周订阅"), tokens: 300,
                                detail: store.t("9 concepts + 3 standard 3D assets", "9 张概念图 + 3 个标准 3D 资产"), recurring: true)
                    productCard(id: "craft.starter100", title: store.t("Starter Pack", "体验包"), tokens: 100,
                                detail: store.t("3 concepts + 1 standard 3D asset", "3 张概念图 + 1 个标准 3D 资产"), recurring: false)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text(store.t("Make the mix your own", "自由搭配你的创作额度")).font(.headline)
                    rateRow("photo.on.rectangle.angled", store.t("One Gemini 2K concept", "一张 Gemini 2K 概念图"), "15 Tokens")
                    rateRow("cube.transparent", store.t("One textured Rodin 3D asset", "一个带纹理 Rodin 3D 资产"), store.modelTokenLabel("rodin"))
                    Text(store.t("The examples use these rates: 3D Token costs vary by model and include the service fee. Your own ChatGPT images cost 0 app Tokens; 3D generation is charged separately. See the exact cost before you create.", "以上组合按此计算：3D Token 费用依模型成本计算，包含服务费。自己的 ChatGPT 图片为 0 App Tokens，3D 生成单独扣费，提交前会显示准确费用。"))
                        .font(.caption).foregroundStyle(.black.opacity(0.58)).fixedSize(horizontal: false, vertical: true)
                    Label(store.t("Unspent paid Tokens never expire", "未使用的付费 Tokens 不过期"), systemImage: "checkmark.seal")
                        .font(.subheadline.weight(.medium)).foregroundStyle(lilac)
                }
                .padding(18)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .craftDepth(.card)

                if let message = purchaseError ?? billing.error {
                    Label(message, systemImage: "exclamationmark.circle")
                        .font(.footnote).foregroundStyle(rose).fixedSize(horizontal: false, vertical: true)
                        .padding(14)
                        .background(rose.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .transition(.opacity)
                }
                if let confirmation {
                    Label(confirmation, systemImage: "checkmark.circle.fill").font(.footnote).foregroundStyle(.green)
                        .padding(14)
                        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay { CraftSparkleBurst(trigger: successCount, tint: appearance.deep, count: 10, radius: 70) }
                        .transition(.opacity)
                }
                if billing.state == .pendingApproval {
                    Text(store.t("Waiting for purchase approval. Tokens will appear after approval and verification.", "正在等待购买批准，批准并验证后会到账。"))
                        .font(.footnote).foregroundStyle(lilac)
                }
                if !billing.isLoading && selectedProduct == nil {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(store.t("Products are unavailable", "暂时无法加载商品")).font(.headline)
                        Text(store.t("For this local review, launch from Xcode with Configuration/Products.storekit selected in the Run scheme. A direct simulator launch may not activate StoreKit testing.", "本地验收时，请在 Xcode 的 Run Scheme 中选用 Configuration/Products.storekit 后运行。直接启动模拟器 App 可能不会激活 StoreKit 测试。"))
                            .font(.caption).foregroundStyle(.black.opacity(0.65))
                        Button(store.t("Retry loading products", "重新加载商品")) { Task { await billing.loadProducts() } }
                            .font(.subheadline.bold()).foregroundStyle(lilac)
                            .buttonStyle(CraftPressStyle())
                    }
                    .padding(16)
                    .background(panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                Button(action: buy) {
                    HStack(spacing: 10) {
                        if processing || billing.isLoading { ProgressView().tint(appearance.buttonInk) }
                        Text(purchaseTitle)
                            .contentTransition(.opacity)
                    }
                }
                .buttonStyle(CraftPrimary(armed: selectedProduct != nil && !processing && !billing.isLoading,
                                          busy: processing || billing.isLoading))
                .disabled(processing || billing.isLoading || selectedProduct == nil)
                .accessibilityIdentifier("purchaseTokens")
                .animation(CraftMotion.gated(.glide, reduceMotion), value: purchaseTitle)

                Text(selectedID == "craft.creator.weekly300"
                     ? store.t("300 Tokens each week. Automatically renews at the displayed weekly price until cancelled. Cancel in Apple subscription settings. This review build uses simulated purchases only.", "每周获得 300 Tokens。按显示的周价格自动续订，直到取消。可在 Apple 订阅设置中取消。本验收版本仅使用模拟购买。")
                     : store.t("A one-time purchase of 100 Tokens. No subscription and no automatic renewal. This review build uses simulated purchases only.", "一次性获得 100 Tokens，无订阅、无自动续费。本验收版本仅使用模拟购买。"))
                    .font(.caption).foregroundStyle(.black.opacity(0.5)).multilineTextAlignment(.center)
                    .contentTransition(.opacity)
                    .animation(CraftMotion.gated(.brush, reduceMotion), value: selectedID)

                HStack {
                    Button(store.t("Restore", "恢复购买"), action: restore).disabled(processing)
                    Spacer()
                    Button(store.t("Terms", "条款")) { legalPage = .terms }
                    Spacer()
                    Button(store.t("Privacy", "隐私")) { legalPage = .privacy }
                }
                .font(.caption.weight(.medium)).foregroundStyle(.black.opacity(0.65))
                .buttonStyle(CraftPressStyle())
            }
            .padding(.top, 14)
        } label: {
            Text(store.t("Optional: test billing screens", "可选：测试收费页面"))
                .font(.subheadline.weight(.medium))
        }
        .tint(lilac)
        .padding(18)
        .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(CraftTheme.stroke)
        )
        .animation(CraftMotion.gated(.glide, reduceMotion), value: showBillingTest)
        .animation(CraftMotion.gated(.glide, reduceMotion), value: confirmation)
        .animation(CraftMotion.gated(.glide, reduceMotion), value: purchaseError)
        .craftEntrance(5)
    }

    private var purchaseTitle: String {
        if processing { return store.t("Verifying purchase…", "正在验证购买…") }
        if billing.isLoading { return store.t("Loading plans…", "正在加载套餐…") }
        guard let product = selectedProduct else { return store.t("Purchases unavailable", "购买暂不可用") }
        return store.t("Test purchase · \(product.displayPrice)", "测试购买 · \(product.displayPrice)")
    }

    private func productCard(id: String, title: String, tokens: Int, detail: String, recurring: Bool) -> some View {
        let selected = id == selectedID
        let product = billing.products.first { $0.id == id }
        return Button {
            withAnimation(CraftMotion.gated(.snap, reduceMotion)) { selectedID = id }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title).font(.headline)
                        Text("\(tokens) Tokens").font(.title2.bold()).foregroundStyle(selected ? lilac : .primary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 5) {
                        Text(product?.displayPrice ?? "—").font(.title3.bold())
                        Text(recurring ? store.t("per week", "每周") : store.t("one time", "一次性"))
                            .font(.caption).foregroundStyle(.black.opacity(0.5))
                    }
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? lilac : .black.opacity(0.25))
                        .craftSymbolPop(selected, reduceMotion: reduceMotion)
                }
                Text(detail).font(.subheadline).foregroundStyle(.black.opacity(0.7))
            }
            .padding(18)
            .background(selected ? appearance.wash : Color.white,
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .craftSelectionRing(selected, color: appearance.fill, cornerRadius: 22, lineWidth: 2, glow: false)
            .craftDepth(.card)
        }
        .buttonStyle(CraftLiftStyle(scale: 1.02))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .craftFeedback(.cardSelect, trigger: selectedID)
    }

    private func rateRow(_ icon: String, _ label: String, _ price: String) -> some View {
        HStack(alignment: .center, spacing: 11) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(lilac)
                .frame(width: 30, height: 30)
                .background(appearance.washSoft, in: Circle())
                .accessibilityHidden(true)
            Text(label).font(.subheadline)
            Spacer(minLength: 8)
            Text(price).font(.subheadline.weight(.semibold)).fixedSize()
        }
    }

    private func buy() {
        guard let product = selectedProduct else { return }
        processing = true
        purchaseError = nil
        confirmation = nil
        Task {
            defer { processing = false }
            guard let purchase = await billing.purchase(product) else { return }
            await deliver(purchase)
        }
    }

    @MainActor private func deliver(_ purchase: BillingManager.VerifiedPurchase) async {
        do {
            try await store.creditPurchase(purchase)
            await billing.finish(transactionID: purchase.transactionID)
            confirmation = store.t("Purchase verified. Your Tokens are ready.", "购买验证成功，额度已到账。")
            successCount += 1
        } catch {
            purchaseError = store.t("Purchase verified, but delivery needs retrying. Use Restore to retry safely. ", "购买验证成功，但额度到账需要重试。请使用“恢复购买”安全重试。") + error.localizedDescription
            failureCount += 1
        }
    }

    private func restore() {
        processing = true
        purchaseError = nil
        confirmation = nil
        Task {
            defer { processing = false }
            await billing.restore()
            let pending = billing.pendingVerifiedTransactions
            for purchase in pending { await deliver(purchase) }
            if pending.isEmpty && billing.error == nil {
                confirmation = store.t("Restore completed. No unfinished purchases were found. Previously delivered Tokens remain in your account balance.", "恢复完成，没有待到账的购买。此前已发放的额度保留在账户余额中。")
            }
        }
    }

    private enum LegalPage: String, Identifiable { case terms, privacy; var id: String { rawValue } }

    private func legalSheet(_ page: LegalPage) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(store.t("Local review build", "本地验收版本")).font(.title2.bold())
                        .craftEntrance(0)
                    if page == .terms {
                        Text(store.t("Purchases in this build are simulated by Apple's local StoreKit testing configuration. No real money is charged. Test Tokens are for reviewing the purchase and generation experience and are not a paid entitlement.", "此版本通过 Apple 本地 StoreKit 配置模拟购买，不会实际扣款。测试 Tokens 仅用于验收购买与生成流程，不构成真实付费权益。"))
                            .craftEntrance(1)
                        Text(store.t("Proposed launch plans: Starter Pack provides 100 Tokens once; Creator Weekly provides 300 Tokens every paid weekly renewal. Weekly subscriptions automatically renew unless cancelled through Apple. The product price shown by StoreKit is the applicable localized price.", "拟上线套餐：体验包一次性提供 100 Tokens；创作者周订阅每次付费周续订提供 300 Tokens。周订阅自动续订，可通过 Apple 取消。适用价格以 StoreKit 显示的本地化价格为准。"))
                            .craftEntrance(2)
                        Text(store.t("Gemini concepts cost 15 Tokens each; your own ChatGPT images cost 0 app Tokens and 3D asset costs depend on the selected model. The app shows the cost before a generation request. Unspent paid Tokens do not expire. Publishing requires final commercial terms and production payment verification.", "Gemini 概念图每张 15 Tokens，自己的 ChatGPT 图片为 0 App Tokens，3D 资产按所选模型计算费用。生成前会显示费用。未使用的付费余额不过期。正式发布前仍须完成正式商业条款与生产支付验证。"))
                            .craftEntrance(3)
                        Text(store.t("Intellectual Property & AI Outputs: AI models and 3D assets are generated via commercial provider APIs. Users must not submit prompts or reference materials that infringe upon third-party trademarks, copyrights, or proprietary rights. 3D Craft's bundled examples and games are original works or licensed for this application.", "知识产权与 AI 生成内容：AI 模型和 3D 资产通过商业供应商 API 生成。用户不得提交侵犯第三方商标、版权或专有权利的提示词或参考素材。3D Craft 内置示例与游戏均为原创或已获授权。"))
                            .craftEntrance(4)
                        Text(store.t("User Submissions & Community Games: By submitting a game, model, or link to the 3D Craft community, you warrant that you are the creator or hold all necessary rights, and grant 3D Craft a non-exclusive license to display, feature, and link to your content. A publicly accessible URL alone does not grant permission without author authorization. Objectionable or infringing content can be reported and will be removed.", "用户提交与社区游戏：向 3D Craft 社区提交游戏、模型或链接，即表示你保证拥有该内容的全部权利或合法授权，并授予 3D Craft 在 App 内展示及链接的非排他许可。未经授权的公开链接不得提交。侵权或不良内容可被举报并会被下架。"))
                            .craftEntrance(5)
                    } else {
                        Text(store.t("Photos, prompts, and uploaded files submitted for generation may be sent to the configured generation service. Only submit material you intend to process. Selecting a photo does not itself start generation.", "提交生成的照片、提示词和文件可能发送至配置的生成服务。请仅提交你打算处理的素材。选取照片本身不会开始生成。"))
                            .craftEntrance(1)
                        Text(store.t("StoreKit handles the purchase interface. This app does not collect card details. The development service receives the verified test transaction identifier and product identifier to record Tokens without duplicate grants.", "购买界面由 StoreKit 处理，App 不收集银行卡信息。开发服务使用已验证测试交易的交易编号和商品编号记录额度，防止重复发放。"))
                            .craftEntrance(2)
                        Text(store.t("This local review notice is not the final published privacy policy. Retention periods, account deletion, service providers, and support contact details must be finalized before public release.", "此本地验收说明并非最终公开隐私政策。正式发布前需确定保存期限、账户删除、服务提供商和支持联系方式。"))
                            .craftEntrance(3)
                    }
                }.font(.body).foregroundStyle(.black.opacity(0.8)).padding(24)
            }
            .background { StudioAtmosphere(intensity: 0.85) }
            .navigationTitle(page == .terms ? store.t("Terms", "条款") : store.t("Privacy", "隐私"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(store.t("Done", "完成")) { legalPage = nil } } }
        }
        .preferredColorScheme(.light)
        .craftAmbientHost()
    }
}
