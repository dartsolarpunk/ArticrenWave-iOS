// AWWelcomeView.swift — Sign In / Guest welcome screen
// Articren Wave · © 2026 DART Meadow LLC & Radical Deepscale LLC
import SwiftUI
import AuthenticationServices

struct AWWelcomeView: View {
    @EnvironmentObject var appState:    AppState
    @EnvironmentObject var authManager: AuthManager
    @State private var ringPulse        = false
    @State private var storageChoice: AuthManager.StoragePreference = .device
    @State private var showStoragePicker = false
    @State private var iCloudAvailable  = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "#08091A"), Color(hex: "#12062A"), Color(hex: "#08091A")],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()

            AWStaffLines()

            VStack(spacing: 0) {
                Spacer()

                // Logo orb
                ZStack {
                    Circle()
                        .stroke(appState.theme.accent.opacity(0.07), lineWidth: 1)
                        .frame(width: ringPulse ? 210 : 178, height: ringPulse ? 210 : 178)
                        .animation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true),
                                   value: ringPulse)
                    Circle()
                        .fill(Color(hex: "#0E0A1E"))
                        .frame(width: 156, height: 156)
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [appState.theme.accent.opacity(0.5),
                                         appState.theme.secondaryAccent.opacity(0.3)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                        .frame(width: 156, height: 156)

                    Image("AppLogo")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 148, height: 148)
                        .clipShape(Circle())
                }
                .onAppear { ringPulse = true }

                Spacer().frame(height: 30)

                VStack(spacing: 6) {
                    Text("ARTICREN WAVE")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .kerning(5)
                    Text("AR Classical Score Writing")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(appState.theme.accent.opacity(0.7))
                        .kerning(2)
                    Text("DART Meadow · Radical Deepscale")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.28))
                }

                Spacer()

                VStack(spacing: 14) {

                    // Sign In with Apple — using UIViewRepresentable for crash safety
                    AWAppleSignInButton { result in
                        switch result {
                        case .success(let auth):
                            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential else { return }
                            let name = [cred.fullName?.givenName, cred.fullName?.familyName]
                                .compactMap { $0 }.joined(separator: " ")
                            DispatchQueue.main.async {
                                authManager.userID       = cred.user
                                authManager.userFullName = name.isEmpty
                                    ? (UserDefaults.standard.string(forKey: "appleUserName") ?? "Composer")
                                    : name
                                authManager.userEmail    = cred.email
                                    ?? (UserDefaults.standard.string(forKey: "appleUserEmail") ?? "")
                                authManager.isSignedIn   = true
                                UserDefaults.standard.set(cred.user, forKey: "appleUserID")
                                if !name.isEmpty { UserDefaults.standard.set(name, forKey: "appleUserName") }
                                if let e = cred.email, !e.isEmpty {
                                    UserDefaults.standard.set(e, forKey: "appleUserEmail")
                                }
                            }
                        case .failure(let err):
                            authManager.authError = err.localizedDescription
                        }
                    }
                    .frame(height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    // Storage picker (collapsible)
                    if showStoragePicker {
                        HStack(spacing: 10) {
                            AWStorageChip(label: "On Device", icon: "iphone",
                                          isSelected: storageChoice == .device) {
                                storageChoice = .device
                            }
                            AWStorageChip(label: "iCloud", icon: "icloud",
                                          isSelected: storageChoice == .iCloud,
                                          isDisabled: !iCloudAvailable) {
                                if iCloudAvailable { storageChoice = .iCloud }
                            }
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // Continue as Guest
                    Button {
                        authManager.storagePreference = storageChoice
                        authManager.userFullName      = "Guest Composer"
                        authManager.isSignedIn        = true
                        UserDefaults.standard.set("guest", forKey: "appleUserID")
                        UserDefaults.standard.set("Guest Composer", forKey: "appleUserName")
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "person.fill").font(.system(size: 13))
                            Text("Continue as Guest").font(.system(size: 15, weight: .regular))
                        }
                        .foregroundColor(.white.opacity(0.52))
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(Color.white.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    // Storage toggle link
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            showStoragePicker.toggle()
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: showStoragePicker ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9))
                            Text("Storage: \(storageChoice.rawValue)")
                                .font(.system(size: 11, design: .monospaced))
                        }
                        .foregroundColor(.white.opacity(0.28))
                    }
                }
                .padding(.horizontal, 28)

                if let err = authManager.authError {
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundColor(.red.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.top, 8)
                }

                Spacer()

                Text("© 2026 DART Meadow LLC & Radical Deepscale LLC")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.2))
                    .padding(.bottom, 36)
            }
        }
        .onAppear {
            authManager.checkiCloudAvailability { available in iCloudAvailable = available }
        }
    }
}

// MARK: - UIViewRepresentable Apple Sign In Button (crash-safe in any context)
struct AWAppleSignInButton: UIViewRepresentable {
    let onCompletion: (Result<ASAuthorization, Error>) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCompletion: onCompletion) }

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let btn = ASAuthorizationAppleIDButton(type: .signIn, style: .white)
        btn.addTarget(context.coordinator,
                      action: #selector(Coordinator.tapped),
                      for: .touchUpInside)
        return btn
    }

    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {}

    class Coordinator: NSObject, ASAuthorizationControllerDelegate,
                       ASAuthorizationControllerPresentationContextProviding {
        let onCompletion: (Result<ASAuthorization, Error>) -> Void
        init(onCompletion: @escaping (Result<ASAuthorization, Error>) -> Void) {
            self.onCompletion = onCompletion
        }

        @objc func tapped() {
            let provider = ASAuthorizationAppleIDProvider()
            let request  = provider.createRequest()
            request.requestedScopes = [.fullName, .email]
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate                    = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }

        func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first(where: { $0.isKeyWindow }) ?? UIWindow()
        }

        func authorizationController(controller: ASAuthorizationController,
                                     didCompleteWithAuthorization auth: ASAuthorization) {
            onCompletion(.success(auth))
        }

        func authorizationController(controller: ASAuthorizationController,
                                     didCompleteWithError error: Error) {
            onCompletion(.failure(error))
        }
    }
}

struct AWStorageChip: View {
    @EnvironmentObject var appState: AppState
    let label: String
    let icon: String
    let isSelected: Bool
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12))
                Text(label).font(.system(size: 12, weight: .medium))
                if isSelected {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                }
            }
            .foregroundColor(isSelected ? appState.theme.accent : .white.opacity(isDisabled ? 0.2 : 0.55))
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? appState.theme.accent.opacity(0.12) : Color.white.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? appState.theme.accent.opacity(0.5) : Color.clear, lineWidth: 1))
            )
        }
        .disabled(isDisabled)
    }
}
