import AuthenticationServices
import CryptoKit
import UIKit

/// One native authorization request. The raw nonce is only sent to Firebase,
/// which checks its hash against the Apple-signed identity token.
@MainActor final class CraftAppleSignIn: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    struct Credential {
        let user: String
        let identityToken: String
        let authorizationCode: String
        let nonce: String
    }
    private let nonce = UUID().uuidString + UUID().uuidString
    private let state = UUID().uuidString
    private var continuation: CheckedContinuation<Credential, Error>?
    private var controller: ASAuthorizationController?

    func authorize() async throws -> Credential {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.email]
            request.nonce = SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
            request.state = state
            let controller = ASAuthorizationController(authorizationRequests: [request])
            self.controller = controller
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }.first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let value = authorization.credential as? ASAuthorizationAppleIDCredential,
              value.state == state,
              let tokenData = value.identityToken, let token = String(data: tokenData, encoding: .utf8), !token.isEmpty,
              let codeData = value.authorizationCode, let code = String(data: codeData, encoding: .utf8), !code.isEmpty else {
            finish(.failure(CraftError(message: "The Apple sign-in response could not be verified. Please try again.")))
            return
        }
        finish(.success(Credential(user: value.user, identityToken: token, authorizationCode: code, nonce: nonce)))
    }
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) { finish(.failure(error)) }
    func cancel() { controller?.cancel(); finish(.failure(CancellationError())) }
    private func finish(_ result: Result<Credential, Error>) {
        let pending = continuation; continuation = nil; controller = nil
        pending?.resume(with: result)
    }
}
