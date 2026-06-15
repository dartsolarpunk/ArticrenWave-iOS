// AWRootView.swift — Root nav: splash → welcome → main layout
import SwiftUI

struct AWRootView: View {
    @Environment(AppState.self)    private var appState
    @Environment(AuthManager.self) private var authManager
    @State private var showSplash = true

    var body: some View {
        ZStack {
            Color(hex: "#08091A").ignoresSafeArea()

            if showSplash {
                AWSSplashView {
                    authManager.restoreSession()
                    withAnimation(.easeInOut(duration: 0.5)) { showSplash = false }
                }
                .transition(.opacity)
                .zIndex(10)

            } else if !authManager.isSignedIn {
                AWWelcomeView()
                    .transition(.move(edge: .bottom).combined(with: .opacity))

            } else {
                AWMainLayout()
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.45), value: showSplash)
        .animation(.easeInOut(duration: 0.35), value: authManager.isSignedIn)
    }
}
