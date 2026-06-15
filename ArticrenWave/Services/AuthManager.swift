// AuthManager.swift — Sign In with Apple + Guest + iCloud
// Articren Wave · © 2026 DART Meadow LLC & Radical Deepscale LLC
import AuthenticationServices
import CloudKit
import SwiftUI

class AuthManager: NSObject, ObservableObject {
    @Published var isSignedIn:         Bool   = false
    @Published var userID:             String = ""
    @Published var userFullName:       String = ""
    @Published var userEmail:          String = ""
    @Published var authError:          String? = nil
    @Published var storagePreference:  StoragePreference = .device

    enum StoragePreference: String {
        case device = "Device"
        case iCloud = "iCloud"
    }

    var isGuest: Bool { userID == "guest" }

    override init() {
        super.init()
        // Don't call restoreSession here — called from AWRootView.onAppear
        // to avoid race conditions before environment is ready
    }

    func restoreSession() {
        guard let savedID = UserDefaults.standard.string(forKey: "appleUserID"),
              !savedID.isEmpty else { return }

        // Guest session restore
        if savedID == "guest" {
            DispatchQueue.main.async {
                self.userID       = "guest"
                self.userFullName = UserDefaults.standard.string(forKey: "appleUserName") ?? "Guest Composer"
                self.isSignedIn   = true
            }
            return
        }

        // Apple ID session restore
        let provider = ASAuthorizationAppleIDProvider()
        provider.getCredentialState(forUserID: savedID) { [weak self] state, _ in
            DispatchQueue.main.async {
                if state == .authorized {
                    self?.userID       = savedID
                    self?.userFullName = UserDefaults.standard.string(forKey: "appleUserName") ?? "Composer"
                    self?.userEmail    = UserDefaults.standard.string(forKey: "appleUserEmail") ?? ""
                    self?.isSignedIn   = true
                }
                // If revoked or not found, stay on welcome screen
            }
        }
    }

    func signOut() {
        userID       = ""
        userFullName = ""
        userEmail    = ""
        isSignedIn   = false
        authError    = nil
        UserDefaults.standard.removeObject(forKey: "appleUserID")
        UserDefaults.standard.removeObject(forKey: "appleUserName")
        UserDefaults.standard.removeObject(forKey: "appleUserEmail")
    }

    func checkiCloudAvailability(completion: @escaping (Bool) -> Void) {
        CKContainer.default().accountStatus { status, _ in
            DispatchQueue.main.async {
                completion(status == .available)
            }
        }
    }
}
