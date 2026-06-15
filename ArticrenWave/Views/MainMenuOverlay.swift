// MainMenuOverlay.swift — Slide-out main menu (safe @Observable version)
import SwiftUI
import PhotosUI

struct MainMenuOverlay: View {
    @Environment(AppState.self)    private var appState
    @Environment(AuthManager.self) private var authManager
    @Environment(ScoreEngine.self) private var scoreEngine

    @State private var showNewDocAlert = false
    @State private var avatarItem: PhotosPickerItem? = nil
    @State private var avatarImage: Image? = nil

    var body: some View {
        HStack(spacing: 0) {
            // Panel
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // Header
                    HStack {
                        ArticrenWaveLogoMark().frame(width: 32, height: 32)
                        Text("Articren Wave")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                        Spacer()
                        Button {
                            withAnimation { appState.isMainMenuOpen = false }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.5))
                                .frame(width: 32, height: 32)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 56)
                    .padding(.bottom, 16)

                    Divider().background(Color.white.opacity(0.08)).padding(.horizontal, 16)

                    // Profile
                    VStack(alignment: .leading, spacing: 12) {
                        Text("PROFILE")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(appState.theme.accent.opacity(0.6))
                            .kerning(1.5)
                            .padding(.horizontal, 16)
                            .padding(.top, 10)

                        HStack(spacing: 14) {
                            // Avatar
                            ZStack {
                                if let img = avatarImage {
                                    img.resizable().scaledToFill()
                                        .frame(width: 52, height: 52).clipShape(Circle())
                                } else {
                                    Circle()
                                        .fill(appState.theme.accent.opacity(0.2))
                                        .frame(width: 52, height: 52)
                                        .overlay(
                                            Text(authManager.userFullName.prefix(1))
                                                .font(.system(size: 22, weight: .semibold))
                                                .foregroundColor(appState.theme.accent)
                                        )
                                }
                                PhotosPicker(selection: $avatarItem, matching: .images) {
                                    Circle().fill(Color.black.opacity(0.3))
                                        .frame(width: 20, height: 20)
                                        .overlay(Image(systemName: "camera.fill")
                                            .font(.system(size: 9)).foregroundColor(.white))
                                        .offset(x: 16, y: 16)
                                }
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(authManager.userFullName.isEmpty ? "Composer" : authManager.userFullName)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                if authManager.isGuest {
                                    Text("GUEST MODE")
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .foregroundColor(appState.theme.secondary.opacity(0.8))
                                        .kerning(1)
                                } else if !authManager.userEmail.isEmpty {
                                    Text(authManager.userEmail)
                                        .font(.system(size: 11))
                                        .foregroundColor(.white.opacity(0.4))
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)

                        Button {
                            withAnimation {
                                appState.isMainMenuOpen = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    authManager.signOut()
                                }
                            }
                        } label: {
                            Label(authManager.isGuest ? "Exit Guest Mode" : "Sign Out",
                                  systemImage: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.red.opacity(0.75))
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(Color.red.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                    }

                    Divider().background(Color.white.opacity(0.08)).padding(.horizontal, 16)

                    // Score actions
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SCORE")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(appState.theme.accent.opacity(0.6))
                            .kerning(1.5)
                            .padding(.horizontal, 16)
                            .padding(.top, 10)

                        MenuActionRow(icon: "doc.badge.plus", label: "New Score") {
                            showNewDocAlert = true
                        }
                        MenuActionRow(icon: "folder", label: "Open Project") { }
                    }
                    .padding(.vertical, 4)

                    Divider().background(Color.white.opacity(0.08)).padding(.horizontal, 16)

                    // Theme accent picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ACCENT COLOR")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(appState.theme.accent.opacity(0.6))
                            .kerning(1.5)
                            .padding(.horizontal, 16)
                            .padding(.top, 10)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach([
                                    ("Magenta", "#E040FB"), ("Cyan", "#00E5FF"),
                                    ("Green", "#00E676"),  ("Red", "#FF1744"),
                                    ("Blue", "#00B4FF"),   ("Gold", "#FFD600")
                                ], id: \.0) { name, hex in
                                    Button {
                                        appState.theme.accent = Color(hex: hex)
                                    } label: {
                                        VStack(spacing: 4) {
                                            Circle().fill(Color(hex: hex))
                                                .frame(width: 28, height: 28)
                                            Text(name)
                                                .font(.system(size: 8))
                                                .foregroundColor(.white.opacity(0.4))
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 10)
                        }
                    }

                    Divider().background(Color.white.opacity(0.08)).padding(.horizontal, 16)

                    // About
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ABOUT")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(appState.theme.accent.opacity(0.6))
                            .kerning(1.5)
                        Text("Articren Wave v1.0")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                        Text("AR Classical Score Writing\nDART Meadow LLC & Radical Deepscale LLC")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.35))
                        Text("Powered by LEATR Neural Architecture")
                            .font(.system(size: 10))
                            .foregroundColor(appState.theme.accent.opacity(0.6))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    Spacer().frame(height: 40)
                }
            }
            .frame(width: 300)
            .background(Color(hex: "#0E0E16").opacity(0.98))

            // Tap outside to close
            Color.black.opacity(0.45).ignoresSafeArea()
                .onTapGesture {
                    withAnimation { appState.isMainMenuOpen = false }
                }
        }
        .ignoresSafeArea()
        .alert("New Score", isPresented: $showNewDocAlert) {
            Button("New") {
                scoreEngine.newDocument()
                withAnimation { appState.isMainMenuOpen = false }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Start a new empty score? Unsaved changes will be lost.")
        }
        .onChange(of: avatarItem) { _, _ in
            Task {
                if let data = try? await avatarItem?.loadTransferable(type: Data.self),
                   let ui = UIImage(data: data) {
                    avatarImage = Image(uiImage: ui)
                }
            }
        }
    }
}

struct MenuActionRow: View {
    @Environment(AppState.self) private var appState
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(appState.theme.accent.opacity(0.8))
                    .frame(width: 20)
                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.2))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }
}
