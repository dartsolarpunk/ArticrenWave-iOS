// NotePalette.swift — Professional note input toolbar with vector symbols
import SwiftUI

struct NotePalette: View {
    @Environment(AppState.self)    private var appState
    @Environment(ScoreEngine.self) private var scoreEngine

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {

                // ── SELECT ──────────────────────────────────────
                PaletteKey(
                    label: { Image(systemName: "cursorarrow").font(.system(size: 14)) },
                    sublabel: "Select",
                    isActive: { if case .select = scoreEngine.editMode { return true }; return false }(),
                    accent: appState.theme.accent
                ) { scoreEngine.editMode = .select }

                // ── MOVE ──────────────────────────────────────
                PaletteKey(
                    label: { Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                        .font(.system(size: 12)) },
                    sublabel: "Move",
                    isActive: { if case .move = scoreEngine.editMode { return true }; return false }(),
                    accent: appState.theme.accent
                ) { scoreEngine.editMode = .move }

                paletteDivider

                // ── NOTES ───────────────────────────────────────
                ForEach(NoteDuration.allCases, id: \.self) { dur in
                    PaletteKey(
                        label: { NoteSymbolView(duration: dur, color: noteActive(dur) ? appState.theme.accent : .white, size: 18) },
                        sublabel: dur.shortLabel,
                        isActive: noteActive(dur),
                        accent: appState.theme.accent
                    ) { scoreEngine.editMode = .addNote(dur) }
                }

                paletteDivider

                // ── RESTS ───────────────────────────────────────
                ForEach(NoteDuration.allCases, id: \.self) { dur in
                    PaletteKey(
                        label: { NoteSymbolView(duration: dur, color: restActive(dur) ? appState.theme.accent : .white.opacity(0.7), size: 18, isRest: true) },
                        sublabel: "R",
                        isActive: restActive(dur),
                        accent: appState.theme.accent
                    ) {
                        scoreEngine.editMode = .addRest(restDurationFor(dur))
                    }
                }

                paletteDivider

                // ── ACCIDENTALS ─────────────────────────────────
                PaletteKey(
                    label: { SharpSymbol(color: accidentalActive(.sharp) ? appState.theme.accent : .white, size: 14) },
                    sublabel: "Sharp",
                    isActive: accidentalActive(.sharp),
                    accent: appState.theme.accent
                ) { scoreEngine.editMode = .addAccidental(.sharp) }

                PaletteKey(
                    label: { FlatSymbol(color: accidentalActive(.flat) ? appState.theme.accent : .white, size: 14) },
                    sublabel: "Flat",
                    isActive: accidentalActive(.flat),
                    accent: appState.theme.accent
                ) { scoreEngine.editMode = .addAccidental(.flat) }

                PaletteKey(
                    label: { NaturalSymbol(color: accidentalActive(.natural) ? appState.theme.accent : .white, size: 14) },
                    sublabel: "Nat.",
                    isActive: accidentalActive(.natural),
                    accent: appState.theme.accent
                ) { scoreEngine.editMode = .addAccidental(.natural) }

                paletteDivider

                // ── TIE / SLUR ──────────────────────────────────
                PaletteKey(
                    label: { TieCurveSymbol(color: isTie ? appState.theme.accent : .white, size: 18, isSlur: false) },
                    sublabel: "Tie",
                    isActive: isTie,
                    accent: appState.theme.accent
                ) { scoreEngine.editMode = .addTie }

                PaletteKey(
                    label: { TieCurveSymbol(color: isSlur ? appState.theme.accent : .white, size: 18, isSlur: true) },
                    sublabel: "Slur",
                    isActive: isSlur,
                    accent: appState.theme.accent
                ) { scoreEngine.editMode = .addSlur }

                // ── ACCENTS: ascend (<) / descend (>) ───────────
                PaletteKey(
                    label: { Image(systemName: "chevron.left").font(.system(size: 13, weight: .bold)) },
                    sublabel: "Ascend",
                    isActive: isAccentType(.ascend),
                    accent: appState.theme.accent
                ) { scoreEngine.editMode = .addAccent(.ascend) }

                PaletteKey(
                    label: { Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)) },
                    sublabel: "Descend",
                    isActive: isAccentType(.descend),
                    accent: appState.theme.accent
                ) { scoreEngine.editMode = .addAccent(.descend) }

                paletteDivider

                // ── DELETE ──────────────────────────────────────
                PaletteKey(
                    label: { Image(systemName: "delete.backward").font(.system(size: 14)) },
                    sublabel: "Erase",
                    isActive: isDelete,
                    accent: .red
                ) { scoreEngine.editMode = .delete }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .background(
            Color(hex: "#0C0D18")
                .overlay(Rectangle().fill(Color.white.opacity(0.03)))
        )
        .overlay(Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1), alignment: .bottom)
    }

    var paletteDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(width: 1, height: 36)
            .padding(.horizontal, 4)
    }

    // ── Mode checks ─────────────────────────────────────────────
    func noteActive(_ dur: NoteDuration) -> Bool {
        if case .addNote(let d) = scoreEngine.editMode { return d == dur }
        return false
    }
    func restActive(_ dur: NoteDuration) -> Bool {
        if case .addRest(let d) = scoreEngine.editMode { return d == restDurationFor(dur) }
        return false
    }
    func accidentalActive(_ acc: Accidental) -> Bool {
        if case .addAccidental(let a) = scoreEngine.editMode { return a == acc }
        return false
    }
    func restDurationFor(_ dur: NoteDuration) -> RestDuration {
        switch dur {
        case .whole:     return .whole
        case .half:      return .half
        case .quarter:   return .quarter
        case .eighth:    return .eighth
        case .sixteenth: return .sixteenth
        }
    }
    var isMove:   Bool { if case .move      = scoreEngine.editMode { return true }; return false }
    var isTie:    Bool { if case .addTie    = scoreEngine.editMode { return true }; return false }
    var isSlur:   Bool { if case .addSlur   = scoreEngine.editMode { return true }; return false }
    func isAccentType(_ t: AccentType) -> Bool {
        if case .addAccent(let a) = scoreEngine.editMode { return a == t }; return false
    }
    var isDelete: Bool { if case .delete    = scoreEngine.editMode { return true }; return false }
}

extension NoteDuration {
    var shortLabel: String {
        switch self {
        case .whole:     return "Whole"
        case .half:      return "Half"
        case .quarter:   return "Qtr"
        case .eighth:    return "8th"
        case .sixteenth: return "16th"
        }
    }
}

// MARK: - Palette Key
struct PaletteKey<Label: View>: View {
    @ViewBuilder let label: () -> Label
    let sublabel: String
    let isActive: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                label()
                    .frame(height: 24)
                Text(sublabel)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(isActive ? accent : .white.opacity(0.35))
                    .lineLimit(1)
            }
            .foregroundColor(isActive ? accent : .white.opacity(0.8))
            .frame(width: 44, height: 50)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? accent.opacity(0.14) : Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isActive ? accent.opacity(0.55) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
