// PianoDrawerView.swift — 88-key piano, correct octave direction
// Octave 1 = highest (far right treble), Octave 7 = lowest (far left bass)
// Black key RIGHT of white = sharp, BLACK key LEFT of white = flat
import SwiftUI

struct PianoDrawerView: View {
    @Environment(AppState.self)    private var appState
    @Environment(AudioEngine.self) private var audioEngine
    @Environment(ScoreEngine.self) private var scoreEngine
    @State private var jumpOctave: Int = 4   // default middle area

    let instruments = ["Grand Piano","Violin","Viola","Cello",
                       "Flute","Oboe","Clarinet","Trumpet","French Horn","Harp"]

    var body: some View {
        VStack(spacing: 0) {
            // Pull tab / header
            HStack(spacing: 0) {
                // Chevron dismiss
                Button {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        appState.isPianoDrawerOpen = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                        Image(systemName: "pianokeys")
                            .font(.system(size: 13))
                    }
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 14).padding(.vertical, 10)
                }

                // Instrument picker
                Menu {
                    ForEach(instruments, id: \.self) { name in
                        Button(name) { audioEngine.loadInstrumentNamed(name) }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(audioEngine.currentInstrumentName)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(appState.theme.accent)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(appState.theme.accent.opacity(0.12))
                        .overlay(Capsule().stroke(appState.theme.accent.opacity(0.35), lineWidth: 1)))
                }

                Spacer()

                // Octave jump — shows 1 (highest) to 7 (lowest)
                HStack(spacing: 2) {
                    Text("Oct:")
                        .font(.system(size: 10)).foregroundColor(.white.opacity(0.35))
                    ForEach(1...7, id: \.self) { oct in
                        Button("\(oct)") { jumpOctave = oct }
                            .font(.system(size: 11, weight: jumpOctave == oct ? .bold : .regular))
                            .foregroundColor(jumpOctave == oct ? appState.theme.accent : .white.opacity(0.4))
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(jumpOctave == oct ? appState.theme.accent.opacity(0.14) : .clear))
                    }
                }
                .padding(.trailing, 12)
            }
            .background(Color(hex: "#111118"))
            .overlay(Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1), alignment: .top)

            Divider().background(Color.white.opacity(0.08))

            // Keyboard — scroll, Octave 1 (high/treble) on RIGHT, Octave 7 (low/bass) on LEFT
            PianoKeyboardView(jumpOctave: $jumpOctave)
        }
        .background(Color(hex: "#0E0F1A"))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        // Drag-down to dismiss
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { val in
                    if val.translation.height > 60 {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                            appState.isPianoDrawerOpen = false
                        }
                    }
                }
        )
    }
}

// MARK: - Keyboard view
struct PianoKeyboardView: View {
    @Environment(AudioEngine.self) private var audioEngine
    @Environment(AppState.self)    private var appState
    @Binding var jumpOctave: Int

    // Layout constants
    private let wW: CGFloat = 36   // white key width
    private let wH: CGFloat = 115  // white key height
    private let bW: CGFloat = 22   // black key width
    private let bH: CGFloat = 70   // black key height
    private let gap: CGFloat = 1   // gap between whites

    // Piano range: octaves 7 (low, left) → 1 (high, right)
    // Standard 88-key: A0 (octave 7 in our numbering) to C8 (octave 1)
    // Our numbering: octave 1 = C5-B5 (highest area), octave 7 = C1-B1 (lowest area)
    // Actually per spec: octave 1 = highest treble (right), octave 7 = lowest bass (left)

    struct PianoKey: Identifiable {
        let id: Int          // sequential index
        let octave: Int      // 1..7 (1=highest)
        let pitchClass: PitchClass
        let isBlack: Bool
        let whiteIndex: Int  // position among white keys from left
        var midiNote: Int {
            // MIDI: C4 = 60, octave 1=highest maps to MIDI 6x
            // Reverse: our octave 1 = MIDI octave 5 (C5=72), octave 7 = MIDI octave 1 (C1=24)
            let midiOct = 8 - octave  // octave 1 → MIDI oct 7, octave 7 → MIDI oct 1
            return (midiOct + 1) * 12 + pitchClass.rawValue
        }
    }

