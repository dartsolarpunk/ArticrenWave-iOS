// ScoreEditorView.swift — Grand staff score canvas with note editing
import SwiftUI

struct ScoreEditorView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var scoreEngine: ScoreEngine

    @State private var scrollOffset: CGFloat = 0
    @State private var scale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 0) {
            // Note/edit palette
            NotePalette()
                .padding(.horizontal, 8)
                .padding(.vertical, 6)

            // Validation error banner
            if let err = scoreEngine.validationError {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundColor(appState.theme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(appState.theme.accent.opacity(0.1))
                    .onTapGesture { scoreEngine.validationError = nil }
            }

            // Score scroll canvas
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                ScoreCanvas()
                    .scaleEffect(scale)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { scale = max(0.5, min(2.5, $0)) }
                    )
            }
            .background(appState.theme.background)
        }
    }
}

// MARK: - Score Canvas (renders all parts/measures)
struct ScoreCanvas: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var scoreEngine: ScoreEngine

    let staffLineSpacing: CGFloat = 8     // px between staff lines
    let measureWidth: CGFloat = 180
    let leftMargin: CGFloat = 60
    let partSpacing: CGFloat = 80

    var body: some View {
        VStack(alignment: .leading, spacing: partSpacing) {
            ForEach(Array(scoreEngine.document.parts.enumerated()), id: \.element.id) { pi, part in
                StaffRow(partIndex: pi, part: part)
            }
        }
        .padding(24)
    }
}

// MARK: - Staff Row (one part: clef + all measures)
struct StaffRow: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var scoreEngine: ScoreEngine

    let partIndex: Int
    let part: Part
    let staffLineSpacing: CGFloat = 9
    let measureWidth: CGFloat = 200

    var staffHeight: CGFloat { staffLineSpacing * 4 } // 4 gaps = 5 lines

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Instrument label
            Text(part.label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.45))
                .padding(.leading, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    // Clef symbol
                    ClefView(clef: part.clef, lineSpacing: staffLineSpacing)
                        .frame(width: 44)

                    // Measures
                    ForEach(Array(part.measures.enumerated()), id: \.element.id) { mi, measure in
                        MeasureView(
                            measure: measure,
                            partIndex: partIndex,
                            measureIndex: mi,
                            clef: part.clef,
                            lineSpacing: staffLineSpacing,
                            width: measureWidth
                        )
                    }
                }
                .frame(height: staffHeight + 60) // extra for ledger lines
            }
        }
    }
}

// MARK: - Clef View (vector)
struct ClefView: View {
    let clef: Clef
    let lineSpacing: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let lines = 5
            let top = size.height / 2 - CGFloat(lines - 1) * lineSpacing / 2

            // Draw 5 staff lines
            for i in 0..<lines {
                let y = top + CGFloat(i) * lineSpacing
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(path, with: .color(.white.opacity(0.7)), lineWidth: 0.7)
            }

            // Draw clef symbol as text (system glyphs approximate)
            let clefSymbol = clef == .treble ? "𝄞" : "𝄢"
            let fontSize: CGFloat = clef == .treble ? 38 : 28
            ctx.draw(
                Text(clefSymbol)
                    .font(.system(size: fontSize, weight: .regular))
                    .foregroundColor(.white),
                at: CGPoint(x: size.width / 2, y: size.height / 2),
                anchor: .center
            )
        }
    }
}

// MARK: - Measure View
struct MeasureView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var scoreEngine: ScoreEngine

    let measure: Measure
    let partIndex: Int
    let measureIndex: Int
    let clef: Clef
    let lineSpacing: CGFloat
    let width: CGFloat

    var staffHeight: CGFloat { lineSpacing * 4 }

    var body: some View {
        ZStack {
            // Staff lines + bar lines
            MeasureStaffLines(lineSpacing: lineSpacing, width: width, staffHeight: staffHeight)

            // Notes and rests
            MeasureContents(
                measure: measure,
                partIndex: partIndex,
                measureIndex: measureIndex,
                clef: clef,
                lineSpacing: lineSpacing,
                width: width,
                staffHeight: staffHeight
            )

            // Tap to add note (if in add mode)
            MeasureTapZone(
                partIndex: partIndex,
                measureIndex: measureIndex,
                clef: clef,
                lineSpacing: lineSpacing,
                staffHeight: staffHeight
            )
        }
        .frame(width: width, height: staffHeight + 60)
    }
}

struct MeasureStaffLines: View {
    let lineSpacing: CGFloat
    let width: CGFloat
    let staffHeight: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let top = (size.height - staffHeight) / 2
            for i in 0...4 {
                let y = top + CGFloat(i) * lineSpacing
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(path, with: .color(.white.opacity(0.65)), lineWidth: 0.7)
            }
            // Bar line at right
            var bar = Path()
            bar.move(to: CGPoint(x: size.width - 1, y: top))
            bar.addLine(to: CGPoint(x: size.width - 1, y: top + staffHeight))
            ctx.stroke(bar, with: .color(.white.opacity(0.5)), lineWidth: 1)
        }
        .frame(width: width, height: staffHeight + 60)
    }
}

