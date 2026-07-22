// ScoreEditorView.swift — Professional score canvas with drag, zoom, pan, cursor
import SwiftUI

// MARK: - Score Editor Container
struct ScoreEditorView: View {
    @Environment(AppState.self)    private var appState
    @Environment(ScoreEngine.self) private var scoreEngine
    @State private var zoomScale: CGFloat = 1.0
    @State private var baseZoom:  CGFloat = 1.0
    @State private var panOffset: CGSize  = .zero

    var body: some View {
        VStack(spacing: 0) {
            // Pinch + pan canvas
            GeometryReader { geo in
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    ScorePageView()
                        .frame(width: geo.size.width, alignment: .topLeading)   // logical layout size
                        .scaleEffect(zoomScale, anchor: .topLeading)            // draw scaled from origin
                        .frame(                                                  // scrollable canvas grows w/ zoom
                            width:  geo.size.width  * zoomScale,
                            height: max(geo.size.height, 1200) * zoomScale,
                            alignment: .topLeading
                        )
                }
                .background(Color(hex: "#080910"))
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { v in
                            // Damped: pow < 1 slows the zoom rate for finer control
                            zoomScale = max(0.4, min(3.0, baseZoom * pow(v, 0.55)))
                        }
                        .onEnded { _ in baseZoom = zoomScale }
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

    let lineSpacing: CGFloat = 9
    let slotUnitW:   CGFloat = 52   // width of one beat-slot (one symbol design unit)

    var staffH: CGFloat { lineSpacing * 4 }
    var rowH:   CGFloat { staffH + 70 }

    func widthFor(_ measure: Measure) -> CGFloat {
        // Measure width stretches with its slot content (16 sixteenths → 16 slots wide)
        CGFloat(measure.totalSlotUnits) * slotUnitW + 32
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(part.label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))

            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
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
                                width:        widthFor(measure),
                                rowH:         rowH
                            )
                        }
                    }

                    // Tie/slur Bezier overlay — spans measures within this part
                    TieOverlayView(
                        part: part, partIndex: partIndex,
                        lineSpacing: lineSpacing, slotUnitW: slotUnitW,
                        rowH: rowH, clefW: 48
                    )
                    .allowsHitTesting(true)
                }
            }
        }
    }
}

// MARK: - Tie / Slur overlay (Bezier curves with draggable control handle)
struct TieOverlayView: View {
    @Environment(AppState.self)    private var appState
    @Environment(ScoreEngine.self) private var scoreEngine
    let part: Part
    let partIndex: Int
    let lineSpacing: CGFloat
    let slotUnitW:   CGFloat
    let rowH: CGFloat
    let clefW: CGFloat

    var staffH: CGFloat { lineSpacing * 4 }

    // Locate a chord's global position within the row: (xCenter, topNoteY, bottomNoteY)
    func locate(_ chordID: UUID) -> (x: CGFloat, topY: CGFloat, botY: CGFloat)? {
        var runningX = clefW
        for measure in part.measures {
            var cum: Double = 0
            for content in measure.contents {
                let units = content.slotUnits
                if case .chord(let ch) = content, ch.id == chordID {
                    let x = runningX + 16 + CGFloat(cum + units / 2) * slotUnitW
                    let ys = ch.notes.map { yFor($0.pitch.staffPosition) }
                    return (x, ys.min() ?? rowH/2, ys.max() ?? rowH/2)
                }
                cum += units
            }
            runningX += CGFloat(measure.totalSlotUnits) * slotUnitW + 32
        }
        return nil
    }

    func yFor(_ staffPos: Int) -> CGFloat {
        rowH / 2 - CGFloat(staffPos - part.clef.middleCOffset) * (lineSpacing / 2)
    }