    var keys: [PianoKey] {
        // Build from octave 7 (left/low) to octave 1 (right/high)
        let whites: [PitchClass] = [.C, .D, .E, .F, .G, .A, .B]
        let blacks: [PitchClass?] = [.Db, nil, .Eb, nil, nil, .Gb, nil, .Ab, nil, .Bb, nil, nil]
        var result: [PianoKey] = []
        var whiteIdx = 0
        var id = 0

        for oct in stride(from: 7, through: 1, by: -1) {
            for (i, wpc) in whites.enumerated() {
                result.append(PianoKey(id: id, octave: oct, pitchClass: wpc, isBlack: false, whiteIndex: whiteIdx))
                id += 1; whiteIdx += 1
            }
        }

        // Add black keys
        whiteIdx = 0
        for oct in stride(from: 7, through: 1, by: -1) {
            let blackPattern: [(PitchClass, Int)] = [(.Db, 0), (.Eb, 1), (.Gb, 3), (.Ab, 4), (.Bb, 5)]
            let base = whiteIdx
            for (pc, offset) in blackPattern {
                result.append(PianoKey(id: id, octave: oct, pitchClass: pc, isBlack: true, whiteIndex: base + offset))
                id += 1
            }
            whiteIdx += 7
        }
        return result
    }

    var whiteKeys: [PianoKey] { keys.filter { !$0.isBlack } }
    var blackKeys: [PianoKey] { keys.filter { $0.isBlack } }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    // White keys
                    HStack(spacing: gap) {
                        ForEach(whiteKeys) { key in
                            AWWhiteKey(key: key, width: wW, height: wH)
                                .id("w\(key.octave)\(key.pitchClass.rawValue)")
                        }
                    }
                    // Black keys overlaid
                    ForEach(blackKeys) { key in
                        AWBlackKey(key: key, width: bW, height: bH)
                            .offset(
                                x: CGFloat(key.whiteIndex) * (wW + gap) + (wW + gap) * 0.62,
                                y: 0
                            )
                    }
                }
                .frame(height: wH + 24)
                .padding(.horizontal, 6)
            }
            .onChange(of: jumpOctave) { _, oct in
                // Jump to the correct octave (remember: octave 1=right, octave 7=left)
                let pc = PitchClass.C.rawValue
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo("w\(oct)\(pc)", anchor: .center)
                }
            }
        }
    }
}

// MARK: - White Key
struct AWWhiteKey: View {
    @Environment(AudioEngine.self) private var audioEngine
    @Environment(AppState.self)    private var appState
    let key: PianoKeyboardView.PianoKey
    let width: CGFloat
    let height: CGFloat
    @State private var pressed = false

    var isMiddleC: Bool { key.pitchClass == .C && key.octave == 4 }

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(pressed ? appState.theme.accent.opacity(0.4) : Color.white)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.black.opacity(0.25), lineWidth: 0.5))
                .frame(width: width, height: height)

            VStack(spacing: 1) {
                if isMiddleC {
                    Circle().fill(appState.theme.accent).frame(width: 5, height: 5)
                    Text("C\(key.octave)")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(appState.theme.accent)
                } else if key.pitchClass == .C {
                    Text("\(key.octave)")
                        .font(.system(size: 7))
                        .foregroundColor(.black.opacity(0.4))
                }
            }
            .padding(.bottom, 5)
        }
        .scaleEffect(pressed ? 0.97 : 1.0)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !pressed {
                        pressed = true
                        let pitch = Pitch(pitchClass: key.pitchClass, octave: key.octave)
                        audioEngine.playPitch(pitch, duration: 0.5)
                    }
                }
                .onEnded { _ in pressed = false }
        )
        .animation(.easeOut(duration: 0.07), value: pressed)
    }
}

// MARK: - Black Key
struct AWBlackKey: View {
    @Environment(AudioEngine.self) private var audioEngine
    @Environment(AppState.self)    private var appState
    let key: PianoKeyboardView.PianoKey
    let width: CGFloat
    let height: CGFloat
    @State private var pressed = false

    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(pressed ? appState.theme.accent.opacity(0.7) : Color(white: 0.10))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.black.opacity(0.7), lineWidth: 0.5))
            .frame(width: width, height: height)
            .scaleEffect(pressed ? 0.96 : 1.0)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !pressed {
                            pressed = true
                            let pitch = Pitch(pitchClass: key.pitchClass, octave: key.octave)
                            audioEngine.playPitch(pitch, duration: 0.4)
                        }
                    }
                    .onEnded { _ in pressed = false }
            )
            .animation(.easeOut(duration: 0.05), value: pressed)
    }
}
