import SwiftUI
import Security
import AuthenticationServices

@MainActor final class WebAuthPresentationProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WebAuthPresentationProvider()
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let keyWindow = scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) {
            return keyWindow
        }
        return ASPresentationAnchor()
    }
}

/// Firebase email identity shared with the website. Passwords are never persisted.
@MainActor final class CraftAccount: ObservableObject {
    static let shared = CraftAccount()
    @Published private(set) var uid: String?
    @Published private(set) var email = ""
    @Published var error: String?
    @Published var busy = false
    @Published var deletionRequested = false
    private var authSession: ASWebAuthenticationSession?
    private var authAttempt: CraftWebAuthAttempt?
    private var appleAttempt: CraftAppleSignIn?
    private var appleUser: String?
    private var idToken: String?
    private var expires = Date.distantPast
    private var refresh: String?
    private let apiKey = "AIzaSyCKjbzHGU6N4X16ZRkmm2otkkL27MeNQYI"
    private let keychain: [String: Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:"studio.craft.account", kSecAttrAccount as String:"firebase"]
    init() {
        var query = keychain; query[kSecReturnData as String] = true
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data, let saved = try? JSONDecoder().decode(Saved.self, from:data) {
            uid = saved.uid; email = saved.email; refresh = saved.refresh; appleUser = saved.appleUser
        }
    }
    private struct Saved: Codable { let uid:String; let email:String; let refresh:String; let appleUser:String? }
    private func persist() throws {
        guard let uid, let refresh else { return }
        let data = try JSONEncoder().encode(Saved(uid:uid,email:email,refresh:refresh,appleUser:appleUser))
        let status = SecItemUpdate(keychain as CFDictionary, [kSecValueData as String:data] as CFDictionary)
        if status == errSecItemNotFound {
            var value=keychain; value[kSecValueData as String]=data
            value[kSecAttrAccessible as String]=kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(value as CFDictionary,nil) == errSecSuccess else { throw CraftError(message:"Could not securely save your sign-in.") }
        } else if status != errSecSuccess { throw CraftError(message:"Could not securely save your sign-in.") }
    }
    private func send(_ url:String, body:Data, type:String="application/json") async throws -> [String:Any] {
        var request=URLRequest(url:URL(string:url)!);request.httpMethod="POST";request.httpBody=body;request.timeoutInterval=30
        request.setValue(type,forHTTPHeaderField:"Content-Type")
        request.setValue("studio.craft.ios", forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        let (data,response)=try await URLSession.shared.data(for:request)
        let result=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any] ?? [:]
        guard let http=response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CraftError(message:"Sign-in could not be completed. Check your email and password or try again later.",statusCode:(response as? HTTPURLResponse)?.statusCode)
        }
        return result
    }
    private func completeWebSignIn(_ callbackURL: URL, attempt: CraftWebAuthAttempt) async throws {
        guard authAttempt?.state == attempt.state else { throw CraftError(message: "This sign-in attempt has expired. Please try again.") }
        guard let values = attempt.credentials(from: callbackURL) else {
            throw CraftError(message: "The sign-in response could not be verified. Please try again.")
        }
        // Verify the supplied Firebase credential before publishing account identity.
        let result = try await send("https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=\(apiKey)",
                                    body: JSONSerialization.data(withJSONObject: ["idToken": values.token]))
        guard let users = result["users"] as? [[String: Any]], let user = users.first,
              user["localId"] as? String == values.uid else { throw CraftError(message: "The sign-in identity could not be verified.") }
        guard authAttempt?.state == attempt.state else { throw CraftError(message: "This sign-in attempt was cancelled.") }
        authAttempt = nil
        uid = values.uid; email = user["email"] as? String ?? ""; appleUser = nil
        idToken = values.token; refresh = values.refresh; expires = Date().addingTimeInterval(3500)
        do { try persist() } catch { signOut(); throw error }
    }
    func signInWithGoogle() async {
        guard !busy else { return }
        busy = true; error = nil
        let attempt = CraftWebAuthAttempt()
        authAttempt = attempt
        defer { busy = false; if authAttempt?.state == attempt.state { authAttempt = nil }; authSession = nil }
        do {
            let callback: URL = try await withCheckedThrowingContinuation { continuation in
                let session = ASWebAuthenticationSession(url: attempt.url, callbackURLScheme: "studio.craft.ios") { callbackURL, err in
                    if let err { continuation.resume(throwing: err) }
                    else if let callbackURL { continuation.resume(returning: callbackURL) }
                    else { continuation.resume(throwing: CraftError(message: "No sign-in response was received.")) }
                }
                session.presentationContextProvider = WebAuthPresentationProvider.shared
                session.prefersEphemeralWebBrowserSession = true
                authSession = session
                if !session.start() { continuation.resume(throwing: CraftError(message: "Could not open sign-in. Please try again.")) }
            }
            try await completeWebSignIn(callback, attempt: attempt)
        } catch let failure as ASWebAuthenticationSessionError where failure.code == .canceledLogin {
            // Cancellation leaves the existing account unchanged.
        } catch { self.error = error.localizedDescription }
    }
    private func exchangeApple(_ credential: CraftAppleSignIn.Credential, create: Bool) async throws -> [String: Any] {
        var form = URLComponents()
        form.queryItems = [URLQueryItem(name: "providerId", value: "apple.com"),
                           URLQueryItem(name: "id_token", value: credential.identityToken),
                           URLQueryItem(name: "nonce", value: credential.nonce)]
        return try await send("https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=\(apiKey)",
            body: JSONSerialization.data(withJSONObject: ["postBody": form.percentEncodedQuery ?? "",
                "requestUri": "https://3d-craft.web.app", "returnSecureToken": true, "autoCreate": create]))
    }
    private func acceptIdentity(_ result: [String: Any], appleUser: String) throws {
        guard let user = result["localId"] as? String, !user.isEmpty,
              let token = result["idToken"] as? String, !token.isEmpty,
              let refreshToken = result["refreshToken"] as? String, !refreshToken.isEmpty else {
            throw CraftError(message: "Incomplete sign-in response.")
        }
        uid = user; email = result["email"] as? String ?? ""; self.appleUser = appleUser
        idToken = token; refresh = refreshToken; expires = Date().addingTimeInterval(3500)
        do { try persist() } catch { signOut(); throw error }
    }
    func signInWithApple() async {
        guard !busy else { return }
        busy = true; error = nil
        let attempt = CraftAppleSignIn(); appleAttempt = attempt
        defer { if appleAttempt === attempt { appleAttempt = nil }; busy = false }
        do {
            let credential = try await attempt.authorize()
            guard appleAttempt === attempt else { throw CancellationError() }
            let result = try await exchangeApple(credential, create: true)
            guard appleAttempt === attempt else { throw CancellationError() }
            try acceptIdentity(result, appleUser: credential.user)
        } catch let failure as ASAuthorizationError where failure.code == .canceled {
        } catch is CancellationError {
        } catch let failure as ASAuthorizationError {
            self.error = "Apple sign-in could not finish. Please try again. If it continues, check that your iPhone is signed in to your Apple Account."
            #if DEBUG
            print("Apple authorization failed: code=\(failure.code.rawValue)")
            #endif
        } catch { self.error = error.localizedDescription }
    }
    func signIn(email:String,password:String,register:Bool) async {
        guard !busy else{return};busy=true;error=nil;defer{busy=false}
        do {
            let result=try await send("https://identitytoolkit.googleapis.com/v1/accounts:\(register ? "signUp" : "signInWithPassword")?key=\(apiKey)",body:JSONSerialization.data(withJSONObject:["email":email.trimmingCharacters(in:.whitespacesAndNewlines),"password":password,"returnSecureToken":true]))
            guard let user=result["localId"] as? String, let token=result["idToken"] as? String, let refreshToken=result["refreshToken"] as? String else{throw CraftError(message:"Incomplete sign-in response.")}
            uid=user;appleUser=nil;self.email=result["email"] as? String ?? email;idToken=token;refresh=refreshToken;expires=Date().addingTimeInterval(3500)
            try persist()
        } catch { signOut();self.error=error.localizedDescription }
    }
    func token(forceRefresh: Bool = false) async throws ->String {
        if !forceRefresh, let idToken,expires>Date(){return idToken}
        guard let refresh else{throw CraftError(message:"Sign in to your 3D Craft account.",statusCode:401)}
        let requestUID = uid
        var form=URLComponents();form.queryItems=[URLQueryItem(name:"grant_type",value:"refresh_token"),URLQueryItem(name:"refresh_token",value:refresh)]
        do {
            let result=try await send("https://securetoken.googleapis.com/v1/token?key=\(apiKey)",body:Data((form.percentEncodedQuery ?? "").utf8),type:"application/x-www-form-urlencoded")
            guard let token=result["id_token"] as? String, let user=result["user_id"] as? String,user==uid else{throw CraftError(message:"Please sign in again.",statusCode:401)}
            idToken=token;self.refresh=result["refresh_token"] as? String ?? refresh;expires=Date().addingTimeInterval(3500);try persist();return token
        } catch { if uid == requestUID, self.refresh == refresh, let failure=error as? CraftError,let status=failure.statusCode,(400..<500).contains(status){signOut()};throw error }
    }
    func resetPassword(email:String) async {
        guard !busy else{return};busy=true;error=nil;defer{busy=false}
        do { _=try await send("https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=\(apiKey)",body:JSONSerialization.data(withJSONObject:["requestType":"PASSWORD_RESET","email":email]));error="If this email has an account, password-reset instructions will be sent." }catch{self.error=error.localizedDescription}
    }
    func requestAccountDeletion() async throws -> String {
        guard let requestUID = uid else { throw CraftError(message: "Please sign in again.", statusCode: 401) }
        var bearer = try await token()
        let lookup = try await send("https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=\(apiKey)",
            body: JSONSerialization.data(withJSONObject: ["idToken": bearer]))
        let users = lookup["users"] as? [[String: Any]] ?? []
        let providers = users.first?["providerUserInfo"] as? [[String: Any]] ?? []
        if let appleUser = providers.first(where: { $0["providerId"] as? String == "apple.com" })?["rawId"] as? String {
            let attempt = CraftAppleSignIn(); appleAttempt = attempt
            defer { if appleAttempt === attempt { appleAttempt = nil } }
            let credential = try await attempt.authorize()
            guard uid == requestUID, appleAttempt === attempt, credential.user == appleUser else {
                throw CraftError(message: "Use the Apple account linked to this 3D Craft account.", statusCode: 401)
            }
            let result = try await exchangeApple(credential, create: false)
            guard uid == requestUID, appleAttempt === attempt, result["localId"] as? String == requestUID else {
                throw CraftError(message: "The Apple account does not match this account.", statusCode: 401)
            }
            try acceptIdentity(result, appleUser: credential.user)
            bearer = try await token()
            _ = try await send("https://identitytoolkit.googleapis.com/v2/accounts:revokeToken?key=\(apiKey)",
                body: JSONSerialization.data(withJSONObject: ["providerId": "apple.com", "tokenType": "CODE",
                    "token": credential.authorizationCode, "idToken": bearer]))
        }
        guard uid == requestUID else { throw CancellationError() }
        var request = URLRequest(url: URL(string: "https://3d-craft.web.app/api/mobile/account/delete")!)
        request.httpMethod = "POST"; request.timeoutInterval = 30
        request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["confirm": true])
        let (_, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 202 else { throw CraftError(message: "Account deletion could not be confirmed.", statusCode: status) }
        return requestUID
    }

    func verifyAppleAuthorization() async {
        guard let appleUser, let requestUID = uid else { return }
        do {
            let state = try await ASAuthorizationAppleIDProvider().credentialState(forUserID: appleUser)
            guard uid == requestUID, self.appleUser == appleUser else { return }
            if state == .revoked || state == .notFound { signOut() }
        } catch {
            // A temporary Apple/network failure must not erase a valid local session.
        }
    }

    func signOut(){
        authAttempt=nil; authSession?.cancel(); authSession=nil
        appleAttempt?.cancel(); appleAttempt=nil
        uid=nil;email="";idToken=nil;refresh=nil;appleUser=nil;expires = .distantPast
        busy=false;error=nil
        SecItemDelete(keychain as CFDictionary)
    }
}