    var partTies: [Tie] {
        scoreEngine.document.ties.filter { locate($0.fromChordID) != nil && locate($0.toChordID) != nil }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(partTies) { tie in
                if let a = locate(tie.fromChordID), let b = locate(tie.toChordID) {
                    TieCurve(tie: tie, a: a, b: b, accent: appState.theme.accent) { dx, dy in
                        if let idx = scoreEngine.document.ties.firstIndex(where: { $0.id == tie.id }) {
                            scoreEngine.document.ties[idx].controlDX = dx
                            scoreEngine.document.ties[idx].controlDY = dy
                        }
                    } onDelete: {
                        scoreEngine.deleteTie(id: tie.id)
                    }
                }
            }
            // Pending tie start indicator
            if let pending = scoreEngine.pendingTieStart, let p = locate(pending) {
                Circle()
                    .stroke(appState.theme.accent, lineWidth: 2)
                    .frame(width: 22, height: 22)
                    .position(x: p.x, y: p.topY - 16)
            }
        }
        .frame(height: rowH, alignment: .topLeading)
    }
}

struct TieCurve: View {
    let tie: Tie
    let a: (x: CGFloat, topY: CGFloat, botY: CGFloat)
    let b: (x: CGFloat, topY: CGFloat, botY: CGFloat)
    let accent: Color
    let onControlChange: (Double, Double) -> Void
    let onDelete: () -> Void

    @State private var dragCtl: CGSize? = nil

    var startPt: CGPoint {
        tie.isSlur ? CGPoint(x: a.x, y: a.botY + 12) : CGPoint(x: a.x, y: a.topY - 12)
    }
    var endPt: CGPoint {
        tie.isSlur ? CGPoint(x: b.x, y: b.botY + 12) : CGPoint(x: b.x, y: b.topY - 12)
    }
    var ctlPt: CGPoint {
        let midX = (startPt.x + endPt.x) / 2
        let midY = (startPt.y + endPt.y) / 2
        let arch: CGFloat = tie.isSlur ? 26 : -26   // slur dips down, tie arcs up
        let dx = dragCtl?.width  ?? CGFloat(tie.controlDX)
        let dy = dragCtl?.height ?? CGFloat(tie.controlDY)
        return CGPoint(x: midX + dx, y: midY + arch + dy)
    }

    var body: some View {
        ZStack {
            Path { p in
                p.move(to: startPt)
                p.addQuadCurve(to: endPt, control: ctlPt)
            }
            .stroke(Color.white.opacity(0.85),
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round))

            // Draggable tangent handle at curve midpoint
            Circle()
                .fill(accent.opacity(0.9))
                .frame(width: 10, height: 10)
                .position(x: (startPt.x + 2*ctlPt.x + endPt.x)/4,
                          y: (startPt.y + 2*ctlPt.y + endPt.y)/4)
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { v in
                            dragCtl = CGSize(
                                width:  CGFloat(tie.controlDX) + v.translation.width,
                                height: CGFloat(tie.controlDY) + v.translation.height
                            )
                        }
                        .onEnded { _ in
                            if let d = dragCtl { onControlChange(Double(d.width), Double(d.height)) }
                            dragCtl = nil
                        }
                )
                .onLongPressGesture { onDelete() }
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

    // Slot-based X: cumulative slot units before this content + half its own span
    func xForContent(_ id: UUID) -> CGFloat {
        var cum: Double = 0
        for content in measure.contents {
            let units = content.slotUnits
            if content.id == id { return 16 + CGFloat(cum + units / 2) * slotUnitW }
            cum += units
        }
        return 16 + CGFloat(cum) * slotUnitW
    }
    func contentAt(x: CGFloat) -> BeatContent? {
        var cum: Double = 0
        for content in measure.contents {
            let units = content.slotUnits
            let x0 = 16 + CGFloat(cum) * slotUnitW
            let x1 = 16 + CGFloat(cum + units) * slotUnitW
            if x >= x0 && x < x1 { return content }
            cum += units
        }
        return nil
    }
    var usedSlotUnits: Double { measure.contents.reduce(0) { $0 + $1.slotUnits } }
    var slotUnitW: CGFloat { 52 }