// MARK: - Measure Contents (notes, rests, ties)
struct MeasureContents: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var scoreEngine: ScoreEngine

    let measure: Measure
    let partIndex: Int
    let measureIndex: Int
    let clef: Clef
    let lineSpacing: CGFloat
    let width: CGFloat
    let staffHeight: CGFloat

    // X position for a beat
    func xFor(beat: Double) -> CGFloat {
        let usable = width - 32
        return 16 + CGFloat(beat / 4.0) * usable
    }

    // Y position for staff position offset from middle C
    func yFor(staffPos: Int) -> CGFloat {
        let center = (staffHeight + 60) / 2
        // Each step is lineSpacing/2 (half-step = one diatonic note)
        let halfStep = lineSpacing / 2
        return center - CGFloat(staffPos - clef.middleCOffset) * halfStep
    }

    var body: some View {
        ZStack {
            ForEach(measure.contents) { content in
                switch content {
                case .chord(let chord):
                    ChordView(
                        chord: chord,
                        xPos: xFor(beat: chord.beatPosition),
                        yFor: yFor,
                        lineSpacing: lineSpacing,
                        partIndex: partIndex,
                        measureIndex: measureIndex
                    )
                case .rest(let rest):
                    RestSymbolView(
                        rest: rest,
                        xPos: xFor(beat: rest.beatPosition),
                        yCenter: (staffHeight + 60) / 2
                    )
                }
            }

            // Ties and slurs
            ForEach(measure.ties) { tie in
                TieArcView(
                    tie: tie,
                    measure: measure,
                    xFor: xFor,
                    yFor: yFor
                )
            }
        }
        .frame(width: width, height: staffHeight + 60)
    }
}

// MARK: - Chord View (renders up to 4 notes)
struct ChordView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var scoreEngine: ScoreEngine

    let chord: Chord
    let xPos: CGFloat
    let yFor: (Int) -> CGFloat
    let lineSpacing: CGFloat
    let partIndex: Int
    let measureIndex: Int

    var isSelected: Bool { scoreEngine.selectedChordID == chord.id }

    var body: some View {
        ZStack {
            ForEach(Array(chord.notes.enumerated()), id: \.element.id) { idx, note in
                NoteHeadView(
                    note: note,
                    duration: chord.duration,
                    xPos: xPos,
                    yPos: yFor(note.pitch.staffPosition),
                    lineSpacing: lineSpacing,
                    isSelected: isSelected
                )
            }

            // Stem (shared for chord — from lowest to highest note)
            if chord.duration != .whole, let firstNote = chord.notes.first {
                let stemY = yFor(firstNote.pitch.staffPosition)
                let stemTop = stemY - 24
                Path { p in
                    p.move(to: CGPoint(x: xPos + 4, y: stemY))
                    p.addLine(to: CGPoint(x: xPos + 4, y: stemTop))
                }
                .stroke(isSelected ? appState.theme.accent : Color.white, lineWidth: 1.2)

                // Tails
                ForEach(0..<chord.duration.tailCount, id: \.self) { t in
                    TailShape(xPos: xPos + 4, stemTop: stemTop, tailIndex: t)
                        .stroke(isSelected ? appState.theme.accent : Color.white, lineWidth: 1.2)
                }
            }
        }
        .contentShape(Rectangle().size(CGSize(width: 30, height: 80)).offset(x: xPos - 15, y: 0))
        .onTapGesture {
            scoreEngine.selectedChordID = chord.id
        }
    }
}

// MARK: - Note Head
struct NoteHeadView: View {
    let note: ScoreNote
    let duration: NoteDuration
    let xPos: CGFloat
    let yPos: CGFloat
    let lineSpacing: CGFloat
    let isSelected: Bool

    var headWidth: CGFloat { lineSpacing * 1.2 }
    var headHeight: CGFloat { lineSpacing * 0.9 }

    var body: some View {
        ZStack {
            // Accidental
            if note.accidental != .none {
                AccidentalView(type: note.accidental, x: xPos - headWidth - 2, y: yPos)
            }

            // Note head
            Ellipse()
                .fill(duration.isFilled ? (isSelected ? Color(hex: "#E040FB") : .white) : .clear)
                .overlay(
                    Ellipse()
                        .stroke(isSelected ? Color(hex: "#E040FB") : .white, lineWidth: 1.2)
                )
                .frame(width: headWidth, height: headHeight)
                .rotationEffect(.degrees(-15))
                .position(x: xPos, y: yPos)

            // Accent marker
            if note.hasAccent {
                Text(">")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
                    .position(x: xPos, y: yPos + headHeight + 4)
            }
        }
    }
}

// MARK: - Accidental View
struct AccidentalView: View {
    let type: Accidental
    let x: CGFloat
    let y: CGFloat

    var symbol: String {
        switch type {
        case .sharp: return "♯"
        case .flat: return "♭"
        case .natural: return "♮"
        case .none: return ""
        }
    }

    var body: some View {
        Text(symbol)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.white.opacity(0.9))
            .position(x: x, y: y)
    }
}

