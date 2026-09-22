import Combine
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Metadata for a user-owned API key. The server keeps only a SHA-256 hash;
/// the plaintext exists solely in `CraftCreatedAPIKey` for the one-time reveal.
struct CraftAPIKey: Identifiable, Equatable {
    enum Status: Equatable { case active, expired, revoked }
    let id: String, name: String, prefix: String, scopes: [String]
    let createdAt: Date, expiresAt: Date?, revokedAt: Date?, lastUsedAt: Date?
    let revoked: Bool

    init?(_ d: [String: Any]) {
        guard let id = d["id"] as? String, !id.isEmpty else { return nil }
        func date(_ key: String) -> Date? { (d[key] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) } }
        self.id = id
        name = (d["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "API key"
        prefix = d["prefix"] as? String ?? "craft_live_"
        scopes = (d["scopes"] as? [Any] ?? []).compactMap { $0 as? String }
        createdAt = date("createdAt") ?? .distantPast
        expiresAt = date("expiresAt"); revokedAt = date("revokedAt"); lastUsedAt = date("lastUsedAt")
        revoked = d["revoked"] as? Bool ?? false
    }

    func status(now: Date = Date()) -> Status {
        if revoked { return .revoked }
        if let expiresAt, expiresAt <= now { return .expired }
        return .active
    }
    var displayPrefix: String { CraftAPIKeyRules.displayPrefix(prefix) }
}

struct CraftCreatedAPIKey: Equatable {
    let metadata: CraftAPIKey, secret: String, warning: String
    init?(_ d: [String: Any]) {
        guard let metadata = CraftAPIKey(d), let secret = d["key"] as? String, secret.hasPrefix("craft_live_") else { return nil }
        self.metadata = metadata; self.secret = secret; warning = d["warning"] as? String ?? ""
    }
}

enum CraftAPIKeyRules {
    static let expiryOptions = [30, 90, 365]
    static let defaultExpiry = 90
    static let maxNameLength = 64
    static let baseURL = StudioConnection.cloudURL + "/api/v1"
    static let openAPIURL = URL(string: StudioConnection.cloudURL + "/api/v1/openapi.json")!
    static let scopes: [(id: String, en: String, zh: String)] = [
        ("assets:read", "Read projects, jobs & assets", "读取项目、任务与资源"),
        ("prompt:write", "Chat & plan model prompts", "对话与规划模型提示词"),
        ("concepts:write", "Create & refine concept images", "创建与优化概念图"),
        ("models:write", "Start 3D model generation", "开始生成 3D 模型"),
        ("animations:write", "Create character animations & video loops", "生成角色动画与视频"),
        ("profile:write", "Update profile & preferences", "更新个人资料与偏好"),
        ("wallet:read", "Read Token balance", "读取代币余额"),
    ]

    /// Permanent deletion is never part of full access; the server requires it explicitly.
    static let deleteScope = "assets:delete"

    static func requestScopes(fullAccess: Bool, selected: Set<String>, allowDelete: Bool = false) -> [String]? {
        let base = fullAccess ? ["*"] : scopes.map(\.id).filter(selected.contains)
        if base.isEmpty { return nil }
        return allowDelete ? base + [deleteScope] : base
    }
    static func cleanName(_ raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty || name.count > maxNameLength ? nil : name
    }
    static func displayPrefix(_ prefix: String) -> String {
        var p = prefix
        while p.hasSuffix("...") || p.hasSuffix("…") { p = p.hasSuffix("…") ? String(p.dropLast()) : String(p.dropLast(3)) }
        return p + "…"
    }
}

/// Key management for the signed-in account. Every request is pinned to the uid
/// that started it; an account change clears all state, including a revealed key.
@MainActor final class CraftAPIKeyStore: ObservableObject {
    @Published private(set) var keys: [CraftAPIKey]?
    @Published private(set) var revealed: CraftCreatedAPIKey?
    @Published private(set) var busy = false
    @Published var error: String?
    private var boundUID: String?
    private var watch: AnyCancellable?

    /// The default is resolved inside the initializer rather than as a default
    /// argument: `CraftAccount.shared` is main-actor isolated, and a default
    /// argument is evaluated at the call site, which Swift 6 rejects.
    init(account: CraftAccount? = nil) {
        let account = account ?? CraftAccount.shared
        boundUID = account.uid
        watch = account.$uid.dropFirst().sink { [weak self] uid in
            guard let self, uid != self.boundUID else { return }
            self.boundUID = uid; self.clear()
        }
    }

