// ScoreEditorView.swift — Score canvas (crash-safe build)
// Articren Wave · © 2026 DART Meadow LLC & Radical Deepscale LLC
import SwiftUI

// MARK: - Score Editor Container
struct ScoreEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(ScoreEngine.self) private var scoreEngine

    var body: some View {
        VStack(spacing: 0) {
            NotePalette()
                .padding(.horizontal, 8)
                .padding(.vertical, 6)

            if let err = scoreEngine.validationError {
                Text(err)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(appState.theme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(appState.theme.accent.opacity(0.1))
                    .onTapGesture { scoreEngine.validationError = nil }
            }

            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                SafeScoreCanvas()
            }
            .background(appState.theme.background)
        }
    }
}

// MARK: - Safe Score Canvas
struct SafeScoreCanvas: View {
    @Environment(AppState.self) private var appState
    @Environment(ScoreEngine.self) private var scoreEngine

    let lineSpacing:  CGFloat = 9
    let measureWidth: CGFloat = 200
    let leftPad:      CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 70) {
            if scoreEngine.document.parts.isEmpty {
                Text("Tap Layout to add a staff")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                    .padding(40)
            } else {
                ForEach(Array(scoreEngine.document.parts.enumerated()),
                        id: \.element.id) { pi, part in
                    SafeStaffRow(
                        partIndex:   pi,
                        part:        part,
                        lineSpacing: lineSpacing,
                        measureW:    measureWidth
                    )
                }
            }
        }
        .padding(leftPad)
    }
}

// MARK: - Safe Staff Row
struct SafeStaffRow: View {
    @Environment(AppState.self) private var appState
    @Environment(ScoreEngine.self) private var scoreEngine

    let partIndex:   Int
    let part:        Part
    let lineSpacing: CGFloat
    let measureW:    CGFloat

