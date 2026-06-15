// ArticrenWaveApp.swift — iOS 17+ @Observable entry point
import SwiftUI

@main
struct ArticrenWaveApp: App {
    // @Observable singletons — no StateObject/EnvironmentObject needed
    private let appState      = AppState.shared
    private let authManager   = AuthManager.shared
    private let scoreEngine   = ScoreEngine.shared
    private let audioEngine   = AudioEngine.shared
    private let projectManager = ProjectManager.shared

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
