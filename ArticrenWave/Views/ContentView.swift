// ContentView.swift — Root layout shell for ArticrenWave
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var projectManager: ProjectManager
    @EnvironmentObject var scoreEngine: ScoreEngine
    @EnvironmentObject var audioEngine: AudioEngine

    var body: some View {
        ZStack {
            appState.theme.background.ignoresSafeArea()

            if !authManager.isSignedIn {
                OnboardingView()
            } else {
                MainComposerView()
            }

            // Main slide-out menu overlay
            if appState.isMainMenuOpen {
                MainMenuOverlay()
                    .transition(.move(edge: .leading))
                    .zIndex(100)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: appState.isMainMenuOpen)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: authManager.isSignedIn)
        .statusBarHidden(false)
    }
}
