// PianoDrawerView.swift — 88-key scrollable piano with instrument switching
import SwiftUI

struct PianoDrawerView: View {
    @Environment(AppState.self) private var appState
    @Environment(AudioEngine.self) private var audioEngine
    @Environment(ScoreEngine.self) private var scoreEngine

    @State private var jumpOctave: Int = 4  // middle C octave

    var body: some View {
        VStack(spacing: 0) {
            // Drawer handle
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.2))
                .frame(width: 36, height: 4)
                .padding(.top, 8)
                .padding(.bottom, 4)

            // Header: instrument picker + octave jump
            HStack(spacing: 12) {
                // Instrument picker
                Menu {
                    ForEach(AudioInstrument.allCases, id: \.self) { instr in
                        Button(instr.rawValue) {
                            audioEngine.loadInstrument(instr)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 12))
                        Text(audioEngine.currentInstrument.rawValue)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(appStateAccent.opacity(0.15))
                            .overlay(Capsule().stroke(appStateAccent.opacity(0.4), lineWidth: 1))
                    )
                }

                Spacer()

                // Octave quick-jump (1–7)
                Text("Jump:")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))

                ForEach(1...7, id: \.self) { oct in
                    Button("\(oct)") {
                        jumpOctave = oct
                    }
                    .font(.system(size: 12, weight: jumpOctave == oct ? .bold : .regular))
                    .foregroundColor(jumpOctave == oct ? appStateAccent : .white.opacity(0.5))
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(jumpOctave == oct ? appStateAccent.opacity(0.15) : .clear)
                    )
                }

                // Sigma (sharps + flats summary)
                Button("Σ") {
                    jumpOctave = 8 // special: scroll to sigma view
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(jumpOctave == 8 ? appStateSecondary : .white.opacity(0.5))
                .frame(width: 26, height: 26)
                .background(Circle().fill(jumpOctave == 8 ? appStateSecondary.opacity(0.15) : .clear))
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider().background(Color.white.opacity(0.1))

            // Piano keyboard scroll view
            PianoScrollView(jumpOctave: $jumpOctave)
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(hex: "#111118"))
                .shadow(color: .black.opacity(0.5), radius: 20, y: -4)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Piano Scroll View
struct PianoScrollView: View {
    @Environment(AudioEngine.self) private var audioEngine
    @Environment(ScoreEngine.self) private var scoreEngine
    @Environment(AppState.self) private var appState

    @Binding var jumpOctave: Int

    private let whiteKeyWidth: CGFloat = 34
    private let whiteKeyHeight: CGFloat = 110
    private let blackKeyWidth: CGFloat = 22
    private let blackKeyHeight: CGFloat = 68

    // All notes: C1 to C8 (white keys)
    private let whiteKeys: [(PitchClass, Int)] = {
        var keys: [(PitchClass, Int)] = []
        let whites: [PitchClass] = [.C, .D, .E, .F, .G, .A, .B]
        for octave in 1...7 {
            for pc in whites { keys.append((pc, octave)) }
        }
        keys.append((.C, 8)) // high C
        return keys
    }()

    private let blackKeys: [(PitchClass, Int, Int)] = {
        // (pitchClass, octave, whiteKeyIndex)
        var keys: [(PitchClass, Int, Int)] = []
        let blacks: [(PitchClass, Int)] = [(.Db,0),(.Eb,1),(.Gb,3),(.Ab,4),(.Bb,5)]
        var whiteIdx = 0
        for octave in 1...7 {
            let base = octave * 7 - 7 // white key offset
            for (pc, offset) in blacks {
                keys.append((pc, octave, base + offset))
            }
        }
        return keys
    }()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    // White keys
                    HStack(spacing: 1) {
                        ForEach(Array(whiteKeys.enumerated()), id: \.offset) { idx, key in
                            WhiteKey(
                                pitch: Pitch(pitchClass: key.0, octave: key.1),
                                width: whiteKeyWidth,
                                height: whiteKeyHeight,
                                isPlayable: isPlayable(pitch: Pitch(pitchClass: key.0, octave: key.1)),
                                isMiddleC: key.0 == .C && key.1 == 4,
                                isMiddleCBass: key.0 == .C && key.1 == 3,
                                octaveLabel: key.0 == .C ? "\(key.1)" : nil
                            )
                            .id("white-\(key.1)-\(key.0.rawValue)")
                        }
                    }

