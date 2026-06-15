// ArticrenWaveApp.swift — App Entry Point
// Articren Wave · © 2026 DART Meadow LLC & Radical Deepscale LLC
import SwiftUI
import AuthenticationServices

@main
struct ArticrenWaveApp: App {
    @StateObject private var appState    = AppState()
    @StateObject private var authManager = AuthManager()
    @StateObject private var projectManager = ProjectManager()
    @StateObject private var scoreEngine = ScoreEngine()
    @StateObject private var audioEngine = AudioEngine()

    var body: some Scene {
        WindowGroup {
            AWRootView()
                .environmentObject(appState)
                .environmentObject(authManager)
                .environmentObject(projectManager)
                .environmentObject(scoreEngine)
                .environmentObject(audioEngine)
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Root View (Splash → Welcome → Main)
struct AWRootView: View {
    @EnvironmentObject var appState:    AppState
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var audioEngine: AudioEngine
    @State private var showSplash = true

    var body: some View {
        ZStack {
            appState.theme.background.ignoresSafeArea()

            if showSplash {
                AWSSplashView(onDone: {
                    withAnimation(.easeInOut(duration: 0.5)) { showSplash = false }
                })
                .transition(.opacity)
                .zIndex(10)

            } else if !authManager.isSignedIn {
                AWWelcomeView()
                    .transition(.move(edge: .bottom).combined(with: .opacity))

            } else {
                MainComposerView()
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.4), value: showSplash)
        .animation(.easeInOut(duration: 0.35), value: authManager.isSignedIn)
        .onAppear { authManager.restoreSession() }
    }
}