    var staffH: CGFloat { lineSpacing * 4 }
    var rowH:   CGFloat { staffH + 60 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Part label
            Text(part.label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    // Clef
                    SafeClefView(clef: part.clef, lineSpacing: lineSpacing)
                        .frame(width: 44, height: rowH)

                    // Measures
                    ForEach(Array(part.measures.enumerated()),
                            id: \.element.id) { mi, measure in
                        SafeMeasureView(
                            measure:      measure,
                            partIndex:    partIndex,
                            measureIndex: mi,
                            clef:         part.clef,
                            lineSpacing:  lineSpacing,
                            width:        measureW,
                            rowH:         rowH
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Safe Clef
struct SafeClefView: View {
    let clef:        Clef
    let lineSpacing: CGFloat

    var staffH: CGFloat { lineSpacing * 4 }

    var body: some View {
        Canvas { ctx, size in
            let top = (size.height - staffH) / 2
            for i in 0...4 {
                let y = top + CGFloat(i) * lineSpacing
                var p = Path()
                p.move(to:    CGPoint(x: 4, y: y))
                p.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(p, with: .color(.white.opacity(0.65)), lineWidth: 0.7)
            }
            let symbol = clef == .treble ? "𝄞" : "𝄢"
            let size2: CGFloat = clef == .treble ? 36 : 26
            ctx.draw(
                Text(symbol).font(.system(size: size2)).foregroundColor(.white),
                at: CGPoint(x: size.width / 2, y: size.height / 2),
                anchor: .center
            )
        }
    }
}

// MARK: - Safe Measure View
struct SafeMeasureView: View {
    @Environment(AppState.self) private var appState
    @Environment(ScoreEngine.self) private var scoreEngine

    let measure:      Measure
    let partIndex:    Int
    let measureIndex: Int
    let clef:         Clef
    let lineSpacing:  CGFloat
    let width:        CGFloat
    let rowH:         CGFloat

    var staffH: CGFloat { lineSpacing * 4 }

    // Beat → X position
    func xFor(_ beat: Double) -> CGFloat {
        let usable = width - 32
        return 16 + CGFloat(beat / 4.0) * usable
    }

    // Staff position → Y position
    func yFor(_ staffPos: Int) -> CGFloat {
        let center  = rowH / 2
        let halfStep = lineSpacing / 2
        return center - CGFloat(staffPos - clef.middleCOffset) * halfStep
    }

    var body: some View {
        ZStack {
            // Staff lines + bar line
            Canvas { ctx, size in
                let top = (size.height - staffH) / 2
                for i in 0...4 {
                    let y = top + CGFloat(i) * lineSpacing
                    var p = Path()
                    p.move(to:    CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                    ctx.stroke(p, with: .color(.white.opacity(0.6)), lineWidth: 0.7)
                }
                var bar = Path()
                bar.move(to:    CGPoint(x: size.width - 1, y: (size.height - staffH) / 2))
                bar.addLine(to: CGPoint(x: size.width - 1, y: (size.height + staffH) / 2))
                ctx.stroke(bar, with: .color(.white.opacity(0.45)), lineWidth: 1)
            }

            // Contents
            ForEach(measure.contents) { content in
                switch content {
                case .chord(let chord):
                    SafeChordView(
                        chord:      chord,
                        xPos:       xFor(chord.beatPosition),
                        yFor:       yFor,
                        lineSpacing: lineSpacing,
                        isSelected: scoreEngine.selectedChordID == chord.id
                    )
                    .onTapGesture { scoreEngine.selectedChordID = chord.id }

                case .rest(let rest):
                    SafeRestView(
                        symbol: restSymbol(rest.duration),
                        xPos:   xFor(rest.beatPosition),
                        yPos:   rowH / 2
                    )
                }
            }

            // Tap to add
            SafeTapZone(
                partIndex:    partIndex,
                measureIndex: measureIndex,
                clef:         clef,
                lineSpacing:  lineSpacing,
                rowH:         rowH,
                xFor:         xFor,
                yFor:         yFor
            )
        }
        .frame(width: width, height: rowH)
    }

    func restSymbol(_ d: RestDuration) -> String {
        switch d {
        case .whole: return "𝄻"
        case .half:  return "𝄼"
        case .quarter: return "𝄽"
        case .eighth:  return "𝄾"
        case .sixteenth: return "𝄿"
        }
    }
}

// MARK: - Safe Chord View
struct SafeChordView: View {
    let chord:       Chord
    let xPos:        CGFloat
    let yFor:        (Int) -> CGFloat
    let lineSpacing: CGFloat
    let isSelected:  Bool

    @Environment(AppState.self) private var appState

    var headW: CGFloat { lineSpacing * 1.2 }
    var headH: CGFloat { lineSpacing * 0.9 }

    var body: some View {
        ZStack {
            ForEach(chord.notes) { note in
                let yPos = yFor(note.pitch.staffPosition)

                // Accidental
                if note.accidental != .none {
                    Text(accidentalSymbol(note.accidental))
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.9))
                        .position(x: xPos - headW - 2, y: yPos)
                }

                // Note head
                Ellipse()
                    .fill(chord.duration.isFilled
                          ? (isSelected ? appState.theme.accent : Color.white)
                          : Color.clear)
                    .overlay(
                        Ellipse().stroke(
                            isSelected ? appState.theme.accent : Color.white,
                            lineWidth: 1.2
                        )
                    )
                    .frame(width: headW, height: headH)
                    .rotationEffect(.degrees(-15))
                    .position(x: xPos, y: yPos)
            }

            // Stem
            if chord.duration != .whole, let first = chord.notes.first {
                let stemY   = yFor(first.pitch.staffPosition)
                let stemTop = stemY - 24
                Path { p in
                    p.move(to:    CGPoint(x: xPos + 4, y: stemY))
                    p.addLine(to: CGPoint(x: xPos + 4, y: stemTop))
                }
                .stroke(isSelected ? appState.theme.accent : Color.white,
                        lineWidth: 1.2)

                // Tails for eighth/sixteenth
                ForEach(0..<chord.duration.tailCount, id: \.self) { t in
                    Path { p in
                        let y0 = stemTop + CGFloat(t) * 5
                        p.move(to: CGPoint(x: xPos + 4, y: y0))
                        p.addCurve(
                            to:       CGPoint(x: xPos + 14, y: y0 + 12),
                            control1: CGPoint(x: xPos + 10, y: y0 + 2),
                            control2: CGPoint(x: xPos + 16, y: y0 + 6)
                        )
                    }
                    .stroke(isSelected ? appState.theme.accent : Color.white,
                            lineWidth: 1.2)
                }
            }
        }
    }

    func accidentalSymbol(_ a: Accidental) -> String {
        switch a {
        case .sharp:   return "♯"
        case .flat:    return "♭"
        case .natural: return "♮"
        case .none:    return ""
        }
    }
}

// MARK: - Safe Rest View
struct SafeRestView: View {
    let symbol: String
    let xPos:   CGFloat
    let yPos:   CGFloat

    var body: some View {
        Text(symbol)
            .font(.system(size: 18))
            .foregroundColor(.white.opacity(0.75))
            .position(x: xPos, y: yPos)
    }
}

// MARK: - Safe Tap Zone
struct SafeTapZone: View {
    @Environment(ScoreEngine.self) private var scoreEngine
    @Environment(AppState.self) private var appState

    let partIndex:    Int
    let measureIndex: Int
    let clef:         Clef
    let lineSpacing:  CGFloat
    let rowH:         CGFloat
    let xFor:         (Double) -> CGFloat
    let yFor:         (Int) -> CGFloat

    @State private var ghostPos: CGPoint? = nil

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in ghostPos = v.location }
                        .onEnded   { v in
                            handleTap(at: v.location, size: geo.size)
                            ghostPos = nil
                        }
                )

            if let pos = ghostPos {
                let sp    = staffPosFor(y: pos.y)
                let pitch = pitchFor(staffPos: sp)
                Circle()
                    .fill(appState.theme.accent.opacity(0.45))
                    .frame(width: lineSpacing * 1.2, height: lineSpacing * 0.9)
                    .position(pos)
                Text(pitch.displayName)
                    .font(.system(size: 9))
                    .foregroundColor(appState.theme.accent)
                    .position(x: pos.x, y: pos.y - 14)
            }
        }
    }

    func handleTap(at loc: CGPoint, size: CGSize) {
        let sp    = staffPosFor(y: loc.y)
        let pitch = pitchFor(staffPos: sp)
        switch scoreEngine.editMode {
        case .addNote:
            scoreEngine.inputNote(pitch: pitch, in: partIndex, measureIndex: measureIndex)
        case .addRest:
            scoreEngine.inputRest(in: partIndex, measureIndex: measureIndex)
        default: break
        }
    }

    func staffPosFor(y: CGFloat) -> Int {
        let center   = rowH / 2
        let halfStep = lineSpacing / 2
        let offset   = (center - y) / halfStep
        return Int(offset.rounded()) + clef.middleCOffset
    }

    func pitchFor(staffPos: Int) -> Pitch {
        let whites: [PitchClass] = [.C, .D, .E, .F, .G, .A, .B]
        var oct = 4 + staffPos / 7
        var idx = staffPos % 7
        if idx < 0 { idx += 7; oct -= 1 }
        return Pitch(
            pitchClass: whites[max(0, min(6, idx))],
            octave:     max(1, min(7, oct))
        )
    }
}
