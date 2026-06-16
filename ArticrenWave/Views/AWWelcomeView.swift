// AWWelcomeView.swift — Welcome + Sign In with Apple + username picker
import SwiftUI
import AuthenticationServices

struct AWWelcomeView: View {
    @Environment(AppState.self)    private var appState
    @Environment(AuthManager.self) private var authManager
    @State private var ringPulse = false
    @State private var showUsernameSheet = false
    @State private var pendingUserID     = ""
    @State private var pendingName       = ""
    @State private var pendingEmail      = ""
    @State private var storageChoice: StoragePreference = .device
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
                        .animation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true), value: ringPulse)
                    Circle().fill(Color(hex: "#0E0A1E")).frame(width: 156, height: 156)
                    Circle()
                        .stroke(LinearGradient(
                            colors: [appState.theme.accent.opacity(0.5), appState.theme.secondary.opacity(0.3)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ), lineWidth: 1.5)
                        .frame(width: 156, height: 156)
                    Image("AppLogo")
                        .resizable().scaledToFill()
                        .frame(width: 148, height: 148).clipShape(Circle())
                }
                .onAppear { ringPulse = true }

                Spacer().frame(height: 30)

                VStack(spacing: 6) {
                    Text("ARTICREN WAVE")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white).kerning(5)
                    Text("AR Classical Score Writing")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(appState.theme.accent.opacity(0.7)).kerning(2)
                    Text("DART Meadow · Radical Deepscale")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.28))
                }

                Spacer()

                VStack(spacing: 14) {
                    // Sign In with Apple
                    AWAppleSignInButton { result in
                        switch result {
                        case .success(let auth):
                            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential else { return }
                            let name = [cred.fullName?.givenName, cred.fullName?.familyName]
                                .compactMap { $0 }.joined(separator: " ")
                            let uid = cred.user
                            let email = cred.email ?? UserDefaults.standard.string(forKey: "appleUserEmail") ?? ""
                            let savedName = UserDefaults.standard.string(forKey: "appleUserName") ?? ""

                            if savedName.isEmpty && name.isEmpty {
                                // First time — show username picker
                                pendingUserID = uid
                                pendingName   = name
                                pendingEmail  = email
                                showUsernameSheet = true
                            } else {
                                // Returning user
                                let finalName = name.isEmpty ? savedName : name
                                UserDefaults.standard.set(uid, forKey: "appleUserID")
                                if !finalName.isEmpty { UserDefaults.standard.set(finalName, forKey: "appleUserName") }
                                if !email.isEmpty { UserDefaults.standard.set(email, forKey: "appleUserEmail") }
                                DispatchQueue.main.async {
                                    authManager.userID       = uid
                                    authManager.userFullName = finalName
                                    authManager.userEmail    = email
                                    authManager.storagePreference = storageChoice
                                    authManager.isSignedIn   = true
                                }
                            }
                        case .failure(let err):
                            let code = (err as NSError).code
                            // 1001 = user cancelled, 1000 = TestFlight/unknown (not a real error)
                            if code != 1001 && code != 1000 {
                                authManager.authError = "Sign in unavailable. Please try Continue as Guest."
                            } else {
                                authManager.authError = nil
                            }
                        }
                    }
                    .frame(height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    // Storage picker
                    if showStoragePicker {
                        HStack(spacing: 10) {
                            AWStorageChip(label: "On Device", icon: "iphone",
                                          isSelected: storageChoice == .device) { storageChoice = .device }
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
                        authManager.userFullName = "Guest Composer"
                        authManager.isSignedIn   = true
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
                        .font(.system(size: 11)).foregroundColor(.red.opacity(0.8))
                        .multilineTextAlignment(.center).padding(.horizontal, 28).padding(.top, 8)
                }

                Spacer()

                Text("© 2026 DART Meadow LLC & Radical Deepscale LLC")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.2)).padding(.bottom, 36)
            }
        }
        .onAppear { authManager.checkiCloudAvailability { available in iCloudAvailable = available } }
        // Username picker sheet
        .sheet(isPresented: $showUsernameSheet) {
            UsernamePickerSheet(
                pendingUserID: pendingUserID,
                pendingEmail:  pendingEmail,
                storageChoice: storageChoice
            ) { username in
                showUsernameSheet = false
                UserDefaults.standard.set(pendingUserID, forKey: "appleUserID")
                UserDefaults.standard.set(username,      forKey: "appleUserName")
                if !pendingEmail.isEmpty {
                    UserDefaults.standard.set(pendingEmail, forKey: "appleUserEmail")
                }
                DispatchQueue.main.async {
                    authManager.userID       = pendingUserID
                    authManager.userFullName = username
                    authManager.userEmail    = pendingEmail
                    authManager.storagePreference = storageChoice
                    authManager.isSignedIn   = true
                }
            }
        }
    }
}

// MARK: - Username Picker Sheet (first sign-in)
struct UsernamePickerSheet: View {
    @Environment(AppState.self) private var appState
    let pendingUserID:  String
    let pendingEmail:   String
    let storageChoice:  StoragePreference
    let onComplete:     (String) -> Void

    @State private var username    = ""
    @State private var isChecking  = false
    @State private var errorMsg    = ""
    @State private var isAvailable = false

