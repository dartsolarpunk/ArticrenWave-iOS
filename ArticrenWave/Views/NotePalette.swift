// NotePalette.swift — Note duration + edit mode selector
import SwiftUI

struct NotePalette: View {
    @Environment(AppState.self) private var appState
    @Environment(ScoreEngine.self) private var scoreEngine

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // Select mode
                PaletteButton(
                    label: "✦",
                    sublabel: "Select",
                    isActive: { if case .select = scoreEngine.editMode { return true }; return false }()
                ) { scoreEngine.editMode = .select }

                Divider().frame(height: 28).background(Color.white.opacity(0.15))

                // Note durations
                ForEach(NoteDuration.allCases, id: \.self) { dur in
                    PaletteButton(
                        label: noteSymbol(dur),
                        sublabel: dur.rawValue.capitalized,
                        isActive: {
                            if case .addNote(let d) = scoreEngine.editMode { return d == dur }
                            return false
                        }()
                    ) { scoreEngine.editMode = .addNote(dur) }
                }

                Divider().frame(height: 28).background(Color.white.opacity(0.15))

                // Rest durations
                ForEach(RestDuration.allCases, id: \.self) { dur in
                    PaletteButton(
                        label: restSymbol(dur),
                        sublabel: "Rest",
                        isActive: {
                            if case .addRest(let d) = scoreEngine.editMode { return d == dur }
                            return false
                        }()
                    ) { scoreEngine.editMode = .addRest(dur) }
                }

                Divider().frame(height: 28).background(Color.white.opacity(0.15))

                // Accidentals
                PaletteButton(label: "♯", sublabel: "Sharp",
                    isActive: { if case .addAccidental(let a) = scoreEngine.editMode { return a == .sharp }; return false }()
                ) { scoreEngine.editMode = .addAccidental(.sharp) }

                PaletteButton(label: "♭", sublabel: "Flat",
                    isActive: { if case .addAccidental(let a) = scoreEngine.editMode { return a == .flat }; return false }()
                ) { scoreEngine.editMode = .addAccidental(.flat) }

                PaletteButton(label: "♮", sublabel: "Nat.",
                    isActive: { if case .addAccidental(let a) = scoreEngine.editMode { return a == .natural }; return false }()
                ) { scoreEngine.editMode = .addAccidental(.natural) }

                Divider().frame(height: 28).background(Color.white.opacity(0.15))

                // Tie / Slur
                PaletteButton(label: "⌢", sublabel: "Tie",
                    isActive: { if case .addTie = scoreEngine.editMode { return true }; return false }()
                ) { scoreEngine.editMode = .addTie }

                PaletteButton(label: "⌣", sublabel: "Slur",
                    isActive: { if case .addSlur = scoreEngine.editMode { return true }; return false }()
                ) { scoreEngine.editMode = .addSlur }

                // Accent
                PaletteButton(label: ">", sublabel: "Accent",
                    isActive: { if case .addAccent = scoreEngine.editMode { return true }; return false }()
                ) { scoreEngine.editMode = .addAccent }

                Divider().frame(height: 28).background(Color.white.opacity(0.15))

                // Delete
                PaletteButton(label: "⌫", sublabel: "Delete",
                    isActive: { if case .delete = scoreEngine.editMode { return true }; return false }(),
                    accent: .red
                ) { scoreEngine.editMode = .delete }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    func noteSymbol(_ dur: NoteDuration) -> String {
        switch dur {
        case .whole: return "𝅝"
        case .half: return "𝅗𝅥"
        case .quarter: return "𝅘𝅥"
        case .eighth: return "𝅘𝅥𝅮"
        case .sixteenth: return "𝅘𝅥𝅯"
        }
    }

    func restSymbol(_ dur: RestDuration) -> String {
        switch dur {
        case .whole: return "𝄻"
        case .half: return "𝄼"
        case .quarter: return "𝄽"
        case .eighth: return "𝄾"
        case .sixteenth: return "𝄿"
        }
    }
}

struct PaletteButton: View {
    @Environment(AppState.self) private var appState

    let label: String
    let sublabel: String
    let isActive: Bool
    var accent: Color? = nil
    let action: () -> Void

    var activeColor: Color {
        accent ?? appState.theme.accent
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(label)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isActive ? activeColor : .white.opacity(0.7))

                Text(sublabel)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(isActive ? activeColor.opacity(0.8) : .white.opacity(0.3))
            }
            .frame(width: 38, height: 42)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isActive ? activeColor.opacity(0.15) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(isActive ? activeColor.opacity(0.5) : Color.clear, lineWidth: 1)
                    )
            )
        }
    }
}