struct CraftSignInView: View {
    @ObservedObject private var account = CraftAccount.shared
    @EnvironmentObject private var store: CraftStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .emerald
    @State private var email = ""
    @State private var password = ""
    @State private var register = false
    @State private var revealPassword = false
    @FocusState private var focused: Field?
    private enum Field { case email, password }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 16) {
                        Image(appearance == .lavender ? "PaywallDragon" : "PaywallExplorer").resizable().scaledToFit()
                            .frame(width: 88, height: 108).clipShape(RoundedRectangle(cornerRadius: 18)).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(store.t("YOUR NEXT IDEA STARTS HERE", "从一个想法开始"))
                                .font(.system(size: 10, weight: .bold)).tracking(1.5).foregroundStyle(appearance.ink)
                            Text(store.t("Make it yours.", "创造属于你的世界。"))
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(store.t("Your creations. All in one place.", "所有创作，在这里相聚。"))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 12) {
                        Button { Task { await account.signInWithApple() } } label: {
                            Label(store.t("Sign in with Apple", "通过 Apple 登录"), systemImage: "apple.logo")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .foregroundStyle(.white).background(.black, in: RoundedRectangle(cornerRadius: 16))
                        }.disabled(account.busy)
                        Button { Task { await account.signInWithGoogle() } } label: {
                            Label(store.t("Continue with Google", "通过 Google 继续"), systemImage: "globe")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color.primary).frame(maxWidth: .infinity, minHeight: 52)
                                .background(CraftTheme.card, in: RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(appearance.ink.opacity(0.15)))
                        }.disabled(account.busy)
                    }.buttonStyle(.plain)
                    HStack(spacing: 14) {
                        Rectangle().frame(height: 1).foregroundStyle(appearance.ink.opacity(0.12))
                        Text(store.t("or use email", "或使用邮箱")).font(.caption).foregroundStyle(.secondary)
                        Rectangle().frame(height: 1).foregroundStyle(appearance.ink.opacity(0.12))
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        Picker(store.t("Account", "账号"), selection: $register) {
                            Text(store.t("Sign in", "登录")).tag(false)
                            Text(store.t("Create account", "创建账号")).tag(true)
                        }.pickerStyle(.segmented)
                        VStack(alignment: .leading, spacing: 7) {
                            Text(store.t("Email address", "邮箱地址")).font(.caption.weight(.semibold)).foregroundStyle(appearance.ink)
                            HStack(spacing: 12) {
                                Image(systemName: "envelope").foregroundStyle(.secondary)
                                TextField("you@example.com", text: $email)
                                    .keyboardType(.emailAddress).textContentType(.emailAddress)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .focused($focused, equals: .email).submitLabel(.next)
                                    .onSubmit { focused = .password }
                                    .accessibilityLabel(store.t("Email address", "邮箱地址"))
                            }.padding(14).background(appearance.wash, in: RoundedRectangle(cornerRadius: 14))
                        }
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(store.t("Password", "密码")).font(.caption.weight(.semibold)).foregroundStyle(appearance.ink)
                                Spacer()
                                if !register {
                                    Button(store.t("Forgot?", "忘记密码？")) { Task { await account.resetPassword(email: email) } }
                                        .font(.caption).disabled(email.isEmpty || account.busy)
                                }
                            }
                            HStack(spacing: 12) {
                                Image(systemName: "lock").foregroundStyle(.secondary)
                                Group {
                                    if revealPassword { TextField(store.t("Password", "密码"), text: $password) }
                                    else { SecureField(store.t("Password", "密码"), text: $password) }
                                }.textContentType(register ? .newPassword : .password)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .focused($focused, equals: .password).submitLabel(.go).onSubmit(submit)
                                Button { revealPassword.toggle() } label: {
                                    Image(systemName: revealPassword ? "eye.slash" : "eye").frame(width: 30, height: 30)
                                }.accessibilityLabel(revealPassword ? store.t("Hide password", "隐藏密码") : store.t("Show password", "显示密码"))
                            }.padding(14).background(appearance.wash, in: RoundedRectangle(cornerRadius: 14))
                            if register { Text(store.t("At least 6 characters", "至少 6 个字符")).font(.caption2).foregroundStyle(.secondary) }
                        }
                        if let error = account.error {
                            Label(error, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button(action: submit) {
                            HStack {
                                if account.busy { ProgressView().tint(appearance.buttonInk) }
                                Text(account.busy ? store.t("Connecting…", "正在连接……") : register ? store.t("Create account", "创建账号") : store.t("Sign in", "登录"))
                                if !account.busy { Image(systemName: "arrow.right") }
                            }
                        }.buttonStyle(CraftPrimary()).disabled(account.busy || email.isEmpty || password.count < 6)
                    }.padding(20).background(CraftTheme.card, in: RoundedRectangle(cornerRadius: 26))
                    VStack(spacing: 12) {
                        Label(store.t("Creations and Tokens sync with your account", "创作与 Tokens 随账号同步"), systemImage: "checkmark.shield")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 24) {
                            Link(store.t("Terms", "条款"), destination: URL(string: "https://3d-craft.web.app/terms")!)
                            Link(store.t("Privacy", "隐私"), destination: URL(string: "https://3d-craft.web.app/privacy")!)
                            Link(store.t("Support", "支持"), destination: URL(string: "https://3d-craft.web.app/contact")!)
                        }.font(.caption)
                    }.frame(maxWidth: .infinity)
                }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }.scrollDismissesKeyboard(.interactively)
                .background { StudioAtmosphere() }
                .navigationTitle("3D Craft").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { dismiss() } label: { Image(systemName: "xmark").font(.subheadline.bold()) }
                            .accessibilityLabel(store.t("Close", "关闭"))
                    }
                }
        }.tint(appearance.ink)
    }
    private func submit() {
        guard !account.busy, !email.isEmpty, password.count >= 6 else { return }
        focused = nil
        Task { await account.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password, register: register); password = "" }
    }
}