// MARK: - Tail shape for eighth/sixteenth
struct TailShape: Shape {
    let xPos: CGFloat
    let stemTop: CGFloat
    let tailIndex: Int

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let yOffset = CGFloat(tailIndex) * 5
        let startY = stemTop + yOffset
        p.move(to: CGPoint(x: xPos, y: startY))
        p.addCurve(
            to: CGPoint(x: xPos + 10, y: startY + 12),
            control1: CGPoint(x: xPos + 6, y: startY + 2),
            control2: CGPoint(x: xPos + 12, y: startY + 6)
        )
        return p
    }
}

// MARK: - Rest Symbol View
struct RestSymbolView: View {
    let rest: ScoreRest
    let xPos: CGFloat
    let yCenter: CGFloat

    var symbol: String {
        switch rest.duration {
        case .whole: return "𝄻"
        case .half: return "𝄼"
        case .quarter: return "𝄽"
        case .eighth: return "𝄾"
        case .sixteenth: return "𝄿"
        }
    }

    var body: some View {
        Text(symbol)
            .font(.system(size: 18))
            .foregroundColor(.white.opacity(0.75))
            .position(x: xPos, y: yCenter)
    }
}

// MARK: - Tie / Slur Arc
struct TieArcView: View {
    let tie: Tie
    let measure: Measure
    let xFor: (Double) -> CGFloat
    let yFor: (Int) -> CGFloat

    var body: some View {
        // Find from/to chords
        var fromX: CGFloat = 0
        var fromY: CGFloat = 0
        var toX: CGFloat = 0
        var toY: CGFloat = 0

        for content in measure.contents {
            if case .chord(let c) = content {
                if c.id == tie.fromChordID, let n = c.notes.first {
                    fromX = xFor(c.beatPosition)
                    fromY = yFor(n.pitch.staffPosition)
                }
                if c.id == tie.toChordID, let n = c.notes.first {
                    toX = xFor(c.beatPosition)
                    toY = yFor(n.pitch.staffPosition)
                }
            }
        }

        let arcY = tie.isSlur ? max(fromY, toY) + 12 : min(fromY, toY) - 12

        return Path { p in
            p.move(to: CGPoint(x: fromX, y: fromY))
            p.addQuadCurve(
                to: CGPoint(x: toX, y: toY),
                control: CGPoint(x: (fromX + toX) / 2, y: arcY)
            )
        }
        .stroke(Color.white.opacity(0.75), lineWidth: 1.5)
    }
}

// MARK: - Measure Tap Zone (for drag-and-drop / tap note entry)
struct MeasureTapZone: View {
    @EnvironmentObject var scoreEngine: ScoreEngine
    @EnvironmentObject var appState: AppState

    let partIndex: Int
    let measureIndex: Int
    let clef: Clef
    let lineSpacing: CGFloat
    let staffHeight: CGFloat

    @State private var dragLocation: CGPoint? = nil

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            dragLocation = value.location
                        }
                        .onEnded { value in
                            handleTap(at: value.location, in: geo)
                            dragLocation = nil
                        }
                )

            // Ghost note indicator during drag
            if let loc = dragLocation {
                let staffPos = staffPositionFor(y: loc.y, containerHeight: geo.size.height)
                let pitch = pitchFor(staffPos: staffPos)
                Circle()
                    .fill(appState.theme.accent.opacity(0.5))
                    .frame(width: lineSpacing * 1.2, height: lineSpacing * 0.9)
                    .position(x: loc.x, y: loc.y)

                Text(pitch.displayName)
                    .font(.system(size: 9))
                    .foregroundColor(appState.theme.accent)
                    .position(x: loc.x, y: loc.y - 14)
            }
        }
    }

    func handleTap(at location: CGPoint, in geo: GeometryProxy) {
        let staffPos = staffPositionFor(y: location.y, containerHeight: geo.size.height)
        let pitch = pitchFor(staffPos: staffPos)

        switch scoreEngine.editMode {
        case .addNote:
            scoreEngine.inputNote(pitch: pitch, in: partIndex, measureIndex: measureIndex)
        case .addRest:
            scoreEngine.inputRest(in: partIndex, measureIndex: measureIndex)
        default: break
        }
    }

    func staffPositionFor(y: CGFloat, containerHeight: CGFloat) -> Int {
        let center = containerHeight / 2
        let halfStep = lineSpacing / 2
        let offset = (center - y) / halfStep
        return Int(offset.rounded()) + clef.middleCOffset
    }

    func pitchFor(staffPos: Int) -> Pitch {
        // Convert staff position to Pitch
        // staffPos relative to middle C (C4 = position 0)
        let diatonicOrder: [PitchClass] = [.C, .D, .E, .F, .G, .A, .B]
        let relPos = staffPos
        var octaveOffset = relPos / 7
        var noteIdx = relPos % 7
        if noteIdx < 0 { noteIdx += 7; octaveOffset -= 1 }
        let baseOctave = 4 + octaveOffset
        let pc = diatonicOrder[noteIdx % 7]
        return Pitch(pitchClass: pc, octave: max(1, min(7, baseOctave)))
    }
}
