// AWSSplashView.swift — Animated splash screen
// Articren Wave · © 2026 DART Meadow LLC & Radical Deepscale LLC
import SwiftUI

struct AWSSplashView: View {
    let onDone: () -> Void

    @Environment(AppState.self) private var appState
    @State private var logoScale:   CGFloat = 0.65
    @State private var logoOpacity: Double  = 0
    @State private var titleOpacity: Double = 0
    @State private var tagOpacity:   Double = 0
    @State private var ringPulse = false
    @State private var bootText = "Initializing score engine…"
    let bootLines = [
        "Initializing score engine…",
        "Loading instrument library…",
        "Preparing grand staff…",
        "Ready."
    ]

    var body: some View {
        ZStack {
            // Deep cosmic background matching the logo artwork
            LinearGradient(
                colors: [Color(hex: "#08091A"), Color(hex: "#12062A"), Color(hex: "#08091A")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ).ignoresSafeArea()

            // Subtle staff lines behind logo
            AWStaffLines()

            VStack(spacing: 0) {
                Spacer()

                // Logo orb
                ZStack {
                    // Outer pulse ring
                    Circle()
                        .stroke(appState.theme.accent.opacity(0.07), lineWidth: 1)
                        .frame(width: ringPulse ? 240 : 200, height: ringPulse ? 240 : 200)
                        .animation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true),
                                   value: ringPulse)

                    // Mid ring
                    Circle()
                        .stroke(appState.theme.accent.opacity(0.18), lineWidth: 1.2)
                        .frame(width: 168, height: 168)

                    // Logo fill
                    Circle()
                        .fill(Color(hex: "#0E0A1E"))
                        .frame(width: 156, height: 156)

                    // App logo image
                    Image("AppLogo")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 148, height: 148)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [appState.theme.accent.opacity(0.6),
                                                 appState.theme.secondary.opacity(0.4)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.5
                                )
                        )
                }
                .scaleEffect(logoScale)
                .opacity(logoOpacity)
                .onAppear {
                    withAnimation(.spring(response: 0.75, dampingFraction: 0.62).delay(0.1)) {
                        logoScale   = 1.0
                        logoOpacity = 1.0
                    }
                    ringPulse = true
                }

                Spacer().frame(height: 36)

                // Wordmark
                VStack(spacing: 7) {
                    Text("ARTICREN WAVE")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .kerning(5)
                        .opacity(titleOpacity)

                    Text("AR CLASSICAL SCORE WRITING")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(appState.theme.accent.opacity(0.75))
                        .kerning(2.5)
                        .opacity(tagOpacity)

                    Text("LEATR · DART Meadow · Radical Deepscale")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.28))
                        .kerning(1.2)
                        .opacity(tagOpacity)
                }

                Spacer()

                // Boot line
                Text(bootText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(appState.theme.accent.opacity(0.35))
                    .opacity(tagOpacity)
                    .padding(.bottom, 54)
                    .animation(.easeInOut(duration: 0.3), value: bootText)
            }
        }
        .onAppear {
            withAnimation(.easeIn(duration: 0.45).delay(0.45)) { titleOpacity = 1 }
            withAnimation(.easeIn(duration: 0.45).delay(0.7))  { tagOpacity   = 1 }

            // Cycle boot lines
            for (i, line) in bootLines.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8 + Double(i) * 0.38) {
                    bootText = line
                }
            }
            // Dismiss
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { onDone() }
        }
    }
}

// Subtle staff lines background decor
