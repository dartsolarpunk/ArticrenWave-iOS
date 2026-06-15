// SheetsViews.swift — Export, Layout Picker, Tempo sheets
import SwiftUI

// MARK: - Export Sheet
struct ExportSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(ScoreEngine.self) private var scoreEngine
    @Environment(AudioEngine.self) private var audioEngine
    @Environment(ProjectManager.self) private var projectManager
    @Environment(\.dismiss) var dismiss

    @State private var selectedFormat: AudioExportFormat = .wav
    @State private var exportURL: URL? = nil
    @State private var showShareSheet = false
    @State private var statusMessage: String = ""

    var body: some View {
        NavigationView {
            ZStack {
                appState.theme.background.ignoresSafeArea()

                VStack(spacing: 20) {
                    // Format picker
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Audio Export", systemImage: "waveform.path.ecg")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(appState.theme.accent)

                        ForEach(AudioExportFormat.allCases, id: \.self) { format in
                            RadioRow(label: format.rawValue, isSelected: selectedFormat == format) {
                                selectedFormat = format
                            }
                        }
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    // Export audio button
                    if audioEngine.isExporting {
                        VStack(spacing: 8) {
                            ProgressView(value: audioEngine.exportProgress)
                                .tint(appState.theme.accent)
                            Text("Rendering audio…")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    } else {
                        ActionButton(label: "Export Audio (\(selectedFormat.rawValue))", icon: "music.quarternote.3", color: appState.theme.accent) {
                            statusMessage = "Audio export coming soon — score saved locally."
                        }
                    }

                    // MIDI export
                    ActionButton(label: "Export MIDI", icon: "pianokeys", color: appState.theme.secondary) {
                        ProjectManager.shared.exportMIDI(from: scoreEngine.document) { url in
                            if let url = url { exportURL = url; showShareSheet = true }
                        }
                    }

                    // PDF export
                    ActionButton(label: "Export PDF Score", icon: "doc.richtext", color: Color.white.opacity(0.6)) {
                        Task { @MainActor in
                            ProjectManager.shared.exportPDF(document: scoreEngine.document) { url in
                                if let url = url { exportURL = url; showShareSheet = true }
                            }
                        }
                    }

                    // Save project
                    ActionButton(label: "Save Project (.awscore)", icon: "folder.badge.plus", color: Color.white.opacity(0.5)) {
                        ProjectManager.shared.save(document: scoreEngine.document, toiCloud: false) { success, url in
                            statusMessage = success ? "Saved!" : "Save failed."
                        }
                    }

                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.system(size: 12))
                            .foregroundColor(appState.theme.accent)
                    }

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(appState.theme.accent)
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportURL {
                ShareSheet(activityItems: [url])
            }
        }
    }
}

struct RadioRow: View {
    @Environment(AppState.self) private var appState
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(isSelected ? appState.theme.accent : .white.opacity(0.35))
                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
            }
        }
    }
}

struct ActionButton: View {
    let label: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(color.opacity(0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(color.opacity(0.5), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Layout Picker Sheet
struct LayoutPickerSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(ScoreEngine.self) private var scoreEngine
    @Environment(\.dismiss) var dismiss

    @State private var showInstrumentPicker = false

    var body: some View {
        NavigationView {
            ZStack {
                appState.theme.background.ignoresSafeArea()

                VStack(spacing: 16) {
                    // Presets
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Layout Presets", systemImage: "music.note.list")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(appState.theme.accent)

                        ForEach(ScoreLayoutPreset.allCases, id: \.self) { preset in
                            Button {
                                scoreEngine.applyLayoutPreset(preset)
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(preset.rawValue)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.white.opacity(0.85))
                                        Text("\(preset.instruments.count) part(s)")
                                            .font(.system(size: 10))
                                            .foregroundColor(.white.opacity(0.35))
                                    }
                                    Spacer()
                                    if scoreEngine.layoutPreset == preset {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(appState.theme.accent)
                                    }
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(scoreEngine.layoutPreset == preset ? appState.theme.accent.opacity(0.1) : Color.white.opacity(0.04))
                                )
                            }
                        }
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    // Add individual part
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Add Instrument", systemImage: "plus.circle")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(appState.theme.accent)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(InstrumentFamily.allCases, id: \.self) { instr in
                                    Button(instr.rawValue) {
                                        scoreEngine.addPart(instrument: instr)
                                        dismiss()
                                    }
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.75))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule().fill(Color.white.opacity(0.07))
                                            .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
                                    )
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Score Layout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(appState.theme.accent)
                }
            }
        }
    }
}

// MARK: - Tempo Sheet
struct TempoSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(ScoreEngine.self) private var scoreEngine
    @Environment(\.dismiss) var dismiss

    @State private var tempo: Double = 80

    var body: some View {
        NavigationView {
            ZStack {
                appState.theme.background.ignoresSafeArea()

                VStack(spacing: 24) {
                    // BPM display
                    VStack(spacing: 4) {
                        Text("\(Int(tempo))")
                            .font(.system(size: 64, weight: .thin, design: .monospaced))
                            .foregroundColor(.white)
                        Text("BPM")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.4))
                            .tracking(3)

                        Text(tempoLabel(Int(tempo)))
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(appState.theme.accent)
                    }
                    .padding(.top, 20)

                    Slider(value: $tempo, in: 40...208, step: 1)
                        .tint(appState.theme.accent)
                        .padding(.horizontal, 24)

                    // Common tempos
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach([40,60,72,80,96,108,120,144,168], id: \.self) { bpm in
                            Button {
                                tempo = Double(bpm)
                            } label: {
                                VStack(spacing: 2) {
                                    Text("\(bpm)")
                                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                    Text(tempoLabel(bpm))
                                        .font(.system(size: 9))
                                }
                                .foregroundColor(Int(tempo) == bpm ? appState.theme.accent : .white.opacity(0.6))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Int(tempo) == bpm ? appState.theme.accent.opacity(0.12) : Color.white.opacity(0.04))
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    Spacer()
                }
            }
            .navigationTitle("Tempo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Set") {
                        scoreEngine.document.tempo = Int(tempo)
                        dismiss()
                    }
                    .foregroundColor(appState.theme.accent)
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear { tempo = Double(scoreEngine.document.tempo) }
    }

    func tempoLabel(_ bpm: Int) -> String {
        switch bpm {
        case ..<60: return "Largo"
        case 60..<66: return "Larghetto"
        case 66..<76: return "Adagio"
        case 76..<108: return "Andante"
        case 108..<120: return "Moderato"
        case 120..<156: return "Allegro"
        case 156..<176: return "Vivace"
        default: return "Presto"
        }
    }
}

// MARK: - UIKit ShareSheet wrapper
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}
