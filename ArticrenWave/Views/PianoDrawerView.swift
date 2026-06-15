// PianoDrawerView.swift — 88-key piano, string-based instrument switching
import SwiftUI

struct PianoDrawerView: View {
    @Environment(AppState.self)    private var appState
    @Environment(AudioEngine.self) private var audioEngine
    @Environment(ScoreEngine.self) private var scoreEngine
    @State private var jumpOctave: Int = 4

    let instruments = ["Grand Piano","Violin","Viola","Cello",
                       "Flute","Oboe","Clarinet","Trumpet","French Horn","Harp"]

    var body: some View {
        VStack(spacing: 0) {
            // Handle
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.2))
                .frame(width: 36, height: 4)
                .padding(.top, 8)
                .padding(.bottom, 4)

            // Header
            HStack(spacing: 12) {
                Menu {
                    ForEach(instruments, id: \.self) { name in
                        Button(name) { audioEngine.loadInstrumentNamed(name) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "music.note.list").font(.system(size: 12))
                        Text(audioEngine.currentInstrumentName)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                        Image(systemName: "chevron.down").font(.system(size: 9))
                    }
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(appState.theme.accent.opacity(0.15))
                        .overlay(Capsule().stroke(appState.theme.accent.opacity(0.4), lineWidth: 1)))
                }

                Spacer()

                Text("Jump:").font(.system(size: 11)).foregroundColor(.white.opacity(0.4))

                ForEach(1...7, id: \.self) { oct in
                    Button("\(oct)") { jumpOctave = oct }
                        .font(.system(size: 12, weight: jumpOctave == oct ? .bold : .regular))
                        .foregroundColor(jumpOctave == oct ? appState.theme.accent : .white.opacity(0.5))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(jumpOctave == oct ? appState.theme.accent.opacity(0.15) : .clear))
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider().background(Color.white.opacity(0.1))

            // Keyboard
            PianoScrollView(jumpOctave: $jumpOctave)
        }
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(hex: "#111118"))
            .shadow(color: .black.opacity(0.5), radius: 20, y: -4))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

struct PianoScrollView: View {
    @Environment(AudioEngine.self) private var audioEngine
    @Environment(ScoreEngine.self) private var scoreEngine
    @Environment(AppState.self)    private var appState
    @Binding var jumpOctave: Int

    private let whiteW: CGFloat = 34
    private let whiteH: CGFloat = 110
    private let blackW: CGFloat = 22
    private let blackH: CGFloat = 68

    // White keys: C1-C8
    private var whiteKeys: [(PitchClass, Int)] {
        var keys: [(PitchClass, Int)] = []
        let whites: [PitchClass] = [.C,.D,.E,.F,.G,.A,.B]
        for oct in 1...7 { for pc in whites { keys.append((pc, oct)) } }
        keys.append((.C, 8))
        return keys
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 1) {
                        ForEach(Array(whiteKeys.enumerated()), id: \.offset) { idx, key in
                            AWPianoWhiteKey(
                                pitch: Pitch(pitchClass: key.0, octave: key.1),
                                width: whiteW, height: whiteH,
                                isMiddleC: key.0 == .C && key.1 == 4,
                                octaveLabel: key.0 == .C ? "\(key.1)" : nil
                            )
                            .id("w-\(key.1)-\(key.0.rawValue)")
                        }
                    }

                    // Black keys
                    let blackPositions: [(PitchClass, Int, Int)] = {
                        var keys: [(PitchClass, Int, Int)] = []
                        let blacks: [(PitchClass, Int)] = [(.Db,0),(.Eb,1),(.Gb,3),(.Ab,4),(.Bb,5)]
                        for oct in 1...7 {
                            let base = (oct-1)*7
                            for (pc, off) in blacks { keys.append((pc, oct, base+off)) }
                        }
                        return keys
                    }()

                    ForEach(Array(blackPositions.enumerated()), id: \.offset) { _, key in
                        AWPianoBlackKey(
                            pitch: Pitch(pitchClass: key.0, octave: key.1),
                            width: blackW, height: blackH
                        )
                        .offset(x: CGFloat(key.2) * (whiteW+1) + (whiteW+1)*0.6)
                    }
                }
                .frame(height: whiteH + 20)
                .padding(.horizontal, 4)
            }
            .onChange(of: jumpOctave) { _, oct in
                guard oct >= 1 && oct <= 7 else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo("w-\(oct)-0", anchor: .leading)
                }
            }
        }
    }
}

struct AWPianoWhiteKey: View {
    @Environment(AudioEngine.self) private var audioEngine
    @Environment(AppState.self)    private var appState
    let pitch: Pitch
    let width: CGFloat
    let height: CGFloat
    let isMiddleC: Bool
    var octaveLabel: String? = nil
    @State private var pressed = false

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 4)
                .fill(pressed ? appState.theme.accent.opacity(0.35) : .white)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.black.opacity(0.3), lineWidth: 1))
                .frame(width: width, height: height)

            VStack(spacing: 2) {
                if isMiddleC {
                    Circle().fill(appState.theme.accent).frame(width: 6, height: 6)
                    Text("C4").font(.system(size: 6, weight: .bold)).foregroundColor(appState.theme.accent)
                } else if let label = octaveLabel {
                    Text(label).font(.system(size: 7)).foregroundColor(.black.opacity(0.4))
                }
            }.padding(.bottom, 6)
        }
        .scaleEffect(pressed ? 0.97 : 1.0)
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if !pressed {
                    pressed = true
                    audioEngine.playPitch(pitch)
                }
            }
            .onEnded { _ in pressed = false }
        )
        .animation(.easeOut(duration: 0.08), value: pressed)
    }
}

struct AWPianoBlackKey: View {
    @Environment(AudioEngine.self) private var audioEngine
    @Environment(AppState.self)    private var appState
    let pitch: Pitch
    let width: CGFloat
    let height: CGFloat
    @State private var pressed = false

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(pressed ? appState.theme.accent.opacity(0.7) : Color(white: 0.12))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.black.opacity(0.6), lineWidth: 0.5))
            .frame(width: width, height: height)
            .scaleEffect(pressed ? 0.96 : 1.0)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if !pressed { pressed = true; audioEngine.playPitch(pitch) } }
                .onEnded { _ in pressed = false }
            )
            .animation(.easeOut(duration: 0.06), value: pressed)
    }
}
