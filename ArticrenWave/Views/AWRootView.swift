// AWRootView.swift — Root navigation using @Environment (iOS 17+)
import SwiftUI

struct AWRootView: View {
    @Environment(AppState.self)   private var appState
    @Environment(AuthManager.self) private var authManager
    @State private var showSplash = true

    var body: some View {
        ZStack {
            Color(hex: "#08091A").ignoresSafeArea()

            if showSplash {
                AWSSplashView {
                    authManager.restoreSession()
                    withAnimation(.easeInOut(duration: 0.5)) {
                        showSplash = false
                    }
                }
                .transition(.opacity)
                .zIndex(10)

            } else if !authManager.isSignedIn {
                AWWelcomeView()
                    .transition(.move(edge: .bottom).combined(with: .opacity))

            } else {
                AWMainShell()
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.45), value: showSplash)
        .animation(.easeInOut(duration: 0.35), value: authManager.isSignedIn)
    }
}

struct AWMainShell: View {
    @Environment(AppState.self) private var appState
    @State private var loaded = false

    var body: some View {
        ZStack {
            appState.themeBackground.ignoresSafeArea()
            if loaded {
                MainComposerView()
            } else {
                VStack(spacing: 16) {
                    ProgressView().tint(appState.themeAccent).scaleEffect(1.2)
                    Text("Loading workspace…")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        loaded = true
                    }
                }
            }
        }
    }
}
