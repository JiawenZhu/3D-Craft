import SwiftUI
import UIKit

struct AIAccountView: View {
    @EnvironmentObject private var store: CraftStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    @State private var confirmLogout = false
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Image(systemName: "brain.head.profile").font(.system(size: 40))
                        .foregroundStyle(appearance.ink).accessibilityHidden(true)
                    Text(store.t("A thinking partner\nfor your ideas.", "为你的灵感，\n添一位思考伙伴。"))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    Text(store.t("Connect ChatGPT to plan concept prompts and access account image generation when available.",
                                 "连接 ChatGPT，规划概念图提示词，并使用账户可用的图片生成功能。"))
                        .foregroundStyle(.secondary)

                    if !store.aiAccount.connected { deviceLoginSetup }

                    if store.aiAccount.connected {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(store.t("ChatGPT connected", "ChatGPT 已连接"), systemImage: "checkmark.circle.fill")
                                .font(.headline).foregroundStyle(appearance.ink)
                            if let email = store.aiAccount.email { Text(email).font(.subheadline).textSelection(.enabled) }
                            Text(store.t("\(store.aiAccount.models.count) models available for planning", "\(store.aiAccount.models.count) 个模型可用于提示词规划"))
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text(store.aiAccount.imageGenerationSupported
                                 ? store.t("GPT Image 2 · Account image generation available", "GPT Image 2 · 账户图片生成可用")
                                 : store.t("Account image generation is not available on this connection yet.", "此连接暂未提供账户图片生成。"))
                                .font(.caption).foregroundStyle(.secondary)
                            Button(store.t("Disconnect ChatGPT", "断开 ChatGPT")) { confirmLogout = true }
                                .buttonStyle(CraftSecondary()).disabled(store.aiAccountBusy)
                                .accessibilityIdentifier("ai.logout")
                        }.craftPanel()
                    } else if let login = store.aiLogin {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(store.t("Finish connecting in your browser", "在浏览器中完成连接")).font(.headline)
                            Text(store.t("Enter this code on the official OpenAI page.", "在 OpenAI 官方页面输入下方代码。"))
                                .font(.subheadline).foregroundStyle(.secondary)
                            HStack {
                                Text(login.userCode).font(.title2.monospaced().bold()).textSelection(.enabled)
                                    .accessibilityIdentifier("ai.userCode")
                                Spacer()
                                Button {
                                    UIPasteboard.general.string = login.userCode; copied = true
                                } label: { Image(systemName: copied ? "checkmark" : "doc.on.doc") }
                                    .accessibilityLabel(store.t("Copy code", "复制代码"))
                            }.padding(16).background(appearance.washSoft, in: RoundedRectangle(cornerRadius: 16))
                            Button { openURL(login.verificationURL) } label: {
                                Label(store.t("Open official sign-in page", "打开官方登录页面"), systemImage: "arrow.up.right")
                            }.buttonStyle(CraftPrimary()).accessibilityIdentifier("ai.openVerification")
                            Label(store.t("Waiting for your browser confirmation…", "正在等待浏览器确认……"), systemImage: "clock")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(store.t("This attempt stops after 5 minutes. You can cancel anytime.", "本次连接将在 5 分钟后停止，你也可以随时取消。"))
                                .font(.caption).foregroundStyle(.secondary)
                            Button(store.t("Get a new code", "获取新代码")) {
                                copied = false
                                Task { _ = await store.beginAILogin() }
                            }
                            .buttonStyle(CraftSecondary()).disabled(store.aiAccountBusy)
                            .accessibilityIdentifier("ai.retryLogin")
                            Button(store.t("Cancel connection", "取消连接")) { Task { await store.cancelAILogin() } }
                                .buttonStyle(CraftSecondary()).disabled(store.aiAccountBusy)
                                .accessibilityIdentifier("ai.cancelLogin")
                        }.craftPanel()
                    } else {
                        Button {
                            copied = false
                            Task { _ = await store.beginAILogin() }
                        } label: {
                            Label(store.aiAccountBusy ? store.t("Connecting…", "正在连接……") : store.t("Get a sign-in code", "获取登录代码"),
                                  systemImage: "person.crop.circle.badge.checkmark")
                        }.buttonStyle(CraftPrimary()).disabled(store.aiAccountBusy || !store.aiAccountLoaded || !store.aiAccount.available)
                            .accessibilityIdentifier("ai.connect")
                        if !store.aiAccountLoaded {
                            ProgressView(store.t("Checking your studio…", "正在检查工作室……"))
                        } else if !store.aiAccount.available {
                            Text(store.t("ChatGPT connection is not available on this studio yet.", "此工作室尚未提供 ChatGPT 连接。"))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }

                    if let error = store.aiAccountError {
                        Text(error).font(.subheadline).foregroundStyle(.red).accessibilityIdentifier("ai.error")
                    }
                    Text(store.t("Gemini is the default and needs no ChatGPT account. Connect your own ChatGPT account to optionally use GPT Image 2 and account planning models. Sign-in happens on OpenAI’s website; the app never asks for your password.",
                                 "Gemini 为默认模型，无需 ChatGPT 账户。连接自己的 ChatGPT 账户后，可选择 GPT Image 2 和账户可用的规划模型。登录在 OpenAI 网站完成，App 不会索取你的密码。"))
                        .font(.caption).foregroundStyle(.secondary)
                    Button(store.t("Refresh connection", "刷新连接")) { Task { await store.refreshAIAccount() } }
                        .buttonStyle(CraftSecondary()).disabled(store.aiAccountBusy)
                        .accessibilityIdentifier("ai.refresh")
                }.padding(22).frame(maxWidth: 650).frame(maxWidth: .infinity)
            }
            .background { StudioAtmosphere(intensity: 0.8) }
            .navigationTitle(store.t("ChatGPT connection", "ChatGPT 连接")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button(store.t("Done", "完成")) { dismiss() }.accessibilityIdentifier("ai.done")
            } }
        }
        .tint(appearance.ink)
        .task { await store.refreshAIAccount() }
        .task(id: store.aiLogin?.id) {
            guard let login = store.aiLogin else { return }
            while !Task.isCancelled, store.aiLogin?.id == login.id, !store.aiAccount.connected {
                if Date() >= login.deadline { await store.cancelAILogin(expired: true); return }
                if scenePhase == .active { await store.refreshAIAccount() }
                do { try await Task.sleep(nanoseconds: 3_000_000_000) } catch { return }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refreshAIAccount() } }
        }
        .confirmationDialog(store.t("Disconnect ChatGPT from this studio?", "要断开此工作室的 ChatGPT 连接吗？"),
                            isPresented: $confirmLogout, titleVisibility: .visible) {
            Button(store.t("Disconnect", "断开连接"), role: .destructive) { Task { await store.logoutAIAccount() } }
        }
    }

    private var deviceLoginSetup: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(store.t("First, enable device sign-in", "先开启设备代码登录"), systemImage: "person.badge.key")
                .font(.headline)
            Text(store.t("In ChatGPT → Settings → Security, turn on device code authorization for Codex. Then return here and get a new sign-in code.",
                         "在 ChatGPT → 设置 → 安全中，开启 Codex 设备代码授权。然后返回这里，获取新的登录代码。"))
                .font(.subheadline).foregroundStyle(.secondary)
                .accessibilityIdentifier("ai.deviceAuthHelp")
            Button { openURL(URL(string: "https://chatgpt.com/#settings/Security")!) } label: {
                Label(store.t("Open ChatGPT security settings", "打开 ChatGPT 安全设置"), systemImage: "arrow.up.right")
            }
            .buttonStyle(CraftSecondary())
            .accessibilityIdentifier("ai.securitySettings")
            Text(store.t("If you see “Enable device code authorization,” complete this step first. Workspace accounts may require an administrator. Gemini remains available without connecting ChatGPT.",
                         "如果提示“Enable device code authorization”，请先完成此步骤。工作区账户可能需要管理员开启。无需连接 ChatGPT，也可继续使用 Gemini。"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .craftPanel()
    }
}