    func clear() { keys = nil; revealed = nil; error = nil; busy = false }
    func dismissReveal() { revealed = nil }

    func load() async {
        do { let result = try await request("GET", "/api/keys"); keys = ((result["keys"] as? [[String: Any]]) ?? []).compactMap(CraftAPIKey.init).sorted { $0.createdAt > $1.createdAt } }
        catch is CancellationError { }
        catch { if keys == nil { keys = [] }; self.error = error.localizedDescription }
    }

    func create(name: String, expiryDays: Int, scopes: [String]) async {
        guard !busy else { return }
        busy = true; error = nil; defer { busy = false }
        do {
            let result = try await request("POST", "/api/keys", body: ["name": name, "scopes": scopes, "expiresInDays": expiryDays])
            guard let created = CraftCreatedAPIKey(result) else { throw CraftError(message: "The key could not be displayed. Revoke any key you don’t recognize, then try again.") }
            revealed = created
            await load()
        } catch is CancellationError { } catch { self.error = error.localizedDescription }
    }

    func revoke(_ key: CraftAPIKey) async {
        guard !busy else { return }
        busy = true; error = nil; defer { busy = false }
        do { _ = try await request("DELETE", "/api/keys/" + (key.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key.id)); await load() }
        catch is CancellationError { } catch { self.error = error.localizedDescription }
    }

