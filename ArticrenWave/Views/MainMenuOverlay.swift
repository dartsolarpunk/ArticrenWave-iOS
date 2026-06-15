// MainMenuOverlay.swift — Slide-out main menu panel
import SwiftUI
import PhotosUI

struct MainMenuOverlay: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var projectManager: ProjectManager
    @EnvironmentObject var scoreEngine: ScoreEngine

    @State private var showNewDocAlert = false
    @State private var showProfileSection = true
    @State private var showProjectsSection = true
    @State private var avatarItem: PhotosPickerItem? = nil
    @State private var avatarImage: Image? = nil
    @State private var showThemePicker = false

    var body: some View {
        HStack(spacing: 0) {
            // Panel
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    HStack {
                        ArticrenWaveLogoMark()
                            .frame(width: 32, height: 32)
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

                    // Profile section
                    MenuSection(title: "PROFILE", isExpanded: $showProfileSection) {
                        VStack(spacing: 12) {
                            HStack(spacing: 14) {
                                // Avatar
                                ZStack {
                                    if let img = avatarImage {
                                        img.resizable()
                                            .scaledToFill()
                                            .frame(width: 52, height: 52)
                                            .clipShape(Circle())
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
                                        Circle()
                                            .fill(Color.black.opacity(0.3))
                                            .frame(width: 20, height: 20)
                                            .overlay(Image(systemName: "camera.fill").font(.system(size: 9)).foregroundColor(.white))
                                            .offset(x: 16, y: 16)
                                    }
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(authManager.userFullName.isEmpty ? "Composer" : authManager.userFullName)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white)
                                    if !authManager.userEmail.isEmpty {
                                        Text(authManager.userEmail)
                                            .font(.system(size: 11))
                                            .foregroundColor(.white.opacity(0.4))
                                    }
                                    Text("Storage: \(authManager.storagePreference.rawValue)")
                                        .font(.system(size: 10))
                                        .foregroundColor(appState.theme.accent.opacity(0.7))
                                }
                                Spacer()
                            }

                            Button {
                                authManager.signOut()
                                withAnimation { appState.isMainMenuOpen = false }
                            } label: {
                                Text("Sign Out")
                                    .font(.system(size: 12))
                                    .foregroundColor(.red.opacity(0.7))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color.red.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }

                    Divider().background(Color.white.opacity(0.08)).padding(.horizontal, 16)

                    // Score actions
                    MenuSection(title: "SCORE", isExpanded: .constant(true)) {
                        VStack(spacing: 2) {
                            MenuActionRow(icon: "doc.badge.plus", label: "New Score") {
                                showNewDocAlert = true
                            }
                            MenuActionRow(icon: "folder", label: "Open Project") {
                                // Opens file browser
                            }
                            MenuActionRow(icon: "icloud.and.arrow.down", label: "Import") {
                                // Import from files
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Divider().background(Color.white.opacity(0.08)).padding(.horizontal, 16)

                    // Recent projects
                    MenuSection(title: "RECENT PROJECTS", isExpanded: $showProjectsSection) {
                        if projectManager.recentProjects.isEmpty {
                            Text("No recent projects")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.25))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                        } else {
                            ForEach(projectManager.recentProjects.prefix(5)) { meta in
                                RecentProjectRow(meta: meta)
                            }
                        }
                    }

                    Divider().background(Color.white.opacity(0.08)).padding(.horizontal, 16)

                    // Theme
                    MenuSection(title: "APPEARANCE", isExpanded: .constant(true)) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(AppTheme.allCases, id: \.self) { theme in
                                    Button {
                                        appState.setTheme(theme)
                                    } label: {
                                        VStack(spacing: 4) {
                                            Circle()
                                                .fill(theme.accent)
                                                .frame(width: 28, height: 28)
                                                .overlay(
                                                    Circle().stroke(
                                                        appState.theme == theme ? .white : .clear,
                                                        lineWidth: 2
                                                    )
                                                )
                                            Text(theme.rawValue.components(separatedBy: " ").last ?? "")
                                                .font(.system(size: 8))
                                                .foregroundColor(appState.theme == theme ? .white : .white.opacity(0.4))
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                    }

                    Divider().background(Color.white.opacity(0.08)).padding(.horizontal, 16)

                    // About
                    MenuSection(title: "ABOUT", isExpanded: .constant(true)) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Articren Wave v1.0")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white.opacity(0.7))
                            Text("Augmented Reality Classical Score Writing\nby DART Meadow LLC & Radical Deepscale LLC")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.35))
                            Text("Powered by LEATR Neural Architecture")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(appState.theme.accent.opacity(0.6))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }

                    Spacer().frame(height: 40)
                }
            }
            .frame(width: 300)
            .background(Color(hex: "#0E0E16").opacity(0.98))

            // Tap outside to close
            Color.black.opacity(0.45)
                .ignoresSafeArea()
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
        .onChange(of: avatarItem) { _ in
            Task {
                if let data = try? await avatarItem?.loadTransferable(type: Data.self),
                   let ui = UIImage(data: data) {
                    avatarImage = Image(uiImage: ui)
                }
            }
        }
    }
}

struct MenuSection<Content: View>: View {
    @EnvironmentObject var appState: AppState
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(appState.theme.accent.opacity(0.6))
                        .tracking(1.5)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.3))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            if isExpanded {
                content()
            }
        }
    }
}

struct MenuActionRow: View {
    @EnvironmentObject var appState: AppState
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

struct RecentProjectRow: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var projectManager: ProjectManager
    @EnvironmentObject var scoreEngine: ScoreEngine

    let meta: ProjectManager.ProjectMeta

    var body: some View {
        Button {
            projectManager.load(from: URL(fileURLWithPath: meta.filePath)) { doc in
                if let doc = doc { scoreEngine.document = doc }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: meta.iCloudSynced ? "icloud" : "doc.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.35))
                VStack(alignment: .leading, spacing: 2) {
                    Text(meta.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(1)
                    Text(meta.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.3))
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}