    func xFor(_ beat: Double) -> CGFloat {
        // Legacy fallback (playback cursor etc.)
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
        let offset  = 700
        let shifted = staffPos + offset
        let octave  = shifted / 7 - (offset / 7) + 4
        let idx     = ((shifted % 7) + 7) % 7
        return Pitch(
            pitchClass: whites[max(0, min(6, idx))],
            octave:     max(1, min(7, octave))
        )
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
                    let chordSel = lassoSelected.contains(chord.id) || scoreEngine.selectedChordID == chord.id
                    let isSelected = chordSel
                    let isDragging = draggingID == chord.id
                    Group {
                        ForEach(chord.notes) { note in
                            let yPos = yFor(note.pitch.staffPosition) + (isDragging ? dragOffset.height : 0)
                            let xPos = xForContent(chord.id)
                            NoteHeadCanvas(
                                duration: note.duration,
                                xPos: xPos,
                                yPos: yPos,
                                lineSpacing: lineSpacing,
                                isSelected: chordSel && (scoreEngine.selectedNoteID == nil || scoreEngine.selectedNoteID == note.id),
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
                        // Stems — one per note, tails per that note's duration
                        ForEach(chord.notes) { note in
                            if note.duration != .whole {
                                let sY = yFor(note.pitch.staffPosition) + (isDragging ? dragOffset.height : 0)
                                StemView(xPos: xForContent(chord.id), headY: sY,
                                         tailCount: note.duration.tailCount,
                                         isSelected: isSelected, accent: appState.theme.accent)
                            }
                        }
                        // Ascend/descend accent arrows — below whole chord + note indicator
                        ForEach(chord.notes.filter { $0.accentType != nil }) { note in
                            let botY = (chord.notes.map { yFor($0.pitch.staffPosition) }.max() ?? rowH/2)
                            HStack(spacing: 2) {
                                Image(systemName: note.accentType == .ascend ? "chevron.left" : "chevron.right")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white.opacity(0.9))
                                if chord.notes.count > 1 {
                                    Text(note.pitch.displayName)
                                        .font(.system(size: 7, design: .monospaced))
                                        .foregroundColor(appState.theme.accent)
                                }
                            }
                            .position(x: xForContent(chord.id), y: botY + 22)
                        }
                    }
                    .contentShape(Rectangle().size(CGSize(width: 40, height: 80))
                        .offset(x: xForContent(chord.id) - 20, y: 0))
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { val in
                                let isMoveMode: Bool = {
                                    if case .move = scoreEngine.editMode { return true }
                                    return false
                                }()
                                let isAlreadySelected = scoreEngine.selectedChordID == chord.id

                                // Allow drag in move mode (any note) OR dragging an already-selected note
                                guard isMoveMode || isAlreadySelected else { return }

                                if draggingID != chord.id {
                                    draggingID = chord.id
                                    scoreEngine.selectedChordID = chord.id
                                    dragOffset = .zero
                                }
                                dragOffset = val.translation

                                let origSP = chord.notes.first?.pitch.staffPosition ?? 0
                                let origY  = yFor(origSP)
                                let newY   = origY + val.translation.height
                                let sp     = staffPosAt(y: newY)
                                ghostPitch = pitchAt(staffPos: sp)
                            }
                            .onEnded { val in
                                if draggingID == chord.id, let gp = ghostPitch {
                                    if let nid = scoreEngine.selectedNoteID,
                                       chord.notes.contains(where: { $0.id == nid }) {
                                        moveSingleNote(chord: chord, noteID: nid, newPitch: gp)
                                    } else {
                                        moveChord(chord: chord, newPitch: gp)
                                    }
                                }
                                draggingID = nil
                                dragOffset  = .zero
                                ghostPitch  = nil
                            }
                    )


                case .rest(let rest):
                    SafeRestView(
                        symbol: restSymbol(rest.duration),
                        xPos: xForContent(rest.id),
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

            // Remaining-beats placeholder slots (must be filled with notes or rests)
            if measure.remainingBeats > 0 && !measure.contents.isEmpty {
                let remaining = Int(measure.remainingBeats.rounded(.up))
                ForEach(0..<remaining, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(style: StrokeStyle(lineWidth: 0.8, dash: [3,3]))
                        .foregroundColor(.white.opacity(0.12))
                        .frame(width: slotUnitW - 14, height: staffH + 8)
                        .position(
                            x: 16 + CGFloat(usedSlotUnits + Double(i) + 0.5) * slotUnitW,
                            y: rowH / 2
                        )
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
                            switch scoreEngine.editMode {
                            case .select:
                                // Lasso
                                if lassoStart == nil { lassoStart = val.startLocation }
                                lassoEnd = val.location
                                updateLassoSelection()
                            case .move:
                                // Drag a note/chord from wherever the touch started
                                if draggingID == nil {
                                    if let hit = contentAt(x: val.startLocation.x),
                                       case .chord(let ch) = hit {
                                        draggingID = ch.id
                                        scoreEngine.selectedChordID = ch.id
                                        // Nearest note at touch start = single-note move target
                                        let nearest = ch.notes.min(by: {
                                            abs(yFor($0.pitch.staffPosition) - val.startLocation.y) <
                                            abs(yFor($1.pitch.staffPosition) - val.startLocation.y)
                                        })
                                        scoreEngine.selectedNoteID = nearest?.id
                                    }
                                }
                                if draggingID != nil {
                                    dragOffset = val.translation
                                    let sp = staffPosAt(y: val.location.y)
                                    ghostPitch = pitchAt(staffPos: sp)
                                }
                            default:
                                ghostPos   = val.location
                                let sp     = staffPosAt(y: val.location.y)
                                ghostPitch = pitchAt(staffPos: sp)
                            }
                        }
                        .onEnded { val in
                            let isTap = abs(val.translation.width) < 6 && abs(val.translation.height) < 6
                            switch scoreEngine.editMode {
                            case .select:
                                lassoStart = nil; lassoEnd = nil
                                if isTap { handleTap(at: val.location) }
                            case .move:
                                if let dragID = draggingID, !isTap, let gp = ghostPitch,
                                   let hit = measure.contents.first(where: { $0.id == dragID }),
                                   case .chord(let ch) = hit {
                                    if let nid = scoreEngine.selectedNoteID,
                                       ch.notes.contains(where: { $0.id == nid }) {
                                        moveSingleNote(chord: ch, noteID: nid, newPitch: gp)
                                    } else {
                                        moveChord(chord: ch, newPitch: gp)
                                    }
                                } else if isTap {
                                    handleTap(at: val.location)
                                }
                                draggingID = nil; dragOffset = .zero; ghostPitch = nil
                            default:
                                handleTap(at: val.location)
                                ghostPos = nil; ghostPitch = nil
                            }
                        }
                )
        }
        .frame(width: width, height: rowH)
    }

