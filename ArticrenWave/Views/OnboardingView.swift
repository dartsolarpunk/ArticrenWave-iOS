// OnboardingView.swift — First launch: Sign In with Apple + storage setup
import SwiftUI
import AuthenticationServices

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authManager: AuthManager

    @State private var storageChoice: AuthManager.StoragePreference = .device
    @State private var iCloudAvailable: Bool = false
    @State private var step: Int = 0  // 0=welcome, 1=storage, 2=signing in

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color(hex: "#0A0A0F"), Color(hex: "#1A0524"), Color(hex: "#0A0A0F")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ).ignoresSafeArea()

            // Subtle grid lines (score staff aesthetic)
            StaffBackgroundDecor()

            VStack(spacing: 0) {
                Spacer()

                // Logo + title
                VStack(spacing: 16) {
                    // Articren Wave logo mark (vector recreation)
                    ArticrenWaveLogoMark()
                        .frame(width: 120, height: 120)

                    VStack(spacing: 4) {
                        Text("Articren Wave")
                            .font(.system(size: 32, weight: .thin, design: .rounded))
                            .foregroundColor(.white)
                            .tracking(2)
                        Text("AR Classical Score Writing")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.4))
                            .tracking(1.5)
                    }
                }

                Spacer().frame(height: 60)

                // Steps
                if step == 0 {
                    WelcomeStep { step = 1 }
                } else if step == 1 {
                    StorageStep(
                        storageChoice: $storageChoice,
                        iCloudAvailable: iCloudAvailable
                    ) {
                        authManager.storagePreference = storageChoice
                        step = 2
                    }
                } else {
                    SignInStep()
                }

                Spacer()

                // Footer
                Text("© 2026 DART Meadow LLC & Radical Deepscale LLC")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.2))
                    .padding(.bottom, 20)
            }
            .padding(.horizontal, 32)
        }
        .onAppear {
            authManager.checkiCloudAvailability { available in
                iCloudAvailable = available
            }
        }
    }
}

struct WelcomeStep: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 10) {
                FeatureRow(icon: "music.note.list", text: "Full Grand Staff Score Writing")
                FeatureRow(icon: "pianokeys", text: "88-Key Virtual Piano + 10 Instruments")
                FeatureRow(icon: "waveform.path.ecg", text: "Export MP3 / WAV / MIDI / PDF")
                FeatureRow(icon: "icloud.and.arrow.up", text: "iCloud Sync & Local Storage")
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
            )

            Button(action: onContinue) {
                Text("Get Started")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        LinearGradient(colors: [Color(hex: "#E040FB"), Color(hex: "#7B1FA2")],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "#E040FB"))
                .frame(width: 24)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.75))
            Spacer()
        }
    }
}

struct StorageStep: View {
    @Binding var storageChoice: AuthManager.StoragePreference
    let iCloudAvailable: Bool
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Where should your scores be stored?")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.center)

            VStack(spacing: 10) {
                StorageOption(
                    title: "On This Device",
                    subtitle: "Projects saved locally to your iPhone/iPad",
                    icon: "iphone",
                    isSelected: storageChoice == .device
                ) { storageChoice = .device }

                StorageOption(
                    title: "iCloud",
                    subtitle: iCloudAvailable ? "Sync across all your Apple devices" : "iCloud not available on this account",
                    icon: "icloud",
                    isSelected: storageChoice == .iCloud,
                    isDisabled: !iCloudAvailable
                ) {
                    if iCloudAvailable { storageChoice = .iCloud }
                }
            }

            Button(action: onContinue) {
                Text("Continue")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(LinearGradient(colors: [Color(hex: "#E040FB"), Color(hex: "#7B1FA2")],
                                               startPoint: .leading, endPoint: .trailing))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }
}

struct StorageOption: View {
    let title: String
    let subtitle: String
    let icon: String
    let isSelected: Bool
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(isSelected ? Color(hex: "#E040FB") : .white.opacity(0.4))
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isDisabled ? .white.opacity(0.3) : .white.opacity(0.9))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(isDisabled ? .white.opacity(0.2) : .white.opacity(0.45))
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? Color(hex: "#E040FB") : .white.opacity(0.25))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color(hex: "#E040FB").opacity(0.1) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color(hex: "#E040FB").opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .disabled(isDisabled)
    }
}

