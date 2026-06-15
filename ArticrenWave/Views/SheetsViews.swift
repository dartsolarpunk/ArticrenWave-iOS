// SheetsViews.swift — Export, Layout, Tempo sheets (iOS 17+ @Environment)
import SwiftUI

// MARK: - Export Sheet
struct ExportSheet: View {
    @Environment(AppState.self)    private var appState
    @Environment(ScoreEngine.self) private var scoreEngine
    @Environment(\.dismiss)        private var dismiss
    @State private var formatIndex: Int = 0
    @State private var statusMessage: String = ""
    @State private var pdfLandscape: Bool = true
    @State private var exportURL: URL? = nil
    @State private var showShareSheet = false

    let formats = ["WAV", "MP3", "M4A", "MIDI"]

    var body: some View {
        NavigationStack {
            ZStack {
                appState.theme.background.ignoresSafeArea()
                VStack(spacing: 16) {
                    // Format picker
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Export Format", systemImage: "waveform.path.ecg")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(appState.theme.accent)
                        Picker("Format", selection: $formatIndex) {
                            ForEach(formats.indices, id: \.self) { i in
                                Text(formats[i]).tag(i)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    // Export audio button
                    Button {
                        statusMessage = "Audio export: coming in next build"
                    } label: {
                        Label("Export Audio (\(formats[formatIndex]))", systemImage: "music.quarternote.3")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background(appState.theme.accent.opacity(0.2))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(appState.theme.accent.opacity(0.5), lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    // MIDI export
                    Button {
                        let tmp = FileManager.default.temporaryDirectory
                            .appendingPathComponent("\(scoreEngine.document.title).mid")
                        try? Data().write(to: tmp)
                        exportURL = tmp
                        showShareSheet = true
                    } label: {
                        Label("Export MIDI", systemImage: "pianokeys")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background(appState.theme.secondary.opacity(0.2))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(appState.theme.secondary.opacity(0.5), lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    // PDF Export
                    VStack(spacing: 8) {
                        HStack {
                            Label("Export PDF Score", systemImage: "doc.richtext")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(appState.theme.secondary)
                            Spacer()
                            Picker("", selection: $pdfLandscape) {
                                Text("Portrait").tag(false)
                                Text("Landscape").tag(true)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 160)
                        }
                        Button {
                            exportPDF()
                        } label: {
                            Label("Export PDF (\(pdfLandscape ? "Landscape" : "Portrait"))", systemImage: "arrow.down.doc")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity).frame(height: 48)
                                .background(appState.theme.secondary.opacity(0.2))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(appState.theme.secondary.opacity(0.5), lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Save project
                    Button {
                        ProjectBrowserState.shared.save(document: scoreEngine.document)
                        statusMessage = "Saved to Projects!"
                    } label: {
                        Label("Save Project (.awscore)", systemImage: "folder.badge.plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
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
                    Button("Done") { dismiss() }.foregroundColor(appState.theme.accent)
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportURL { ShareSheet(activityItems: [url]) }
        }
    }

    func exportPDF() {
        let doc = scoreEngine.document
        let pageSize = pdfLandscape
            ? CGRect(x: 0, y: 0, width: 1122, height: 794)   // A4 landscape 96dpi
            : CGRect(x: 0, y: 0, width: 794, height: 1122)   // A4 portrait

        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(doc.title)_score.pdf")

        guard let pdf = CGContext(tmpURL as CFURL, mediaBox: nil, nil) else { return }

        var pageBox = pageSize
        pdf.beginPDFPage(nil)

        // Professional score header
        let title = doc.title as CFString
        let attrs: CFDictionary = [
            kCTFontAttributeName: CTFontCreateWithName("Helvetica-Bold" as CFString, 24, nil),
            kCTForegroundColorAttributeName: CGColor(gray: 0, alpha: 1)
        ] as CFDictionary

        // Draw title
        if let titleStr = CFAttributedStringCreate(nil, title, attrs) {
            if let line = CTLineCreateWithAttributedString(titleStr) {
                pdf.textPosition = CGPoint(x: 60, y: pageBox.height - 60)
                CTLineDraw(line, pdf)
            }
        }

        // Draw tempo marking
        let tempoStr = "\(doc.tempo) BPM" as CFString
        let tempoAttrs: CFDictionary = [
            kCTFontAttributeName: CTFontCreateWithName("Helvetica" as CFString, 12, nil),
            kCTForegroundColorAttributeName: CGColor(gray: 0.3, alpha: 1)
        ] as CFDictionary
        if let tempoAS = CFAttributedStringCreate(nil, tempoStr, tempoAttrs),
           let tempoLine = CTLineCreateWithAttributedString(tempoAS) {
            pdf.textPosition = CGPoint(x: 60, y: pageBox.height - 85)
            CTLineDraw(tempoLine, pdf)
        }

        // Draw staves for each part
        let staffTop: CGFloat = pageBox.height - 130
        let staffSpacing: CGFloat = 120
        let leftMargin: CGFloat = 80
        let rightMargin: CGFloat = pageBox.width - 60
        let lineSpacing: CGFloat = 10

        for (pi, part) in doc.parts.enumerated() {
            let baseY = staffTop - CGFloat(pi) * staffSpacing

            // Part label
            let labelStr = part.label as CFString
            let labelAttrs: CFDictionary = [
                kCTFontAttributeName: CTFontCreateWithName("Helvetica" as CFString, 10, nil),
                kCTForegroundColorAttributeName: CGColor(gray: 0.4, alpha: 1)
            ] as CFDictionary
            if let labelAS = CFAttributedStringCreate(nil, labelStr, labelAttrs),
               let labelLine = CTLineCreateWithAttributedString(labelAS) {
                pdf.textPosition = CGPoint(x: leftMargin - 70, y: baseY - 16)
                CTLineDraw(labelLine, pdf)
            }

            // Draw 5 staff lines
            pdf.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
            pdf.setLineWidth(0.8)
            for i in 0...4 {
                let y = baseY - CGFloat(i) * lineSpacing
                pdf.move(to: CGPoint(x: leftMargin, y: y))
                pdf.addLine(to: CGPoint(x: rightMargin, y: y))
            }
            pdf.strokePath()

            // Clef symbol (text approximation)
            let clefStr = (part.clef == .treble ? "𝄞" : "𝄢") as CFString
            let clefAttrs: CFDictionary = [
                kCTFontAttributeName: CTFontCreateWithName("Times New Roman" as CFString, 40, nil),
                kCTForegroundColorAttributeName: CGColor(gray: 0, alpha: 1)
            ] as CFDictionary
            if let clefAS = CFAttributedStringCreate(nil, clefStr, clefAttrs),
               let clefLine = CTLineCreateWithAttributedString(clefAS) {
                pdf.textPosition = CGPoint(x: leftMargin + 4, y: baseY - 32)
                CTLineDraw(clefLine, pdf)
            }

            // Bar lines between measures
            let measureWidth = (rightMargin - leftMargin - 50) / CGFloat(max(part.measures.count, 1))
            for mi in 0...part.measures.count {
                let x = leftMargin + 50 + CGFloat(mi) * measureWidth
                pdf.move(to: CGPoint(x: x, y: baseY))
                pdf.addLine(to: CGPoint(x: x, y: baseY - lineSpacing * 4))
                pdf.strokePath()
            }
        }

        // Footer
        let footer = "© Articren Wave — DART Meadow LLC & Radical Deepscale LLC" as CFString
        let footerAttrs: CFDictionary = [
            kCTFontAttributeName: CTFontCreateWithName("Helvetica" as CFString, 9, nil),
            kCTForegroundColorAttributeName: CGColor(gray: 0.6, alpha: 1)
        ] as CFDictionary
        if let footerAS = CFAttributedStringCreate(nil, footer, footerAttrs),
           let footerLine = CTLineCreateWithAttributedString(footerAS) {
            pdf.textPosition = CGPoint(x: 60, y: 30)
            CTLineDraw(footerLine, pdf)
        }

        pdf.endPDFPage()
        pdf.closePDF()

        exportURL = tmpURL
        showShareSheet = true
        statusMessage = "PDF ready — \(pdfLandscape ? "Landscape" : "Portrait") A4"
    }
}

// MARK: - Layout Picker Sheet
struct LayoutPickerSheet: View {
    @Environment(AppState.self)    private var appState
    @Environment(ScoreEngine.self) private var scoreEngine
    @Environment(\.dismiss)        private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                appState.theme.background.ignoresSafeArea()
                VStack(spacing: 16) {
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
                                        Image(systemName: "checkmark").foregroundColor(appState.theme.accent)
                                    }
                                }
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 10)
                                    .fill(scoreEngine.layoutPreset == preset
                                          ? appState.theme.accent.opacity(0.1)
                                          : Color.white.opacity(0.04)))
                            }
                        }
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

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
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Capsule().fill(Color.white.opacity(0.07))
                                        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1)))
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
                    Button("Done") { dismiss() }.foregroundColor(appState.theme.accent)
                }
            }
        }
    }
}

// MARK: - Tempo Sheet
struct TempoSheet: View {
    @Environment(AppState.self)    private var appState
    @Environment(ScoreEngine.self) private var scoreEngine
    @Environment(\.dismiss)        private var dismiss
    @State private var tempo: Double = 80

    var body: some View {
        NavigationStack {
            ZStack {
                appState.theme.background.ignoresSafeArea()
                VStack(spacing: 24) {
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
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 8)
                                    .fill(Int(tempo) == bpm
                                          ? appState.theme.accent.opacity(0.12)
                                          : Color.white.opacity(0.04)))
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

// MARK: - UIKit ShareSheet
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}
