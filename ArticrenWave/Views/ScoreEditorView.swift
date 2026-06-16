// ScoreEditorView.swift — Professional score canvas with drag, zoom, pan, cursor
import SwiftUI

// MARK: - Score Editor Container
struct ScoreEditorView: View {
    @Environment(AppState.self)    private var appState
    @Environment(ScoreEngine.self) private var scoreEngine
    @State private var zoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize  = .zero

    var body: some View {
        VStack(spacing: 0) {
            // Pinch + pan canvas
            GeometryReader { geo in
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    ScorePageView()
                        .scaleEffect(zoomScale)
                        .frame(
                            width:  max(geo.size.width,  800 * zoomScale),
                            height: max(geo.size.height, 1100 * zoomScale)
                        )
                }
                .background(Color(hex: "#080910"))
                .gesture(
                    MagnificationGesture()
                        .onChanged { v in
                            zoomScale = max(0.4, min(3.0, v))
                        }
                )
            }
        }
    }
}

// MARK: - Score Page (title header + staves)
struct ScorePageView: View {
    @Environment(AppState.self)    private var appState
    @Environment(ScoreEngine.self) private var scoreEngine
    private var audio: AWAudioPlayer { AWAudioPlayer.shared }
    @State private var isEditingTitle    = false
    @State private var isEditingComposer = false
    @State private var composerName: String = ""
    @State private var scoreDate: String    = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Score header ──────────────────────────────────────
            VStack(spacing: 4) {
                // Title (tappable to edit)
                if isEditingTitle {
                    TextField("Score title", text: Binding(
                        get: { scoreEngine.document.title },
                        set: { scoreEngine.document.title = $0 }
                    ))
                    .font(.system(size: 26, weight: .bold, design: .serif))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.plain)
                    .onSubmit { isEditingTitle = false }
                    .autocorrectionDisabled()
                } else {
                    Text(scoreEngine.document.title)
                        .font(.system(size: 26, weight: .bold, design: .serif))
                        .foregroundColor(.white)
                        .onTapGesture { isEditingTitle = true }
                }

                // Composer
                if isEditingComposer {
                    TextField("Composer name", text: $composerName)
                        .font(.system(size: 13, design: .serif))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.plain)
                        .onSubmit { isEditingComposer = false }
                } else {
                    Text(composerName.isEmpty ? "Tap to add composer" : composerName)
                        .font(.system(size: 13, design: .serif))
                        .foregroundColor(composerName.isEmpty ? .white.opacity(0.2) : .white.opacity(0.6))
                        .onTapGesture { isEditingComposer = true }
                }

                // Date
                Text(scoreDate.isEmpty ? formattedDate : scoreDate)
                    .font(.system(size: 11, design: .serif))
                    .foregroundColor(.white.opacity(0.3))
                    .onTapGesture {
                        scoreDate = scoreDate.isEmpty ? formattedDate : ""
                    }

                // Tempo marking
                HStack(spacing: 4) {
                    QuarterNoteSymbol(color: .white.opacity(0.6), size: 14)
                        .frame(width: 10, height: 18)
                    Text("= \(scoreEngine.document.tempo)")
                        .font(.system(size: 12, design: .serif))
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding(.top, 4)

                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(height: 1)
                    .padding(.top, 12)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 16)

            // ── Staves ────────────────────────────────────────────
            if scoreEngine.document.parts.isEmpty {
                Text("Tap Layout to add a staff")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.white.opacity(0.25))
                    .padding(40)
            } else {
                ForEach(Array(scoreEngine.document.parts.enumerated()), id: \.element.id) { pi, part in
                    ZStack {
                        DraggableStaffRow(partIndex: pi, part: part)
                        // Playback cursor overlay
                        if audio.isPlaying || audio.isPaused {
                            PlaybackCursorOverlay(
                                progress: audio.progress,
                                measureCount: part.measures.count
                            )
                        }
                    }
                    .padding(.bottom, 60)
                }
            }

            Spacer().frame(height: 48)
        }
        .padding(.horizontal, 16)
        .onAppear {
            composerName = UserDefaults.standard.string(forKey: "aw_composer_name") ?? ""
        }
        .onChange(of: composerName) { _, v in
            UserDefaults.standard.set(v, forKey: "aw_composer_name")
        }
    }

    var formattedDate: String {
        let f = DateFormatter()
        f.dateStyle = .long
        return f.string(from: Date())
    }
}

