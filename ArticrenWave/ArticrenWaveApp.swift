// ArticrenWave — Augmented Reality Classical Music Score Writing App
// © 2026 DART Meadow LLC & Radical Deepscale LLC
// Bundle ID: ArticrenWaveAppStore

import SwiftUI
import AuthenticationServices
import CloudKit

@main
struct ArticrenWaveApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var authManager = AuthManager()
    @StateObject private var projectManager = ProjectManager()
    @StateObject private var scoreEngine = ScoreEngine()
    @StateObject private var audioEngine = AudioEngine()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(authManager)
                .environmentObject(projectManager)
                .environmentObject(scoreEngine)
                .environmentObject(audioEngine)
                .preferredColorScheme(.dark)
                .onAppear {
                    audioEngine.preloadSounds()
                }
        }
    }
}