    /// Canonical cloud origin only — never a local or saved LAN server.
    private func request(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> [String: Any] {
        let account = CraftAccount.shared
        guard let uid = account.uid, uid == boundUID else { throw CancellationError() }
        var r = URLRequest(url: URL(string: StudioConnection.cloudURL + path)!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        r.httpMethod = method
        if let body { r.httpBody = try JSONSerialization.data(withJSONObject: body); r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        r.setValue("Bearer " + (try await account.token()), forHTTPHeaderField: "Authorization")
        guard account.uid == uid else { throw CancellationError() }
        var (data, response) = try await URLSession.shared.data(for: r)
        if (response as? HTTPURLResponse)?.statusCode == 401, account.uid == uid {
            r.setValue("Bearer " + (try await account.token(forceRefresh: true)), forHTTPHeaderField: "Authorization")
            (data, response) = try await URLSession.shared.data(for: r)
        }
        guard account.uid == uid, boundUID == uid else { throw CancellationError() }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (200..<300).contains(status), let json else {
            throw CraftError(message: json?["detail"] as? String ?? "API keys are unavailable right now. Please try again shortly.", statusCode: status)
        }
        return json
    }
}

struct APIAccessView: View {
    @EnvironmentObject private var store: CraftStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    @ObservedObject private var account = CraftAccount.shared
    @StateObject private var keys = CraftAPIKeyStore()
    @State private var name = ""
    @State private var expiry = CraftAPIKeyRules.defaultExpiry
    @State private var fullAccess = true
    @State private var allowDelete = false
    @State private var scopes = Set(CraftAPIKeyRules.scopes.map(\.id))
    @State private var stored = false
    @State private var copied = false
    @State private var revoking: CraftAPIKey?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(store.t("API Configuration", "API 接口设置"))
                            .font(.title2.weight(.bold))
                            .foregroundStyle(appearance.ink)
                        Text(store.t("Configure and manage API keys to connect 3D Craft with your external tools, scripts, and workflows.",
                                     "配置并管理你的 API 密钥，以便将 3D Craft 与外部工具、脚本和工作流无缝连接。"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                    if let revealed = keys.revealed { reveal(revealed) } else { createForm }
                    if let error = keys.error {
                        Text(error).font(.footnote).foregroundStyle(.red).accessibilityIdentifier("apiKeys.error")
                    }
                    keyList
                    connectGuide
                }
                .padding(24).frame(maxWidth: 650).frame(maxWidth: .infinity)
            }
            .background { StudioAtmosphere() }
            .navigationTitle(store.t("API access", "API 访问"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(store.t("Done", "完成")) { dismiss() } } }
            .task { await keys.load() }
            .onChange(of: account.uid) { _, _ in dismiss() }
            .onDisappear { keys.clear() }
            .alert(store.t("Revoke this key?", "撤销此密钥？"), isPresented: Binding(get: { revoking != nil }, set: { if !$0 { revoking = nil } }), presenting: revoking) { key in
                Button(store.t("Cancel", "取消"), role: .cancel) {}
                Button(store.t("Revoke", "撤销"), role: .destructive) { Task { await keys.revoke(key) } }
            } message: { key in
                Text(store.t("“\(key.name)” stops working immediately for anything using it. This cannot be undone.", "所有使用「\(key.name)」的工具将立即失效。此操作无法撤销。"))
            }
        }
    }

    private var createForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(store.t("Create a key", "创建密钥")).font(.headline)
            TextField(store.t("Name, e.g. My script", "名称，例如 我的脚本"), text: $name)
                .textFieldStyle(.roundedBorder).textInputAutocapitalization(.never).autocorrectionDisabled()
                .onChange(of: name) { _, value in if value.count > CraftAPIKeyRules.maxNameLength { name = String(value.prefix(CraftAPIKeyRules.maxNameLength)) } }
                .accessibilityIdentifier("apiKeys.name")
            Text(store.t("Expires after", "有效期")).font(.subheadline.weight(.semibold))
            Picker(store.t("Expires after", "有效期"), selection: $expiry) {
                ForEach(CraftAPIKeyRules.expiryOptions, id: \.self) { days in
                    Text(days == 365 ? store.t("1 year", "1 年") : store.t("\(days) days", "\(days) 天")).tag(days)
                }
            }.pickerStyle(.segmented).accessibilityIdentifier("apiKeys.expiry")
            Toggle(store.t("Full API access", "完整 API 权限"), isOn: $fullAccess).tint(appearance.ink)
            if !fullAccess {
                ForEach(CraftAPIKeyRules.scopes, id: \.id) { scope in
                    Toggle(isOn: Binding(get: { scopes.contains(scope.id) }, set: { on in if on { scopes.insert(scope.id) } else { scopes.remove(scope.id) } })) {
                        Text(store.t(scope.en, scope.zh)).font(.subheadline)
                    }.tint(appearance.ink).padding(.leading, 12)
                }
            }
            Toggle(isOn: $allowDelete) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.t("Allow permanent deletes", "允许永久删除")).font(.subheadline)
                    Text(store.t("Lets the tool erase projects, images and 3D objects. Deleted work can’t be restored.",
                                 "允许工具删除项目、图片和 3D 作品。删除后无法恢复。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.tint(.red).accessibilityIdentifier("apiKeys.allowDelete")
            Text(store.t("Grant only what the connected tool needs. No key can manage other keys or perform account administration such as deleting your account.",
                         "只授予所连接工具需要的权限。任何密钥都无法管理其他密钥或执行删除账户等账户管理操作。"))
                .font(.caption).foregroundStyle(.secondary)
            Button {
                guard let clean = CraftAPIKeyRules.cleanName(name) else { keys.error = store.t("Give this key a name so you can recognize it later.", "请为密钥命名，方便日后识别。"); return }
                guard let chosen = CraftAPIKeyRules.requestScopes(fullAccess: fullAccess, selected: scopes, allowDelete: allowDelete) else { keys.error = store.t("Choose at least one permission, or allow full access.", "请至少选择一项权限，或允许完整访问。"); return }
                stored = false; copied = false
                Task { await keys.create(name: clean, expiryDays: expiry, scopes: chosen); if keys.revealed != nil { name = "" } }
            } label: {
                HStack { if keys.busy { ProgressView() }; Text(store.t(keys.busy ? "Creating…" : "Create key", keys.busy ? "正在创建……" : "创建密钥")) }
            }.buttonStyle(CraftPrimary()).disabled(keys.busy).accessibilityIdentifier("apiKeys.create")
        }
        .padding(18).craftSurface(.raised, cornerRadius: 20)
    }

