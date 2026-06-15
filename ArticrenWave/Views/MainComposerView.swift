// MainComposerView.swift — Professional score composer layout
import SwiftUI

struct MainComposerView: View {
    @Environment(AppState.self)    private var appState
    @Environment(ScoreEngine.self) private var scoreEngine
    @Environment(AudioEngine.self) private var audioEngine
    @Environment(ProjectManager.self) private var projectManager

    @State private var showProjectBrowser = false
    @State private var showExportSheet    = false
    @State private var showLayoutPicker   = false
    @State private var showTempoSheet     = false
    @State private var showMainMenu       = false
    @State private var zoom: CGFloat      = 1.0

    var body: some View {
        ZStack {
            Color(hex: "#080910").ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Top toolbar ───────────────────────────────────
                ComposerTopBar(
                    showProjectBrowser: $showProjectBrowser,
                    showExportSheet:    $showExportSheet,
                    showLayoutPicker:   $showLayoutPicker,
                    showTempoSheet:     $showTempoSheet,
                    showMainMenu:       $showMainMenu
                )

                // ── Note palette ──────────────────────────────────
                NotePalette()
                    .frame(height: 62)

                // ── Validation banner ─────────────────────────────
                if let err = scoreEngine.validationError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                        Text(err)
                            .font(.system(size: 11))
                            .foregroundColor(.orange.opacity(0.9))
                        Spacer()
                        Button { scoreEngine.validationError = nil } label: {
                            Image(systemName: "xmark").font(.system(size: 10)).foregroundColor(.white.opacity(0.4))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.12))
                    .overlay(Rectangle().fill(Color.orange.opacity(0.3)).frame(height: 1), alignment: .bottom)
                }

                // ── Score canvas ──────────────────────────────────
                SafeScoreCanvas()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // ── Playback bar ──────────────────────────────────
                PlaybackBarView()
                    .frame(height: 72)

                // ── Piano drawer ──────────────────────────────────
                if appState.isPianoDrawerOpen {
                    PianoDrawerView()
                        .frame(height: pianoHeight)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Piano pull tab
                PianoPullTab()
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: appState.isPianoDrawerOpen)
        // Sheets
        .sheet(isPresented: $showProjectBrowser) { ProjectBrowserView(isPresented: $showProjectBrowser) }
        .sheet(isPresented: $showExportSheet)    { ExportSheet() }
        .sheet(isPresented: $showLayoutPicker)   { LayoutPickerSheet() }
        .sheet(isPresented: $showTempoSheet)     { TempoSheet() }
        // Main menu overlay
        .overlay {
            if showMainMenu {
                MainMenuOverlay()
                    .transition(.move(edge: .leading))
                    .zIndex(100)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showMainMenu)
        .onChange(of: showMainMenu) { _, val in appState.isMainMenuOpen = val }
        .onChange(of: appState.isMainMenuOpen) { _, val in showMainMenu = val }
    }

    var pianoHeight: CGFloat {
        UIScreen.main.bounds.height > 736 ? 220 : 180
    }
}

// MARK: - Composer Top Bar
struct ComposerTopBar: View {
    @Environment(AppState.self)    private var appState
    @Environment(ScoreEngine.self) private var scoreEngine
    @Environment(AudioEngine.self) private var audioEngine
    @Binding var showProjectBrowser: Bool
    @Binding var showExportSheet:    Bool
    @Binding var showLayoutPicker:   Bool
    @Binding var showTempoSheet:     Bool
    @Binding var showMainMenu:       Bool

    var body: some View {
        HStack(spacing: 0) {
            // Menu
            Button { withAnimation { showMainMenu = true } } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 44, height: 44)
            }

            // Score title
            Button { showProjectBrowser = true } label: {
                HStack(spacing: 4) {
                    Text(scoreEngine.document.title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 2)

            // Actions
            HStack(spacing: 6) {
                TopBarButton(icon: "metronome.fill") { showTempoSheet = true }
                TopBarButton(icon: "music.note.list") { showLayoutPicker = true }
                TopBarButton(icon: "square.and.arrow.up") { showExportSheet = true }

                // Record button
                Button {
                    if scoreEngine.isRecording {
                        scoreEngine.stopRecording()
                    } else {
                        scoreEngine.startRecording()
                    }
                } label: {
                    Circle()
                        .fill(scoreEngine.isRecording ? Color.red : Color.white.opacity(0.08))
                        .frame(width: 30, height: 30)
                        .overlay(
                            Circle()
                                .fill(Color.red)
                                .frame(width: scoreEngine.isRecording ? 10 : 12, height: scoreEngine.isRecording ? 10 : 12)
                                .opacity(scoreEngine.isRecording ? 0 : 1)
                        )
                        .overlay(
                            Image(systemName: "stop.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.white)
                                .opacity(scoreEngine.isRecording ? 1 : 0)
                        )
                }
                .padding(.trailing, 8)
            }
        }
        .frame(height: 50)
        .background(
            Color(hex: "#0C0D18")
                .overlay(Rectangle().fill(Color.white.opacity(0.04)))
        )
        .overlay(Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1), alignment: .bottom)
    }
}

struct TopBarButton: View {
    @Environment(AppState.self) private var appState
    let icon: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.65))
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - Piano Pull Tab
struct PianoPullTab: View {
    @Environment(AppState.self)    private var appState
    @Environment(AudioEngine.self) private var audioEngine

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                appState.isPianoDrawerOpen.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: appState.isPianoDrawerOpen ? "chevron.down" : "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                Image(systemName: "pianokeys")
                    .font(.system(size: 12))
                Text(appState.isPianoDrawerOpen ? "Hide Piano" : "Piano · \(audioEngine.currentInstrumentName)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                if !appState.isPianoDrawerOpen {
                    Capsule()
                        .fill(appState.theme.accent.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
            .foregroundColor(.white.opacity(0.7))
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(Color(hex: "#1A1B28"))
                    .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
            )
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color(hex: "#080910"))
    }
}