    func handleTap(at loc: CGPoint) {
        let sp    = staffPosAt(y: loc.y)
        let pitch = pitchAt(staffPos: sp)

        // Which content slot (if any) was tapped?
        var cum: Double = 0
        var hit: BeatContent? = nil
        for content in measure.contents {
            let units = content.slotUnits
            let x0 = 16 + CGFloat(cum) * slotUnitW
            let x1 = 16 + CGFloat(cum + units) * slotUnitW
            if loc.x >= x0 && loc.x < x1 { hit = content; break }
            cum += units
        }

        switch scoreEngine.editMode {
        case .addNote:
            if let hit, case .chord(let ch) = hit {
                // Tap ON an existing chord slot → build/replace within that chord
                scoreEngine.addNoteToChord(chordID: ch.id, pitch: pitch,
                                           partIndex: partIndex, measureIndex: measureIndex)
            } else {
                // Empty area → append a new beat
                scoreEngine.inputNote(pitch: pitch, in: partIndex, measureIndex: measureIndex)
            }
        case .addRest:
            scoreEngine.inputRest(in: partIndex, measureIndex: measureIndex)
        case .select, .move:
            if let hit, case .chord(let ch) = hit {
                // Nearest note in the chord by Y = individual note selection
                let nearest = ch.notes.min(by: {
                    abs(yFor($0.pitch.staffPosition) - loc.y) < abs(yFor($1.pitch.staffPosition) - loc.y)
                })
                scoreEngine.selectedChordID = ch.id
                scoreEngine.selectedNoteID  = nearest?.id
            } else {
                scoreEngine.selectedChordID = nil
                scoreEngine.selectedNoteID  = nil
            }
        case .delete:
            if let hit, case .chord(let ch) = hit {
                let nearest = ch.notes.min(by: {
                    abs(yFor($0.pitch.staffPosition) - loc.y) < abs(yFor($1.pitch.staffPosition) - loc.y)
                })
                if ch.notes.count > 1, let n = nearest {
                    scoreEngine.deleteNote(noteID: n.id, chordID: ch.id, partIndex: partIndex)
                } else {
                    scoreEngine.deleteContent(id: ch.id, partIndex: partIndex)
                }
            } else if let hit, case .rest(let r) = hit {
                scoreEngine.deleteContent(id: r.id, partIndex: partIndex)
            }
        case .addTie, .addSlur:
            if let hit, case .chord(let ch) = hit {
                scoreEngine.handleTieTap(chordID: ch.id)
            }
        case .addAccent(let type):
            if let hit, case .chord(let ch) = hit {
                scoreEngine.applyAccent(type, chordID: ch.id, partIndex: partIndex)
            }
        default: break
        }
    }


