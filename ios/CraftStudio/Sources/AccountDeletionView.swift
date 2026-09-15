import SwiftUI

struct AccountDeletionView: View {
    @EnvironmentObject private var store: CraftStore
    @EnvironmentObject private var billing: BillingManager
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var account = CraftAccount.shared
    @State private var confirming = false
    @State private var deleting = false
    @State private var needsSignIn = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Image(systemName: "person.crop.circle.badge.minus")
                        .font(.system(size: 44)).foregroundStyle(.red)
                    Text(store.t("Delete your account?", "删除你的账户？"))
                        .font(.largeTitle.bold())
                    Text(account.email).foregroundStyle(.secondary)
                    Text(store.t("This permanently removes your account, cloud creations, uploaded files, community submissions and unused Tokens. Save any creations you want to keep first.", "这会永久删除你的账户、云端作品、上传文件、社区投稿和未使用的代币。请先导出需要保留的作品。"))
                    Text(store.t("Deletion continues securely on our servers even if you close the app. Copies you exported or shared elsewhere are not removed. Limited purchase and deletion records are retained to prevent duplicate credit and resolve disputes.", "即使关闭应用，服务器也会继续处理删除。你已导出或分享至其他平台的副本不会被删除。为防止重复充值和处理争议，部分购买与删除记录会保留。"))
                        .font(.footnote).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 12) {
                        Text(store.t("Apple subscriptions", "Apple 订阅")).font(.headline)
                        Text(store.t("Deleting your account does not cancel an Apple subscription. You can cancel it in your Apple subscription settings. Cancellation is not required to delete your account.", "删除账户不会取消 Apple 订阅。你可以在 Apple 订阅设置中取消订阅。无论是否取消订阅，你都可以删除账户。"))
                        Link(store.t("Manage subscriptions", "管理订阅"), destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                    }.padding(18).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
                    if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("accountDeletion.error") }
                    if needsSignIn {
                        Button(store.t("Sign out and sign in again", "退出并重新登录")) { account.signOut() }
                    }
                    Button(role: .destructive) { confirming = true } label: {
                        HStack {
                            if deleting { ProgressView() }
                            Text(store.t(deleting ? "Requesting deletion…" : "Delete account", deleting ? "正在请求删除……" : "删除账户"))
                        }.frame(maxWidth: .infinity, minHeight: 48)
                    }.buttonStyle(.borderedProminent).tint(.red).disabled(deleting)
                        .accessibilityIdentifier("accountDeletion.confirm")
                }.padding(24).frame(maxWidth: 600).frame(maxWidth: .infinity)
            }.background { StudioAtmosphere() }
                .navigationTitle(store.t("Account deletion", "删除账户"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) {
                    Button(store.t("Cancel", "取消")) { dismiss() }.disabled(deleting)
                } }
                .interactiveDismissDisabled(deleting)
                .alert(store.t("Permanently delete this account?", "永久删除此账户？"), isPresented: $confirming) {
                    Button(store.t("Cancel", "取消"), role: .cancel) {}
                    Button(store.t("Delete account", "删除账户"), role: .destructive) { Task { await delete() } }
                } message: { Text(store.t("This cannot be undone.", "此操作无法撤销。")) }
        }
    }

    @MainActor private func delete() async {
        deleting = true; error = nil; needsSignIn = false
        defer { deleting = false }
        do {
            let uid = try await account.requestAccountDeletion()
            guard account.uid == uid else { return }
            await store.eraseLocalAccountData()
            guard account.uid == uid else { return }
            billing.forgetDeletedAccount(uid)
            CraftProfile.shared.erase()
            account.signOut()
            account.deletionRequested = true
        } catch {
            needsSignIn = (error as? CraftError)?.statusCode == 401
            self.error = needsSignIn
                ? store.t("Please sign in again, then return to Profile → Delete account to confirm it is you.", "请重新登录，然后返回「我的」→「删除账户」以确认你的身份。")
                : store.t("The request could not be confirmed. Try again; an accepted deletion request will continue on the server.", "暂时无法确认请求，请重试。如果请求已受理，服务器会继续处理删除。")
        }
    }
}