// MARK: - Playback cursor overlay
struct PlaybackCursorOverlay: View {
    @Environment(AppState.self) private var appState
    let progress: Double
    let measureCount: Int

    var body: some View {
        GeometryReader { geo in
            let x = CGFloat(progress) * geo.size.width
            Rectangle()
                .fill(appState.theme.accent.opacity(0.6))
                .frame(width: 2)
                .offset(x: x)
                .shadow(color: appState.theme.accent, radius: 4)
                .animation(.linear(duration: 0.08), value: progress)
        }
    }
}

// MARK: - Draggable Staff Row
struct DraggableStaffRow: View {
    @Environment(AppState.self)    private var appState
    @Environment(ScoreEngine.self) private var scoreEngine

    let partIndex: Int
    let part: Part

    let lineSpacing: CGFloat  = 9
    let measureWidth: CGFloat = 220

    var staffH: CGFloat { lineSpacing * 4 }
    var rowH:   CGFloat { staffH + 70 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(part.label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    SafeClefView(clef: part.clef, lineSpacing: lineSpacing)
                        .frame(width: 48, height: rowH)

                    ForEach(Array(part.measures.enumerated()), id: \.element.id) { mi, measure in
                        DraggableMeasureView(
                            measure:      measure,
                            partIndex:    partIndex,
                            measureIndex: mi,
                            clef:         part.clef,
                            lineSpacing:  lineSpacing,
                            width:        measureWidth,
                            rowH:         rowH
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Draggable Measure View
struct DraggableMeasureView: View {
    @Environment(AppState.self)    private var appState
    @Environment(ScoreEngine.self) private var scoreEngine

    let measure:      Measure
    let partIndex:    Int
    let measureIndex: Int
    let clef:         Clef
    let lineSpacing:  CGFloat
    let width:        CGFloat
    let rowH:         CGFloat

    var staffH: CGFloat { lineSpacing * 4 }

    // Drag state
    @State private var draggingID:     UUID?   = nil
    @State private var dragOffset:     CGSize  = .zero
    @State private var ghostPitch:     Pitch?  = nil
    @State private var ghostPos:       CGPoint? = nil
    // Lasso selection
    @State private var lassoStart:    CGPoint? = nil
    @State private var lassoEnd:      CGPoint? = nil
    @State private var lassoSelected: Set<UUID> = []

    func xFor(_ beat: Double) -> CGFloat {
        16 + CGFloat(beat / 4.0) * (width - 32)
    }

    func yFor(_ staffPos: Int) -> CGFloat {
        rowH / 2 - CGFloat(staffPos - clef.middleCOffset) * (lineSpacing / 2)
    }

    func staffPosAt(y: CGFloat) -> Int {
        let halfStep = lineSpacing / 2
        let offset   = (rowH / 2 - y) / halfStep
        return Int(offset.rounded()) + clef.middleCOffset
    }

    func pitchAt(staffPos: Int) -> Pitch {
        let whites: [PitchClass] = [.C, .D, .E, .F, .G, .A, .B]
        var oct = 4 + staffPos / 7
        var idx = ((staffPos % 7) + 7) % 7
        return Pitch(pitchClass: whites[idx], octave: max(1, min(7, oct)))
    }

    var lassoRect: CGRect? {
        guard let s = lassoStart, let e = lassoEnd else { return nil }
        return CGRect(
            x: min(s.x, e.x), y: min(s.y, e.y),
            width: abs(e.x - s.x), height: abs(e.y - s.y)
        )
    }

    var body: some View {
        ZStack {
            // Staff lines + bar line
            Canvas { ctx, size in
                let top = (size.height - staffH) / 2
                for i in 0...4 {
                    let y = top + CGFloat(i) * lineSpacing
                    var p = Path(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
                    ctx.stroke(p, with: .color(.white.opacity(0.6)), lineWidth: 0.7)
                }
                var bar = Path()
                bar.move(to: CGPoint(x: size.width - 1, y: top))
                bar.addLine(to: CGPoint(x: size.width - 1, y: top + staffH))
                ctx.stroke(bar, with: .color(.white.opacity(0.45)), lineWidth: 1)
            }

            // Middle C ledger line helper
            Canvas { ctx, size in
                let midCY = yFor(0)
                if midCY < 0 || midCY > size.height { return }
                var p = Path()
                p.move(to: CGPoint(x: xFor(0) - 10, y: midCY))
                p.addLine(to: CGPoint(x: xFor(0) + 10, y: midCY))
                ctx.stroke(p, with: .color(.white.opacity(0.3)), lineWidth: 0.5)
            }

            // Notes and rests
            ForEach(measure.contents) { content in
                switch content {
                case .chord(let chord):
                    let isSelected = lassoSelected.contains(chord.id) || scoreEngine.selectedChordID == chord.id
                    let isDragging = draggingID == chord.id
                    Group {
                        ForEach(chord.notes) { note in
                            let yPos = yFor(note.pitch.staffPosition) + (isDragging ? dragOffset.height : 0)
                            let xPos = xFor(chord.beatPosition)
                            NoteHeadCanvas(
                                duration: chord.duration,
                                xPos: xPos,
                                yPos: yPos,
                                lineSpacing: lineSpacing,
                                isSelected: isSelected,
                                accent: appState.theme.accent
                            )
                            // Accidental
                            if note.accidental != .none {
                                Text(accidentalText(note.accidental))
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.9))
                                    .position(x: xPos - lineSpacing * 1.5, y: yPos)
                            }
                        }
                        // Stem
                        if chord.duration != .whole, let first = chord.notes.first {
                            let sY = yFor(first.pitch.staffPosition) + (isDragging ? dragOffset.height : 0)
                            StemView(xPos: xFor(chord.beatPosition), headY: sY,
                                     tailCount: chord.duration.tailCount,
                                     isSelected: isSelected, accent: appState.theme.accent)
                        }
                    }
                    .contentShape(Rectangle().size(CGSize(width: 40, height: 80))
                        .offset(x: xFor(chord.beatPosition) - 20, y: 0))
                    .gesture(
                        DragGesture(minimumDistance: 6)
                            .onChanged { val in
                                // Allow drag in move mode OR when a note is already selected
                                let isMoveMode = { if case .move = scoreEngine.editMode { return true }; return false }()
                                let isSelected = scoreEngine.selectedChordID == chord.id
                                guard isMoveMode || isSelected else { return }

                                if draggingID == nil {
                                    draggingID = chord.id
                                    scoreEngine.selectedChordID = chord.id
                                    dragOffset = .zero
                                }
                                dragOffset = val.translation

                                // Calculate ghost pitch from drag
                                let originalY = yFor(chord.notes.first?.pitch.staffPosition ?? 0)
                                let newY = originalY + val.translation.height
                                let sp = staffPosAt(y: newY)
                                ghostPitch = pitchAt(staffPos: sp)
                            }
                            .onEnded { val in
                                if draggingID == chord.id, let gp = ghostPitch {
                                    moveChord(chord: chord, newPitch: gp)
                                }
                                draggingID = nil
                                dragOffset  = .zero
                                ghostPitch  = nil
                            }
                    )
                    .onTapGesture {
                        switch scoreEngine.editMode {
                        case .delete:
                            scoreEngine.deleteContent(id: chord.id, partIndex: partIndex)
                        case .move:
                            // Tap in move mode selects the note
                            scoreEngine.selectedChordID = chord.id
                        default:
                            scoreEngine.selectedChordID = chord.id
                        }
                    }

                case .rest(let rest):
                    SafeRestView(
                        symbol: restSymbol(rest.duration),
                        xPos: xFor(rest.beatPosition),
                        yPos: rowH / 2
                    )
                    .onTapGesture {
                        if case .delete = scoreEngine.editMode {
                            scoreEngine.deleteContent(id: rest.id, partIndex: partIndex)
                        }
                    }
                }
            }

            // Ghost pitch label while dragging
            if let gp = ghostPitch, draggingID != nil {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.and.down")
                        .font(.system(size: 8))
                    Text(gp.displayName)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(appState.theme.accent.opacity(0.85))
                .clipShape(Capsule())
                .shadow(color: appState.theme.accent.opacity(0.4), radius: 6)
                .position(x: width / 2, y: 18)
            }

            // Ghost note while hovering to place
            if let gPos = ghostPos, draggingID == nil {
                Circle()
                    .fill(appState.theme.accent.opacity(0.4))
                    .frame(width: lineSpacing * 1.2, height: lineSpacing * 0.85)
                    .position(gPos)
                if let gp = ghostPitch {
                    Text(gp.displayName)
                        .font(.system(size: 9))
                        .foregroundColor(appState.theme.accent)
                        .position(x: gPos.x, y: gPos.y - 14)
                }
            }

            // Lasso selection box
            if let rect = lassoRect {
                Rectangle()
                    .stroke(appState.theme.accent.opacity(0.7), lineWidth: 1)
                    .background(appState.theme.accent.opacity(0.06))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }

            // Tap/drag gesture for placing notes or lasso
            Color.clear.contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { val in
                            if case .select = scoreEngine.editMode {
                                // Lasso
                                if lassoStart == nil { lassoStart = val.startLocation }
                                lassoEnd = val.location
                                updateLassoSelection()
                            } else {
                                ghostPos   = val.location
                                let sp     = staffPosAt(y: val.location.y)
                                ghostPitch = pitchAt(staffPos: sp)
                            }
                        }
                        .onEnded { val in
                            if case .select = scoreEngine.editMode {
                                lassoStart = nil; lassoEnd = nil
                            } else {
                                handleTap(at: val.location)
                                ghostPos   = nil
                                ghostPitch = nil
                            }
                        }
                )
        }
        .frame(width: width, height: rowH)
    }

    func handleTap(at loc: CGPoint) {
        let sp    = staffPosAt(y: loc.y)
        let pitch = pitchAt(staffPos: sp)
        switch scoreEngine.editMode {
        case .addNote:
            scoreEngine.inputNote(pitch: pitch, in: partIndex, measureIndex: measureIndex)
        case .addRest:
            scoreEngine.inputRest(in: partIndex, measureIndex: measureIndex)
        case .select, .move:
            // Deselect when tapping empty area
            scoreEngine.selectedChordID = nil
        default: break
        }
    }

    func moveChord(chord: Chord, newPitch: Pitch) {
        // Calculate the staff position delta from the original first note to new pitch
        guard let firstNote = chord.notes.first else { return }
        let delta = newPitch.staffPosition - firstNote.pitch.staffPosition

        for mi in 0..<scoreEngine.document.parts[partIndex].measures.count {
            for ci in 0..<scoreEngine.document.parts[partIndex].measures[mi].contents.count {
                if case .chord(var c) = scoreEngine.document.parts[partIndex].measures[mi].contents[ci],
                   c.id == chord.id {
                    // Move each note by the same interval
                    c.notes = c.notes.map { note in
                        var n = note
                        let newSP = note.pitch.staffPosition + delta
                        n.pitch = pitchFromStaffPos(newSP)
                        return n
                    }
                    scoreEngine.document.parts[partIndex].measures[mi].contents[ci] = .chord(c)
                    scoreEngine.selectedChordID = chord.id
                    return
                }
            }
        }
    }

    func pitchFromStaffPos(_ staffPos: Int) -> Pitch {
        let whites: [PitchClass] = [.C, .D, .E, .F, .G, .A, .B]
        // staffPos 0 = C4 (middle C = MIDI 60)
        // positive staffPos = higher pitch, negative = lower
        // Each octave = 7 diatonic steps
        let absPos  = staffPos + 1000 * 7     // large positive offset to avoid negative mod
        let octave  = (staffPos + 1000*7) / 7 - 1000 + 4  // centre on C4
        let idx     = ((staffPos % 7) + 7) % 7
        return Pitch(
            pitchClass: whites[idx],
            octave:     max(1, min(7, octave))
        )
    }

    func updateLassoSelection() {
        guard let rect = lassoRect else { return }
        var selected = Set<UUID>()
        for content in measure.contents {
            if case .chord(let c) = content {
                let x = xFor(c.beatPosition)
                let y = yFor(c.notes.first?.pitch.staffPosition ?? 0)
                if rect.contains(CGPoint(x: x, y: y)) {
                    selected.insert(c.id)
                }
            }
        }
        lassoSelected = selected
    }

    func restSymbol(_ d: RestDuration) -> String {
        switch d { case .whole: return "𝄻"; case .half: return "𝄼";
                   case .quarter: return "𝄽"; case .eighth: return "𝄾"; case .sixteenth: return "𝄿" }
    }
    func accidentalText(_ a: Accidental) -> String {
        switch a { case .sharp: return "♯"; case .flat: return "♭"; case .natural: return "♮"; case .none: return "" }
    }
}

// MARK: - Note Head (Canvas-based)
struct NoteHeadCanvas: View {
    @Environment(ScoreEngine.self) private var scoreEngine
    let duration:    NoteDuration
    let xPos:        CGFloat
    let yPos:        CGFloat
    let lineSpacing: CGFloat
    let isSelected:  Bool
    let accent:      Color

    var showMoveHint: Bool {
        if case .move = scoreEngine.editMode { return true }
        return false
    }

    var hw: CGFloat { lineSpacing * 1.15 }
    var hh: CGFloat { lineSpacing * 0.82 }
    var fill: Color { isSelected ? accent : .white }

    var body: some View {
        ZStack {
            Ellipse()
                .fill(duration.isFilled ? fill : .clear)
                .overlay(Ellipse().stroke(fill, lineWidth: 1.2))
                .frame(width: hw, height: hh)
                .rotationEffect(.degrees(-12))

            // Move mode indicator — pulsing ring on selected note
            if isSelected && showMoveHint {
                Ellipse()
                    .stroke(accent.opacity(0.6), lineWidth: 1.5)
                    .frame(width: hw + 6, height: hh + 4)
                    .rotationEffect(.degrees(-12))
            }
        }
        .position(x: xPos, y: yPos)
    }
}

// MARK: - Stem View
struct StemView: View {
    let xPos:       CGFloat
    let headY:      CGFloat
    let tailCount:  Int
    let isSelected: Bool
    let accent:     Color

    var stemColor: Color { isSelected ? accent : .white }

    var body: some View {
        let stemTop = headY - 28
        ZStack {
            Path { p in
                p.move(to: CGPoint(x: xPos + 5, y: headY - 4))
                p.addLine(to: CGPoint(x: xPos + 5, y: stemTop))
            }
            .stroke(stemColor, lineWidth: 1.2)

            ForEach(0..<tailCount, id: \.self) { t in
                Path { p in
                    let y0 = stemTop + CGFloat(t) * 6
                    p.move(to: CGPoint(x: xPos + 5, y: y0))
                    p.addCurve(
                        to:       CGPoint(x: xPos + 16, y: y0 + 13),
                        control1: CGPoint(x: xPos + 12, y: y0 + 2),
                        control2: CGPoint(x: xPos + 17, y: y0 + 7)
                    )
                }
                .stroke(stemColor, style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            }
        }
    }
}

// MARK: - Safe Rest View
struct SafeRestView: View {
    let symbol: String
    let xPos:   CGFloat
    let yPos:   CGFloat
    var body: some View {
        Text(symbol).font(.system(size: 18)).foregroundColor(.white.opacity(0.75))
            .position(x: xPos, y: yPos)
    }
}

// MARK: - Clef View
struct SafeClefView: View {
    let clef:        Clef
    let lineSpacing: CGFloat
    var staffH: CGFloat { lineSpacing * 4 }
    var body: some View {
        Canvas { ctx, size in
            let top = (size.height - staffH) / 2
            for i in 0...4 {
                let y = top + CGFloat(i) * lineSpacing
                var p = Path(); p.move(to: CGPoint(x: 4, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(p, with: .color(.white.opacity(0.65)), lineWidth: 0.7)
            }
            let sym = clef == .treble ? "𝄞" : "𝄢"
            let sz: CGFloat = clef == .treble ? 36 : 26
            ctx.draw(
                Text(sym).font(.system(size: sz)).foregroundColor(.white),
                at: CGPoint(x: size.width/2, y: size.height/2), anchor: .center
            )
        }
    }
}