    func moveSingleNote(chord: Chord, noteID: UUID, newPitch: Pitch) {
        scoreEngine.snapshot()
        for mi in 0..<scoreEngine.document.parts[partIndex].measures.count {
            for ci in 0..<scoreEngine.document.parts[partIndex].measures[mi].contents.count {
                if case .chord(var c2) = scoreEngine.document.parts[partIndex].measures[mi].contents[ci],
                   c2.id == chord.id,
                   let ni = c2.notes.firstIndex(where: { $0.id == noteID }) {
                    c2.notes[ni].pitch = newPitch
                    c2.notes.sort { $0.pitch.staffPosition < $1.pitch.staffPosition }
                    scoreEngine.document.parts[partIndex].measures[mi].contents[ci] = .chord(c2)
                    let instrName = scoreEngine.document.parts[partIndex].instrument.rawValue
                    AWAudioPlayer.shared.playPitch(newPitch, instrumentName: instrName, duration: 0.4)
                    return
                }
            }
        }
    }

    func moveChord(chord: Chord, newPitch: Pitch) {
        scoreEngine.snapshot()
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
                    let instrName = scoreEngine.document.parts[partIndex].instrument.rawValue
                    for note in c.notes {
                        AWAudioPlayer.shared.playPitch(note.pitch, instrumentName: instrName, duration: 0.4)
                    }
                    return
                }
            }
        }
    }

    func pitchFromStaffPos(_ staffPos: Int) -> Pitch {
        // staffPos 0 = C4 (middle C), positive = higher, negative = lower
        // Each octave span = 7 diatonic steps
        let whites: [PitchClass] = [.C, .D, .E, .F, .G, .A, .B]
        // Use a large offset to keep modulo positive
        let offset = 700  // 100 octaves
        let shifted = staffPos + offset
        let octave  = shifted / 7 - (offset / 7) + 4
        let idx     = ((shifted % 7) + 7) % 7
        return Pitch(
            pitchClass: whites[max(0, min(6, idx))],
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
