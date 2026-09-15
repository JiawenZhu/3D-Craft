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
            uid = saved.uid; email = saved.email; refresh = saved.refresh
        }
    }
    private struct Saved: Codable { let uid:String; let email:String; let refresh:String }
    private func persist() throws {
        guard let uid, let refresh else { return }
        let data = try JSONEncoder().encode(Saved(uid:uid,email:email,refresh:refresh))
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
        let (data,response)=try await URLSession.shared.data(for:request)
        let result=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any] ?? [:]
        guard let http=response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CraftError(message:"Sign-in could not be completed. Check your email and password or try again later.",statusCode:(response as? HTTPURLResponse)?.statusCode)
        }
        return result
    }
    func handleAuthCallback(_ callbackURL: URL) {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return
        }
        let uid = queryItems.first(where: { $0.name == "uid" })?.value
        let email = queryItems.first(where: { $0.name == "email" })?.value ?? ""
        let token = queryItems.first(where: { $0.name == "token" })?.value
        let refresh = queryItems.first(where: { $0.name == "refresh" })?.value
        guard let uid, let token, let refresh else {
            return
        }
        signInWithTokens(uid: uid, email: email, token: token, refresh: refresh)
    }
    func signInWithTokens(uid: String, email: String, token: String, refresh: String) {
        self.uid = uid
        self.email = email
        self.idToken = token
        self.refresh = refresh
        self.expires = Date().addingTimeInterval(3500)
        do { try persist() } catch { self.error = error.localizedDescription }
    }
    func signInWithGoogle() async {
        guard !busy else { return }
        busy = true; error = nil; defer { busy = false }
        await withCheckedContinuation { continuation in
            guard let authURL = URL(string: "https://3d-craft.firebaseapp.com/auth/ios") else {
                self.error = "Invalid auth URL"
                continuation.resume()
                return
            }
            let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: "studio.craft.ios") { [weak self] callbackURL, err in
                guard let self else {
                    continuation.resume()
                    return
                }
                self.authSession = nil
                if let err = err as? ASWebAuthenticationSessionError, err.code == .canceledLogin {
                    continuation.resume()
                    return
                }
                guard let callbackURL else {
                    if let err { self.error = err.localizedDescription }
                    continuation.resume()
                    return
                }
                self.handleAuthCallback(callbackURL)
                continuation.resume()
            }
            session.presentationContextProvider = WebAuthPresentationProvider.shared
            session.prefersEphemeralWebBrowserSession = true
            self.authSession = session
            session.start()
        }
    }
    func signIn(email:String,password:String,register:Bool) async {
        guard !busy else{return};busy=true;error=nil;defer{busy=false}
        do {
            let result=try await send("https://identitytoolkit.googleapis.com/v1/accounts:\(register ? "signUp" : "signInWithPassword")?key=\(apiKey)",body:JSONSerialization.data(withJSONObject:["email":email.trimmingCharacters(in:.whitespacesAndNewlines),"password":password,"returnSecureToken":true]))
            guard let user=result["localId"] as? String, let token=result["idToken"] as? String, let refreshToken=result["refreshToken"] as? String else{throw CraftError(message:"Incomplete sign-in response.")}
            uid=user;self.email=result["email"] as? String ?? email;idToken=token;refresh=refreshToken;expires=Date().addingTimeInterval(3500)
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
        let bearer = try await token()
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

    func signOut(){
        authSession?.cancel(); authSession=nil
        uid=nil;email="";idToken=nil;refresh=nil;expires = .distantPast
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
                Text("Generation uses purchased or admin-granted credits. Connecting ChatGPT does not replace your 3D Craft sign-in.").font(.footnote).foregroundStyle(.secondary)
                HStack{Link("Terms",destination:URL(string:"https://3d-craft.web.app/terms")!);Link("Privacy",destination:URL(string:"https://3d-craft.web.app/privacy")!);Link("Support",destination:URL(string:"https://3d-craft.web.app/contact")!)}.font(.footnote)
            }.textFieldStyle(.roundedBorder).padding(30).padding(.top,50)
        }.background{StudioAtmosphere()}.tint(appearance.ink)
    }
}
