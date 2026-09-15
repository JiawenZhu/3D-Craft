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
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .emerald
    @State private var email=""
    @State private var password=""
    @State private var register=false
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20){
                Image(systemName:"cube.fill").font(.system(size:48)).foregroundStyle(appearance.ink)
                Text("Welcome to 3D Craft").font(.largeTitle.bold())
                Text("Sign in with the same account you use on the website to sync your concepts and 3D objects in real time.").foregroundStyle(.secondary)
                
                Button {
                    Task { await account.signInWithGoogle() }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "globe")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color.blue)
                        Text("Continue with Google")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.1), lineWidth: 1))
                }
                .disabled(account.busy)

                Button { Task { await account.signInWithApple() } } label: {
                    Label("Sign in with Apple", systemImage: "apple.logo")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .foregroundStyle(.white).background(.black, in: RoundedRectangle(cornerRadius: 12))
                }.disabled(account.busy)
                HStack(spacing: 12) {
                    Rectangle().frame(height: 1).foregroundColor(.secondary.opacity(0.25))
                    Text("or use email").font(.footnote).foregroundColor(.secondary)
                    Rectangle().frame(height: 1).foregroundColor(.secondary.opacity(0.25))
                }.padding(.vertical, 4)

                Picker("Account",selection:$register){Text("Sign in").tag(false);Text("Create account").tag(true)}.pickerStyle(.segmented)
                TextField("Email",text:$email).keyboardType(.emailAddress).textContentType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Password",text:$password).textContentType(register ? .newPassword : .password)
                Button(account.busy ? "Connecting…" : register ? "Create account" : "Sign in"){
                    Task{await account.signIn(email:email,password:password,register:register);password=""}
                }.buttonStyle(CraftPrimary()).disabled(account.busy || email.isEmpty || password.count<6)
                Button("Forgot password?"){Task{await account.resetPassword(email:email)}}.disabled(email.isEmpty || account.busy)
                if let error=account.error{Text(error).font(.callout).foregroundStyle(.red)}
                Text("Review the Token cost before generating. Your creations and balance sync with your 3D Craft account.").font(.footnote).foregroundStyle(.secondary)
                HStack{Link("Terms",destination:URL(string:"https://3d-craft.web.app/terms")!);Link("Privacy",destination:URL(string:"https://3d-craft.web.app/privacy")!);Link("Support",destination:URL(string:"https://3d-craft.web.app/contact")!)}.font(.footnote)
            }.textFieldStyle(.roundedBorder).padding(30).padding(.top,50)
        }.background{StudioAtmosphere()}.tint(appearance.ink)
    }
}