                    // Black keys overlaid
                    ForEach(Array(blackKeys.enumerated()), id: \.offset) { idx, key in
                        let xPos = CGFloat(key.2) * (whiteKeyWidth + 1) + (whiteKeyWidth + 1) * 0.6
                        BlackKey(
                            pitch: Pitch(pitchClass: key.0, octave: key.1),
                            width: blackKeyWidth,
                            height: blackKeyHeight,
                            isPlayable: isPlayable(pitch: Pitch(pitchClass: key.0, octave: key.1))
                        )
                        .offset(x: xPos)
                    }
                }
                .frame(height: whiteKeyHeight + 20)
                .padding(.horizontal, 4)
            }
            .onChange(of: jumpOctave) { oct in
                guard oct >= 1 && oct <= 7 else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo("white-\(oct)-0", anchor: .leading)
                }
            }
        }
    }

    func isPlayable(pitch: Pitch) -> Bool {
        // Map AudioInstrument to InstrumentFamily for range check
        let range = audioEngine.currentInstrument.playableOctaveRange
        return range.contains(pitch.octave)
    }
}

extension AudioInstrument {
    var playableOctaveRange: ClosedRange<Int> {
        switch self {
        case .grandPiano: return 1...7
        case .violin: return 3...7
        case .viola: return 3...6
        case .cello: return 2...6
        case .flute: return 4...7
        case .oboe: return 4...7
        case .clarinet: return 3...6
        case .trumpet: return 3...6
        case .frenchHorn: return 2...5
        case .harp: return 1...7
        }
    }
}

// MARK: - White Key
struct WhiteKey: View {
    @Environment(AudioEngine.self) private var audioEngine
    @Environment(ScoreEngine.self) private var scoreEngine
    @Environment(AppState.self) private var appState

    let pitch: Pitch
    let width: CGFloat
    let height: CGFloat
    let isPlayable: Bool
    let isMiddleC: Bool
    let isMiddleCBass: Bool
    var octaveLabel: String? = nil

    @State private var isPressed = false

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 4)
                .fill(keyColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.black.opacity(0.3), lineWidth: 1)
                )
                .frame(width: width, height: height)

            VStack(spacing: 2) {
                // Middle C markers
                if isMiddleC {
                    Circle()
                        .fill(appStateAccent)
                        .frame(width: 6, height: 6)
                    Text("C4")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundColor(appStateAccent)
                }
                if isMiddleCBass {
                    Circle()
                        .fill(appStateSecondary)
                        .frame(width: 6, height: 6)
                    Text("C3")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundColor(appStateSecondary)
                }
                if let label = octaveLabel, !isMiddleC && !isMiddleCBass {
                    Text(label)
                        .font(.system(size: 7))
                        .foregroundColor(.black.opacity(0.4))
                }
            }
            .padding(.bottom, 6)
        }
        .opacity(isPlayable ? 1.0 : 0.35)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed && isPlayable {
                        isPressed = true
                        let dur = NoteDuration.quarter.beats
                        audioEngine.playPitch(pitch, duration: dur)
                        if scoreEngine.isRecording {
                            scoreEngine.recordLiveNote(
                                pitch: pitch,
                                instrument: InstrumentFamily(rawValue: audioEngine.currentInstrument.rawValue) ?? .piano,
                                duration: .quarter
                            )
                        }
                    }
                }
                .onEnded { _ in isPressed = false }
        )
        .animation(.easeOut(duration: 0.08), value: isPressed)
    }

    var keyColor: Color {
        if isPressed { return appStateAccent.opacity(0.35) }
        if !isPlayable { return Color(white: 0.85) }
        return .white
    }
}

// MARK: - Black Key
struct BlackKey: View {
    @Environment(AudioEngine.self) private var audioEngine
    @Environment(ScoreEngine.self) private var scoreEngine
    @Environment(AppState.self) private var appState

    let pitch: Pitch
    let width: CGFloat
    let height: CGFloat
    let isPlayable: Bool

    @State private var isPressed = false

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(isPressed ? appStateAccent.opacity(0.7) : (isPlayable ? Color(white: 0.12) : Color(white: 0.4)))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.black.opacity(0.6), lineWidth: 0.5)
            )
            .frame(width: width, height: height)
            .opacity(isPlayable ? 1.0 : 0.4)
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed && isPlayable {
                            isPressed = true
                            audioEngine.playPitch(pitch, duration: 0.3)
                        }
                    }
                    .onEnded { _ in isPressed = false }
            )
            .animation(.easeOut(duration: 0.06), value: isPressed)
    }
}