    private func reveal(_ created: CraftCreatedAPIKey) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(store.t("Copy “\(created.metadata.name)” now", "立即复制「\(created.metadata.name)」"), systemImage: "checkmark.shield").font(.headline)
            Text(store.t("This is the only time the full key is shown. 3D Craft stores only a one-way hash, so it can’t be recovered — if you lose it, revoke it and create a new one.",
                         "完整密钥只会显示这一次。3D Craft 只保存单向哈希，无法找回；如果遗失，请撤销后重新创建。"))
                .font(.subheadline)
            Text(created.secret).font(.system(.footnote, design: .monospaced)).textSelection(.enabled).privacySensitive()
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("apiKeys.secret")
            Button {
                // Local-only and expiring, so the key doesn't sync via Universal Clipboard or linger.
                UIPasteboard.general.setItems([[UTType.plainText.identifier: created.secret]],
                                              options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)])
                copied = true
            } label: { Label(copied ? store.t("Copied — clears in 2 minutes", "已复制，2 分钟后清除") : store.t("Copy key", "复制密钥"), systemImage: copied ? "checkmark" : "doc.on.doc") }
                .buttonStyle(CraftSecondary()).accessibilityIdentifier("apiKeys.copy")
            Toggle(store.t("I’ve stored this key somewhere safe", "我已将密钥妥善保存"), isOn: $stored).tint(appearance.ink)
            Button(store.t("Done — hide key", "完成，隐藏密钥")) { keys.dismissReveal(); stored = false; copied = false }
                .buttonStyle(CraftPrimary()).disabled(!stored).accessibilityIdentifier("apiKeys.hide")
        }
        .padding(18).background(Color.yellow.opacity(0.14), in: RoundedRectangle(cornerRadius: 20))
    }

    private var keyList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(store.t("Your keys", "你的密钥")).font(.headline)
            if let list = keys.keys {
                if list.isEmpty {
                    Text(store.t("No keys yet. Keys you create appear here with their prefix only.", "还没有密钥。创建的密钥仅以前缀形式显示在这里。"))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(list) { key in row(key) }
            } else { ProgressView().frame(maxWidth: .infinity) }
        }
        .padding(18).craftSurface(.raised, cornerRadius: 20)
    }

    private func row(_ key: CraftAPIKey) -> some View {
        let status = key.status()
        let date: (Date?) -> String = { $0.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? store.t("never", "从不") }
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(key.name).font(.subheadline.weight(.semibold))
                    Text(status == .active ? store.t("Active", "有效") : status == .expired ? store.t("Expired", "已过期") : store.t("Revoked", "已撤销"))
                        .font(.caption2.weight(.semibold)).padding(.horizontal, 7).padding(.vertical, 2)
                        .background(status == .active ? appearance.washStrong : Color.secondary.opacity(0.15), in: Capsule())
                }
                Text(key.displayPrefix).font(.system(.caption, design: .monospaced))
                Text((key.scopes.contains("*") ? store.t("Full API access", "完整 API 权限")
                     : key.scopes.filter { $0 != CraftAPIKeyRules.deleteScope }.map { id in CraftAPIKeyRules.scopes.first { $0.id == id }.map { store.t($0.en, $0.zh) } ?? id }.joined(separator: " · "))
                     + (key.scopes.contains(CraftAPIKeyRules.deleteScope) ? store.t(" · Can delete", " · 可删除") : ""))
                    .font(.caption).foregroundStyle(.secondary)
                Text(status == .revoked ? store.t("Revoked \(date(key.revokedAt))", "撤销于 \(date(key.revokedAt))")
                     : store.t("Expires \(date(key.expiresAt)) · Last used \(date(key.lastUsedAt))", "到期 \(date(key.expiresAt)) · 最近使用 \(date(key.lastUsedAt))"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if status == .active {
                Button(role: .destructive) { revoking = key } label: { Text(store.t("Revoke", "撤销")).font(.subheadline) }
                    .disabled(keys.busy).accessibilityIdentifier("apiKeys.revoke")
            }
        }
        .opacity(status == .active ? 1 : 0.6)
        .padding(.vertical, 4)
    }

    private var connectGuide: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(store.t("Client integration", "客户端接入参数")).font(.headline)
            
            LabeledContent(store.t("Base URL", "基础 URL")) {
                HStack(spacing: 8) {
                    Text(CraftAPIKeyRules.baseURL)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                    Button {
                        UIPasteboard.general.string = CraftAPIKeyRules.baseURL
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                            .foregroundStyle(appearance.ink)
                    }
                }
            }
            LabeledContent(store.t("Documentation", "接口文档")) {
                Link(store.t("OpenAPI Specification", "OpenAPI 规范"), destination: CraftAPIKeyRules.openAPIURL)
                    .font(.caption.weight(.medium))
            }
            LabeledContent(store.t("Authentication", "鉴权请求头")) {
                Text("Authorization: Bearer <key>")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            
            Divider().opacity(0.4)
            
            Text(store.t("Supported operations: Token balance, creative planning, multi-view concept images, and 3D reconstruction jobs.",
                         "支持的操作：代币余额查询、提示词规划、多视角概念图生成与 3D 模型重构。"))
                .font(.caption).foregroundStyle(.secondary)
            
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(appearance.ink)
                    .font(.caption)
                Text(store.t("Keep your secret keys secure. API requests authenticate as your account and spend your Token balance.",
                             "请妥善保管你的密钥。API 请求将代表你的账户执行并消耗相应的代币余额。"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(appearance.washSoft, in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(18).craftSurface(.raised, cornerRadius: 20)
    }
}
