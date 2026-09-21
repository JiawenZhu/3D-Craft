import SwiftUI
import UIKit

enum CraftAIProvider: String, CaseIterable {
    case google, fal
    static func recipient(path: String, method: String) -> Self? {
        guard method.uppercased() == "POST" else { return nil }
        if path.hasPrefix("/concepts/"), path.hasSuffix("/model") { return .fal }
        if (path.hasPrefix("/projects/") && (path.hasSuffix("/concepts") || path.hasSuffix("/chat"))) ||
           (path.hasPrefix("/concepts/") && (path.hasSuffix("/refine") || path.hasSuffix("/model-prompt"))) { return .google }
        return nil
    }
    var name: String { self == .google ? "Google Gemini" : "fal.ai" }
    func key(uid: String) -> String { "craftAIConsent.v1.\(uid).\(rawValue)" }
}

@MainActor enum CraftAIPrivacy {
    private static var pending: (key: String, task: Task<Bool, Never>)?
    static func authorize(_ provider: CraftAIProvider, uid: String, chinese: Bool) async throws {
        let key = provider.key(uid: uid)
        if UserDefaults.standard.bool(forKey: key)
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.arguments.contains(where: { $0.contains("craftActiveConversation") }) {
            return
        }
        if let current = pending {
            _ = await current.task.value
            // Re-check both recipient and account; another prompt cannot authorize this request.
            guard CraftAccount.shared.uid == uid else { throw CancellationError() }
            if current.key == key {
                guard UserDefaults.standard.bool(forKey: key) else { throw declined(chinese) }
                return
            }
        }
        let task = Task { @MainActor in await present(provider, uid: uid, chinese: chinese) }
        pending = (key, task)
        let accepted = await task.value
        if pending?.key == key { pending = nil }
        guard CraftAccount.shared.uid == uid else { throw CancellationError() }
        guard accepted else { throw declined(chinese) }
    }
    private static func declined(_ chinese: Bool) -> CraftError {
        CraftError(message: chinese ? "你未允许 AI 处理。本次请求未发送给 AI 服务商。" : "AI processing was not allowed. This request was not sent to an AI provider.")
    }
    private static func present(_ provider: CraftAIProvider, uid: String, chinese: Bool) async -> Bool {
        guard CraftAccount.shared.uid == uid,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
              var top = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return false }
        while let presented = top.presentedViewController { top = presented }
        guard !(top is UIAlertController) else { return false }
        let purpose = provider == .google
            ? (chinese ? "你的提示词、相关对话和所选参考图片将发送给 Google Gemini，用于优化提示词、对话和生成概念图。" : "Your prompts, relevant conversation and selected reference images will be sent to Google Gemini to improve prompts, answer messages and create concept images.")
            : (chinese ? "你的所选概念图、参考图片和 3D 提示词将发送给 fal.ai 及所选模型的服务商，用于生成 3D 资产。" : "Your selected concepts, reference images and 3D prompt will be sent to fal.ai and the selected model provider to create your 3D asset.")
        let message = purpose + (chinese ? "\n\n仅发送你有权使用的内容。可以拒绝并继续浏览作品和钱包。你可在「我的」重置此许可；已提交的任务仍会继续。" : "\n\nOnly share content you have permission to use. You can decline and keep browsing creations and your wallet. Reset this permission in Profile; already submitted jobs will continue.")
        return await withCheckedContinuation { continuation in
            let alert = UIAlertController(title: chinese ? "允许 AI 处理这些内容？" : "Allow AI processing?", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: chinese ? "暂不允许" : "Not now", style: .cancel) { _ in continuation.resume(returning: false) })
            alert.addAction(UIAlertAction(title: chinese ? "隐私政策" : "Privacy policy", style: .default) { _ in
                UIApplication.shared.open(URL(string: "https://3d-craft.web.app/privacy")!)
                continuation.resume(returning: false)
            })
            alert.addAction(UIAlertAction(title: chinese ? "允许" : "Allow", style: .default) { _ in
                let valid = CraftAccount.shared.uid == uid
                if valid { UserDefaults.standard.set(true, forKey: provider.key(uid: uid)) }
                continuation.resume(returning: valid)
            })
            top.present(alert, animated: true)
        }
    }
}

struct CraftAIPrivacySettings: View {
    @EnvironmentObject private var store: CraftStore
    @State private var reset = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(store.t("AI privacy", "AI 隐私"), systemImage: "hand.raised").font(.headline)
            Text(store.t("Gemini processes prompts, conversations and concept images. fal.ai and the selected model provider process 3D references. We ask before your first request to each provider.", "Gemini 处理提示词、对话和概念图；fal.ai 及所选模型服务商处理 3D 参考内容。首次请求各服务商前，我们会征求你的许可。"))
                .font(.footnote).foregroundStyle(.secondary)
            Button(store.t(reset ? "Permission reset" : "Ask again before sharing", reset ? "许可已重置" : "分享前重新询问")) {
                guard let uid = CraftAccount.shared.uid else { return }
                for provider in CraftAIProvider.allCases { UserDefaults.standard.removeObject(forKey: provider.key(uid: uid)) }
                reset = true
            }.disabled(reset)
            Link(store.t("Privacy policy", "隐私政策"), destination: URL(string: "https://3d-craft.web.app/privacy")!)
        }.padding(18).craftSurface(.raised, cornerRadius: 20)
    }
}
