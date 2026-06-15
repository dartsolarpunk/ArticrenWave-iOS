// PlaybackView.swift — Score playback controls with scrubber
import SwiftUI

@Observable
class PlaybackEngine {
    var isPlaying: Bool  = false
    var isPaused: Bool   = false
    var currentBeat: Double = 0.0
    var totalBeats: Double  = 16.0
    var bpm: Int = 80

    static let shared = PlaybackEngine()
    private var timer: Timer? = nil

    var progress: Double {
        guard totalBeats > 0 else { return 0 }
        return currentBeat / totalBeats
    }

    var currentTimeString: String {
        let seconds = (currentBeat / Double(bpm)) * 60.0
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        let ms = Int((seconds - Double(Int(seconds))) * 10)
        return String(format: "%d:%02d.%d", m, s, ms)
    }

    var totalTimeString: String {
        let seconds = (totalBeats / Double(bpm)) * 60.0
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }

    func play(document: ScoreDocument) {
        guard !isPlaying || isPaused else { return }
        if !isPaused { currentBeat = 0 }
        isPlaying = true
        isPaused = false

        // Calculate total beats
        totalBeats = Double(document.parts.first?.measures.count ?? 4) * 4.0
        totalBeats = max(totalBeats, 4.0)
        bpm = document.tempo

        let interval = 60.0 / Double(bpm) / 4.0  // sixteenth note intervals
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            self.currentBeat += 0.25
            if self.currentBeat >= self.totalBeats {
                self.stop()
            }
        }
    }

    func pause() {
        timer?.invalidate()
        timer = nil
        isPaused = true
        isPlaying = false
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isPlaying = false
        isPaused = false
        currentBeat = 0
    }

    func seek(to progress: Double) {
        currentBeat = progress * totalBeats
    }
}

// MARK: - Playback Bar View
struct PlaybackBarView: View {
    @Environment(AppState.self)    private var appState
    @Environment(ScoreEngine.self) private var scoreEngine
    @State private var engine = PlaybackEngine.shared
    @State private var isScrubbing = false
    @State private var scrubProgress: Double = 0

    var displayProgress: Double { isScrubbing ? scrubProgress : engine.progress }

    var body: some View {
        VStack(spacing: 0) {
            // Scrubber track
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track background
                    Capsule()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 3)

                    // Progress fill
                    Capsule()
                        .fill(
                            LinearGradient(colors: [appState.theme.accent, appState.theme.secondary],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: geo.size.width * displayProgress, height: 3)

                    // Scrub thumb
                    Circle()
                        .fill(Color.white)
                        .frame(width: isScrubbing ? 14 : 10, height: isScrubbing ? 14 : 10)
                        .shadow(color: appState.theme.accent.opacity(0.6), radius: 4)
                        .offset(x: geo.size.width * displayProgress - (isScrubbing ? 7 : 5))
                        .animation(.easeOut(duration: 0.1), value: isScrubbing)
                }
                .frame(height: 20)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { val in
                            isScrubbing = true
                            scrubProgress = max(0, min(1, val.location.x / geo.size.width))
                        }
                        .onEnded { _ in
                            engine.seek(to: scrubProgress)
                            isScrubbing = false
                        }
                )
            }
            .frame(height: 20)
            .padding(.horizontal, 16)

            // Controls row
            HStack(alignment: .center, spacing: 0) {
                // Time display
                Text(engine.currentTimeString)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))
                    .frame(width: 52, alignment: .leading)
                    .padding(.leading, 16)

                Spacer()

                // Transport buttons
                HStack(spacing: 28) {
                    // Rewind to start
                    Button {
                        engine.stop()
                    } label: {
                        Image(systemName: "backward.end.fill")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }

                    // Play / Pause
                    Button {
                        if engine.isPlaying {
                            engine.pause()
                        } else {
                            engine.play(document: scoreEngine.document)
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [appState.theme.accent, appState.theme.accent.opacity(0.7)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 42, height: 42)
                                .shadow(color: appState.theme.accent.opacity(0.4), radius: 8)

                            Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                                .offset(x: engine.isPlaying ? 0 : 1.5)
                        }
                    }

                    // Stop
                    Button {
                        engine.stop()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }

                Spacer()

                // Total time + BPM
                VStack(alignment: .trailing, spacing: 1) {
                    Text(engine.totalTimeString)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.45))
                    Text("\(scoreEngine.document.tempo) BPM")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.28))
                }
                .frame(width: 52, alignment: .trailing)
                .padding(.trailing, 16)
            }
            .frame(height: 52)
        }
        .background(
            Color(hex: "#0C0D18")
                .overlay(
                    Rectangle()
                        .fill(appState.theme.accent.opacity(0.05))
                )
        )
        .overlay(Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1), alignment: .top)
    }
}
