// AuthManager.swift — Sign In with Apple + iCloud for ArticrenWave
import AuthenticationServices
import CloudKit
import SwiftUI

class AuthManager: NSObject, ObservableObject {
    @Published var isSignedIn: Bool = false
    @Published var userID: String = ""
    @Published var userFullName: String = ""
    @Published var userEmail: String = ""
    @Published var avatarURL: URL? = nil
    @Published var storagePreference: StoragePreference = .device
    @Published var authError: String? = nil

    enum StoragePreference: String {
        case device = "Device"
        case iCloud = "iCloud"
    }

    override init() {
        super.init()
        restoreSession()
    }

    private func restoreSession() {
        guard let savedID = UserDefaults.standard.string(forKey: "appleUserID"),
              !savedID.isEmpty else { return }

        let provider = ASAuthorizationAppleIDProvider()
        provider.getCredentialState(forUserID: savedID) { [weak self] state, _ in
            DispatchQueue.main.async {
                if state == .authorized {
                    self?.userID = savedID
                    self?.userFullName = UserDefaults.standard.string(forKey: "appleUserName") ?? ""
                    self?.userEmail = UserDefaults.standard.string(forKey: "appleUserEmail") ?? ""
                    self?.isSignedIn = true
                }
            }
        }
    }

    // MARK: - Sign In with Apple
    func signInWithApple(presentationAnchor: ASPresentationAnchor) {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    func signOut() {
        userID = ""
        userFullName = ""
        userEmail = ""
        isSignedIn = false
        UserDefaults.standard.removeObject(forKey: "appleUserID")
        UserDefaults.standard.removeObject(forKey: "appleUserName")
        UserDefaults.standard.removeObject(forKey: "appleUserEmail")
    }

    // MARK: - iCloud availability
    func checkiCloudAvailability(completion: @escaping (Bool) -> Void) {
        CKContainer.default().accountStatus { status, _ in
            DispatchQueue.main.async {
                completion(status == .available)
            }
        }
    }
}

// MARK: - ASAuthorizationControllerDelegate
extension AuthManager: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController,
                                  didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }

        let id = credential.user
        let name = [credential.fullName?.givenName, credential.fullName?.familyName]
            .compactMap { $0 }.joined(separator: " ")
        let email = credential.email ?? ""

        DispatchQueue.main.async {
            self.userID = id
            self.userFullName = name.isEmpty ? (UserDefaults.standard.string(forKey: "appleUserName") ?? "Composer") : name
            self.userEmail = email.isEmpty ? (UserDefaults.standard.string(forKey: "appleUserEmail") ?? "") : email
            self.isSignedIn = true

            UserDefaults.standard.set(id, forKey: "appleUserID")
            if !name.isEmpty { UserDefaults.standard.set(name, forKey: "appleUserName") }
            if !email.isEmpty { UserDefaults.standard.set(email, forKey: "appleUserEmail") }
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        DispatchQueue.main.async {
            self.authError = error.localizedDescription
        }
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding
extension AuthManager: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Return the key window
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow }) ?? UIWindow()
    }
}
