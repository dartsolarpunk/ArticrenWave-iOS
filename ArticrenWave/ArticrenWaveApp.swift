// ArticrenWaveApp.swift — App Entry Point
// Articren Wave · © 2026 DART Meadow LLC & Radical Deepscale LLC
import SwiftUI
import AuthenticationServices

@main
struct ArticrenWaveApp: App {
    @StateObject private var appState       = AppState()
    @StateObject private var authManager    = AuthManager()
    @StateObject private var projectManager = ProjectManager()
    @StateObject private var scoreEngine    = ScoreEngine()
    @StateObject private var audioEngine    = AudioEngine()

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

// MARK: - Root View
struct AWRootView: View {
    @EnvironmentObject var appState:    AppState
    @EnvironmentObject var authManager: AuthManager
    @State private var showSplash    = true
    @State private var splashDone    = false   // prevents restoreSession racing

    var body: some View {
        ZStack {
            Color(hex: "#08091A").ignoresSafeArea()

            if showSplash {
                AWSSplashView(onDone: {
                    splashDone = true
                    // Restore session AFTER splash — prevents race to MainComposerView
                    authManager.restoreSession()
                    withAnimation(.easeInOut(duration: 0.5)) {
                        showSplash = false
                    }
                })
                .transition(.opacity)
                .zIndex(10)

            } else if !authManager.isSignedIn {
                AWWelcomeView()
                    .transition(.move(edge: .bottom).combined(with: .opacity))

            } else {
                // Wrap in NavigationStack for safety
                AWMainShell()
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.45), value: showSplash)
        .animation(.easeInOut(duration: 0.35), value: authManager.isSignedIn)
        // DO NOT call restoreSession here — called after splash completes
    }
}

// MARK: - Main Shell (lazy-loads composer so it doesn't init during transition)
struct AWMainShell: View {
    @EnvironmentObject var appState:    AppState
    @EnvironmentObject var authManager: AuthManager
    @State private var loaded = false

    var body: some View {
        ZStack {
            appState.theme.background.ignoresSafeArea()

            if loaded {
                MainComposerView()
            } else {
                // Brief loading frame while composer initializes
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(appState.theme.accent)
                        .scaleEffect(1.2)
                    Text("Loading workspace…")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }
                .onAppear {
                    // Give SwiftUI one frame to settle before loading heavy views
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        loaded = true
                    }
                }
            }
        }
    }
}
