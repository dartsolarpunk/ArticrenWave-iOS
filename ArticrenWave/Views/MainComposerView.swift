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

            // TEMP DIAGNOSTIC — shows exactly what the audio engine is doing right now.
            // Remove once sound is confirmed working.
            VStack {
                Text(AWAudioPlayer.shared.diagnostic)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.yellow)
                    .padding(6)
                    .background(Color.black.opacity(0.75))
                    .cornerRadius(6)
                    .padding(.top, 54)
                Spacer()
            }
            .zIndex(999)
            .allowsHitTesting(false)

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
                ScoreEditorView()
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
        // Sheets — must pass @Observable environments explicitly
        .sheet(isPresented: $showProjectBrowser) {
            ProjectBrowserView(isPresented: $showProjectBrowser)
                .environment(AppState.shared)
                .environment(ScoreEngine.shared)
                .environment(AuthManager.shared)
        }
        .sheet(isPresented: $showExportSheet) {
            ExportSheet()
                .environment(AppState.shared)
                .environment(ScoreEngine.shared)
                .environment(AudioEngine.shared)
        }
        .sheet(isPresented: $showLayoutPicker) {
            LayoutPickerSheet()
                .environment(AppState.shared)
                .environment(ScoreEngine.shared)
        }
        .sheet(isPresented: $showTempoSheet) {
            TempoSheet()
                .environment(AppState.shared)
                .environment(ScoreEngine.shared)
        }
        // Menu is handled by AWMainLayout drawer — just sync state
        .onChange(of: showMainMenu) { _, val in appState.isMainMenuOpen = val }
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
                // Undo / Redo
                Button { scoreEngine.undo() } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(scoreEngine.canUndo ? .white.opacity(0.75) : .white.opacity(0.2))
                        .frame(width: 30, height: 34)
                }.disabled(!scoreEngine.canUndo)
                Button { scoreEngine.redo() } label: {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(scoreEngine.canRedo ? .white.opacity(0.75) : .white.opacity(0.2))
                        .frame(width: 30, height: 34)
                }.disabled(!scoreEngine.canRedo)

                TopBarButton(icon: "metronome.fill") { showTempoSheet = true }
                TopBarButton(icon: "music.note.list") { showLayoutPicker = true }
                TopBarButton(icon: "square.and.arrow.up") { showExportSheet = true }

                // Record button — red pulse when live recording active
                Button {
                    if scoreEngine.isRecording {
                        scoreEngine.stopRecording()
                        // Ensure piano is open for live recording
                    } else {
                        scoreEngine.startRecording()
                        appState.isPianoDrawerOpen = true  // auto-open piano for recording
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(scoreEngine.isRecording ? Color.red : Color.white.opacity(0.08))
                            .frame(width: 32, height: 32)
                        if scoreEngine.isRecording {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.white)
                        } else {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 13, height: 13)
                        }
                    }
                    .shadow(color: scoreEngine.isRecording ? Color.red.opacity(0.6) : .clear, radius: 6)
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