    // Reserved/taken names for demo — in production this would hit a CloudKit check
    let reservedNames = ["admin","articren","dartmeadow","leatr","wave","composer"]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#08091A").ignoresSafeArea()
                VStack(spacing: 28) {
                    VStack(spacing: 8) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 48)).foregroundColor(appState.theme.accent)
                        Text("Choose Your Username")
                            .font(.system(size: 22, weight: .bold, design: .rounded)).foregroundColor(.white)
                        Text("This will display on your profile.\nChoose something unique.")
                            .font(.system(size: 13)).foregroundColor(.white.opacity(0.45))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("USERNAME")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4)).kerning(1.5)

                        HStack(spacing: 10) {
                            Text("@").foregroundColor(appState.theme.accent)
                                .font(.system(size: 16, weight: .semibold))
                            TextField("yourname", text: $username)
                                .textFieldStyle(.plain)
                                .font(.system(size: 18, weight: .medium, design: .monospaced))
                                .foregroundColor(.white)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .onChange(of: username) { _, val in
                                    username = val.lowercased()
                                        .filter { $0.isLetter || $0.isNumber || $0 == "_" }
                                    isAvailable = false
                                    errorMsg    = ""
                                }
                            if isChecking {
                                ProgressView().tint(appState.theme.accent).scaleEffect(0.8)
                            } else if isAvailable && !username.isEmpty {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }
                        .padding(14)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .stroke(isAvailable ? Color.green.opacity(0.5) : appState.theme.accent.opacity(0.25), lineWidth: 1))

                        if !errorMsg.isEmpty {
                            Text(errorMsg).font(.system(size: 11)).foregroundColor(.red.opacity(0.8))
                        } else if username.count < 3 && !username.isEmpty {
                            Text("At least 3 characters required")
                                .font(.system(size: 11)).foregroundColor(.white.opacity(0.3))
                        }
                    }
                    .padding(.horizontal, 24)

                    VStack(spacing: 12) {
                        // Check availability button
                        Button {
                            checkAvailability()
                        } label: {
                            Text(isChecking ? "Checking…" : "Check Availability")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(appState.theme.accent)
                                .frame(maxWidth: .infinity).frame(height: 44)
                                .background(appState.theme.accent.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12)
                                    .stroke(appState.theme.accent.opacity(0.3), lineWidth: 1))
                        }
                        .disabled(username.count < 3 || isChecking)

                        // Confirm
                        Button {
                            let finalName = username.isEmpty ? "Composer" : "@\(username)"
                            onComplete(finalName)
                        } label: {
                            Text("Create Account")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity).frame(height: 52)
                                .background(isAvailable
                                    ? LinearGradient(colors: [appState.theme.accent, appState.theme.accent.opacity(0.7)],
                                                     startPoint: .leading, endPoint: .trailing)
                                    : LinearGradient(colors: [Color.white.opacity(0.1), Color.white.opacity(0.05)],
                                                     startPoint: .leading, endPoint: .trailing))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(!isAvailable && !username.isEmpty)

                        Button("Skip for now") {
                            onComplete(pendingEmail.components(separatedBy: "@").first ?? "Composer")
                        }
                        .font(.system(size: 12)).foregroundColor(.white.opacity(0.3))
                    }
                    .padding(.horizontal, 24)

                    Spacer()
                }
            }
            .navigationTitle("").navigationBarHidden(true)
        }
        .presentationDetents([.large])
    }

    func checkAvailability() {
        guard username.count >= 3 else { return }
        isChecking = true
        errorMsg   = ""

        // Simulate async check (in production: CloudKit query)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            isChecking = false
            let taken = reservedNames.contains(username) ||
                        UserDefaults.standard.bool(forKey: "taken_\(username)")

            if taken {
                isAvailable = false
                errorMsg    = "'\(username)' is already taken. Try another."
            } else {
                isAvailable = true
                errorMsg    = ""
                // Mark locally so same device can't reuse it
                UserDefaults.standard.set(true, forKey: "taken_\(username)")
            }
        }
    }
}

// MARK: - Staff Lines Background
struct AWStaffLines: View {
    var body: some View {
        Canvas { ctx, size in
            let spacing = size.height / 6
            for i in 1...5 {
                var p = Path()
                let y = CGFloat(i) * spacing
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(p, with: .color(.white.opacity(0.04)), lineWidth: 0.5)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Apple Sign In Button (UIViewRepresentable — crash-safe)
struct AWAppleSignInButton: UIViewRepresentable {
    let onCompletion: (Result<ASAuthorization, Error>) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onCompletion: onCompletion) }
    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let btn = ASAuthorizationAppleIDButton(type: .signIn, style: .white)
        btn.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        return btn
    }
    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {}

    class Coordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
        let onCompletion: (Result<ASAuthorization, Error>) -> Void
        init(onCompletion: @escaping (Result<ASAuthorization, Error>) -> Void) { self.onCompletion = onCompletion }

        @objc func tapped() {
            let provider = ASAuthorizationAppleIDProvider()
            let request  = provider.createRequest()
            request.requestedScopes = [.fullName, .email]
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
        func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }
                .first(where: { $0.isKeyWindow }) ?? UIWindow()
        }
        func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization auth: ASAuthorization) {
            onCompletion(.success(auth))
        }
        func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
            onCompletion(.failure(error))
        }
    }
}

// MARK: - Storage Chip
struct AWStorageChip: View {
    @Environment(AppState.self) private var appState
    let label: String; let icon: String; let isSelected: Bool
    var isDisabled: Bool = false; let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12))
                Text(label).font(.system(size: 12, weight: .medium))
                if isSelected { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)) }
            }
            .foregroundColor(isSelected ? appState.theme.accent : .white.opacity(isDisabled ? 0.2 : 0.55))
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? appState.theme.accent.opacity(0.12) : Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? appState.theme.accent.opacity(0.5) : Color.clear, lineWidth: 1)))
        }
        .disabled(isDisabled)
    }
}
