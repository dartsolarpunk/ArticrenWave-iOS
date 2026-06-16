// PlaybackView.swift — Playback bar + score position indicator
import SwiftUI

// MARK: - Playback Bar
struct PlaybackBarView: View {
    @Environment(AppState.self)    private var appState
    @Environment(ScoreEngine.self) private var scoreEngine
    private var audio: AWAudioPlayer { AWAudioPlayer.shared }
    @State private var isScrubbing = false
    @State private var scrubProg: Double = 0

    var displayProg: Double { isScrubbing ? scrubProg : audio.progress }
    var totalTime: String {
        let s = audio.totalBeats / Double(scoreEngine.document.tempo) * 60
        return String(format: "%d:%02d", Int(s)/60, Int(s)%60)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Scrubber track
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08)).frame(height: 3)
                    Capsule()
                        .fill(LinearGradient(colors: [appState.theme.accent, appState.theme.secondary],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * displayProg, height: 3)
                    Circle()
                        .fill(.white)
                        .frame(width: isScrubbing ? 14 : 9, height: isScrubbing ? 14 : 9)
                        .shadow(color: appState.theme.accent.opacity(0.5), radius: 5)
                        .offset(x: geo.size.width * displayProg - (isScrubbing ? 7 : 4.5))
                        .animation(.easeOut(duration: 0.08), value: isScrubbing)
                }
                .frame(height: 20)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        isScrubbing = true
                        scrubProg = max(0, min(1, v.location.x / geo.size.width))
                    }
                    .onEnded { _ in
                        audio.seek(to: scrubProg)
                        isScrubbing = false
                    }
                )
            }
            .frame(height: 20)
            .padding(.horizontal, 16)

            // Controls
            HStack(alignment: .center, spacing: 0) {
                // Time
                Text(audio.currentTimeString)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(width: 52, alignment: .leading)
                    .padding(.leading, 16)

                Spacer()

                // Transport
                HStack(spacing: 24) {
                    Button { audio.stop() } label: {
                        Image(systemName: "backward.end.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.65))
                    }

                    Button {
                        if audio.isPlaying { audio.pause() }
                        else { audio.play(document: scoreEngine.document) }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(
                                    colors: [appState.theme.accent, appState.theme.accent.opacity(0.7)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 44, height: 44)
                                .shadow(color: appState.theme.accent.opacity(0.45), radius: 8)
                            Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                                .offset(x: audio.isPlaying ? 0 : 1.5)
                        }
                    }

                    Button { audio.stop() } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.65))
                    }
                }

                Spacer()

                // Total time + BPM
                VStack(alignment: .trailing, spacing: 1) {
                    Text(totalTime)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                    Text("\(scoreEngine.document.tempo) BPM")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.25))
                }
                .frame(width: 52, alignment: .trailing)
                .padding(.trailing, 16)
            }
            .frame(height: 52)
        }
        .background(
            Color(hex: "#0C0D18")
                .overlay(Rectangle().fill(appState.theme.accent.opacity(0.04)))
        )
        .overlay(Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1), alignment: .top)
        .onAppear { audio.setup() }
    }
}

// MARK: - Score Playback Cursor (overlaid on the score canvas)
struct PlaybackCursorView: View {
    @Environment(AppState.self) private var appState
    private var audio: AWAudioPlayer { AWAudioPlayer.shared }

    let measureWidth: CGFloat
    let rowHeight: CGFloat
    let totalMeasures: Int

    var cursorX: CGFloat {
        guard totalMeasures > 0 else { return 0 }
        let totalBeats = Double(totalMeasures) * 4.0
        let progress   = audio.totalBeats > 0 ? audio.currentBeat / audio.totalBeats : 0
        return CGFloat(progress) * (measureWidth * CGFloat(totalMeasures))
    }

    var body: some View {
        if audio.isPlaying || audio.isPaused {
            Rectangle()
                .fill(appState.theme.accent.opacity(0.55))
                .frame(width: 1.5)
                .frame(maxHeight: .infinity)
                .offset(x: cursorX)
                .animation(.linear(duration: 0.05), value: audio.currentBeat)
        }
    }
}