struct SignInStep: View {
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        VStack(spacing: 20) {
            Text("Sign in to save your work")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.8))

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                switch result {
                case .success(let auth):
                    if let credential = auth.credential as? ASAuthorizationAppleIDCredential {
                        let name = [credential.fullName?.givenName, credential.fullName?.familyName]
                            .compactMap { $0 }.joined(separator: " ")
                        authManager.userID = credential.user
                        authManager.userFullName = name.isEmpty ? "Composer" : name
                        authManager.userEmail = credential.email ?? ""
                        authManager.isSignedIn = true
                        UserDefaults.standard.set(credential.user, forKey: "appleUserID")
                        if !name.isEmpty { UserDefaults.standard.set(name, forKey: "appleUserName") }
                    }
                case .failure: break
                }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            Button("Skip for now") {
                authManager.userFullName = "Guest Composer"
                authManager.isSignedIn = true
            }
            .font(.system(size: 13))
            .foregroundColor(.white.opacity(0.35))
        }
    }
}

// MARK: - Logo Mark (vector recreation of Articren Wave)
struct ArticrenWaveLogoMark: View {
    var body: some View {
        Canvas { ctx, size in
            let s = size.width

            // Pink/magenta vertical lightning bolt
            let bolt = Path { p in
                p.move(to: CGPoint(x: s * 0.22, y: s * 0.05))
                p.addLine(to: CGPoint(x: s * 0.12, y: s * 0.50))
                p.addLine(to: CGPoint(x: s * 0.20, y: s * 0.50))
                p.addLine(to: CGPoint(x: s * 0.08, y: s * 0.95))
                p.addLine(to: CGPoint(x: s * 0.35, y: s * 0.45))
                p.addLine(to: CGPoint(x: s * 0.24, y: s * 0.45))
                p.addLine(to: CGPoint(x: s * 0.22, y: s * 0.05))
            }
            ctx.fill(bolt, with: .linearGradient(
                Gradient(colors: [Color(hex: "#FF00A0"), Color(hex: "#8B00FF")]),
                startPoint: CGPoint(x: s*0.1, y: 0),
                endPoint: CGPoint(x: s*0.1, y: s)
            ))

            // Purple diagonal slash
            let slash = Path { p in
                p.move(to: CGPoint(x: s * 0.30, y: s * 0.08))
                p.addLine(to: CGPoint(x: s * 0.90, y: s * 0.10))
                p.addLine(to: CGPoint(x: s * 0.85, y: s * 0.20))
                p.addLine(to: CGPoint(x: s * 0.25, y: s * 0.18))
            }
            ctx.fill(slash, with: .linearGradient(
                Gradient(colors: [Color(hex: "#8B00FF"), Color(hex: "#C040FB")]),
                startPoint: CGPoint(x: s*0.3, y: s*0.1),
                endPoint: CGPoint(x: s*0.9, y: s*0.1)
            ))

            // Cyan wave arc
            var wave = Path()
            wave.move(to: CGPoint(x: s * 0.18, y: s * 0.45))
            wave.addCurve(
                to: CGPoint(x: s * 0.45, y: s * 0.30),
                control1: CGPoint(x: s * 0.28, y: s * 0.55),
                control2: CGPoint(x: s * 0.38, y: s * 0.22)
            )
            ctx.stroke(wave, with: .linearGradient(
                Gradient(colors: [Color(hex: "#00BFFF"), Color(hex: "#7B00FF")]),
                startPoint: CGPoint(x: s*0.18, y: s*0.45),
                endPoint: CGPoint(x: s*0.45, y: s*0.3)
            ), style: StrokeStyle(lineWidth: s * 0.05, lineCap: .round))
        }
    }
}

// MARK: - Staff background decor
struct StaffBackgroundDecor: View {
    var body: some View {
        Canvas { ctx, size in
            for i in 0...8 {
                let y = size.height * 0.2 + CGFloat(i) * 12
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(path, with: .color(.white.opacity(0.03)), lineWidth: 0.5)
            }
        }
        .ignoresSafeArea()
    }
}
