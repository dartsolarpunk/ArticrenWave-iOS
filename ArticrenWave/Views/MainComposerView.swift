// MainComposerView.swift — Score editor + piano drawer layout
import SwiftUI

struct MainComposerView: View {
    @Environment(AppState.self) private var appState
    @Environment(ScoreEngine.self) private var scoreEngine
    @Environment(AudioEngine.self) private var audioEngine

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // ── Score area fills available space ──
                VStack(spacing: 0) {
                    ComposerToolbar()
                    ScoreEditorView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // ── Piano drawer slides up from bottom ──
                if appState.isPianoDrawerOpen {
                    PianoDrawerView()
                        .frame(height: pianoDrawerHeight(geo: geo))
                        .transition(.move(edge: .bottom))
                        .zIndex(50)
                }

                // ── Drawer pull tab ──
                DrawerPullTab()
                    .zIndex(51)
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.82), value: appState.isPianoDrawerOpen)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    func pianoDrawerHeight(geo: GeometryProxy) -> CGFloat {
        let isLandscape = geo.size.width > geo.size.height
        return isLandscape ? geo.size.height * 0.5 : geo.size.height * 0.38
    }
}

// MARK: - Drawer Pull Tab
struct DrawerPullTab: View {
    @Environment(AppState.self) private var appState
    @Environment(AudioEngine.self) private var audioEngine

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                    appState.isPianoDrawerOpen.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: appState.isPianoDrawerOpen ? "chevron.down" : "chevron.up")
                        .font(.system(size: 11, weight: .semibold))
                    Text(appState.isPianoDrawerOpen ? "Hide Piano" : "Piano")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    if audioEngine.currentInstrumentName != AudioInstrument.grandPiano.rawValue {
                        Text("· \(audioEngine.currentInstrumentName)")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                .foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.1))
                        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                )
            }
            .padding(.bottom, 8)
        }
    }
}

// MARK: - Composer Toolbar
struct ComposerToolbar: View {
    @Environment(AppState.self) private var appState
    @Environment(ScoreEngine.self) private var scoreEngine
    @Environment(ProjectManager.self) private var projectManager
    @Environment(AudioEngine.self) private var audioEngine

    @State private var showExportSheet = false
    @State private var showLayoutPicker = false
    @State private var showInstrumentPicker = false
    @State private var showTempoSheet = false

    var body: some View {
        HStack(spacing: 0) {
            // Menu button
            Button {
                withAnimation { appState.isMainMenuOpen = true }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(width: 44, height: 44)
            }

            // Title
            Text(scoreEngine.document.title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 4)

            // Toolbar actions
            HStack(spacing: 4) {
                ToolbarButton(icon: "metronome", label: "Tempo") {
                    showTempoSheet = true
                }
                ToolbarButton(icon: "pianokeys", label: "Layout") {
                    showLayoutPicker = true
                }
                ToolbarButton(icon: "square.and.arrow.up", label: "Export") {
                    showExportSheet = true
                }
                // Record
                Button {
                    if scoreEngine.isRecording {
                        scoreEngine.stopRecording()
                    } else {
                        scoreEngine.startRecording()
                    }
                } label: {
                    Circle()
                        .fill(scoreEngine.isRecording ? Color.red : Color.white.opacity(0.12))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle()
                                .fill(Color.red.opacity(scoreEngine.isRecording ? 0 : 1))
                                .frame(width: 10, height: 10)
                        )
                }
                .padding(.horizontal, 6)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 50)
        .background(appState.themeBackground.opacity(0.97))
        .overlay(Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1), alignment: .bottom)
        // Sheets — must pass environmentObjects explicitly through sheet presentation
        .sheet(isPresented: $showExportSheet) {
            ExportSheet()
        }
        .sheet(isPresented: $showLayoutPicker) {
            LayoutPickerSheet()
        }
        .sheet(isPresented: $showTempoSheet) {
            TempoSheet()
        }
    }
}

struct ToolbarButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white.opacity(0.75))
                .frame(width: 36, height: 36)
        }
    }
}
