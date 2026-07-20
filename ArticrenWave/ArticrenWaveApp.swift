// ArticrenWaveApp.swift — iOS 17+ @Observable entry point
import SwiftUI

@main
struct ArticrenWaveApp: App {
    private let appState       = AppState.shared
    private let authManager    = AuthManager.shared
    private let scoreEngine    = ScoreEngine.shared
    private let audioEngine    = AudioEngine.shared
    private let projectManager = ProjectManager.shared

    init() {
        // Restore saved accent color
        if let hex = UserDefaults.standard.string(forKey: "aw_accent_hex") {
            AppState.shared.theme.accent = Color(hex: hex)
        }
        // Audio engine starts lazily on first sound request (starting at App.init crashes on iOS 27 — session not active yet)
    }

    var body: some Scene {
        WindowGroup {
            AWRootView()
                .environment(appState)
                .environment(authManager)
                .environment(scoreEngine)
                .environment(audioEngine)
                .environment(projectManager)
                .preferredColorScheme(.dark)
        }
    }
}
