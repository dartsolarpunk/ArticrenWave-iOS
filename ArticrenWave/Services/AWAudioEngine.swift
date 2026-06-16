// AWAudioEngine.swift — Thread-safe audio playback
// @Observable state accessed only on MainActor; audio ops on audio queue
import AVFoundation
import Observation

struct AWInstrument {
    let name: String
    let midiProgram: UInt8
    static let all: [AWInstrument] = [
        .init(name: "Grand Piano",  midiProgram: 0),
        .init(name: "Violin",       midiProgram: 40),
        .init(name: "Viola",        midiProgram: 41),
        .init(name: "Cello",        midiProgram: 42),
        .init(name: "Double Bass",  midiProgram: 43),
        .init(name: "Flute",        midiProgram: 73),
        .init(name: "Oboe",         midiProgram: 68),
        .init(name: "Clarinet",     midiProgram: 71),
        .init(name: "Bassoon",      midiProgram: 70),
        .init(name: "French Horn",  midiProgram: 60),
        .init(name: "Trumpet",      midiProgram: 56),
        .init(name: "Trombone",     midiProgram: 57),
        .init(name: "Tuba",         midiProgram: 58),
        .init(name: "Harp",         midiProgram: 46),
        .init(name: "Timpani",      midiProgram: 47),
    ]
    static func find(_ name: String) -> AWInstrument {
        all.first { $0.name == name } ?? all[0]
    }
}

// MARK: - Scheduled note (value type — safe to pass across threads)
private struct ScheduledNote {
    let pitchClass: PitchClass
    let octave:     Int
    let startTime:  Double
    let duration:   Double
    let program:    UInt8
}

// MARK: - Audio Player
@Observable
@MainActor
class AWAudioPlayer {
    static let shared = AWAudioPlayer()

    // Playback progress (all on MainActor)
    var isPlaying:   Bool   = false
    var isPaused:    Bool   = false
    var currentBeat: Double = 0.0
    var totalBeats:  Double = 16.0

    var progress: Double { totalBeats > 0 ? currentBeat / totalBeats : 0 }
    var currentTimeString: String {
        guard totalBeats > 0 else { return "0:00.0" }
        let bpm   = _bpm > 0 ? _bpm : 80
        let secs  = (currentBeat / Double(bpm)) * 60.0
        return String(format: "%d:%04.1f", Int(secs)/60, secs.truncatingRemainder(dividingBy: 60))
    }

    // Private audio-thread state
    private var engine     = AVAudioEngine()
    private var sampler    = AVAudioUnitSampler()
    private var playerNode = AVAudioPlayerNode()
    private var isSetup    = false
    private var useSampler = false
    private var _bpm       = 80
    private var playTimer: Timer?
    private let audioQ     = DispatchQueue(label: "aw.audio", qos: .userInteractive)

    private init() {}

    // MARK: - Setup (call on main thread)
    func setup() {
        guard !isSetup else { return }
        isSetup = true

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { print("AVAudioSession: \(error)") }

        engine.attach(sampler)
        engine.attach(playerNode)
        engine.connect(sampler,     to: engine.mainMixerNode, format: nil)
        engine.connect(playerNode,  to: engine.mainMixerNode, format: nil)

        do { try engine.start() }
        catch { print("Engine: \(error)"); return }

        // Try system DLS soundfont
        for path in ["/System/Library/Audio/Sounds/Banks/gs_instruments.dls",
                     "/System/Library/Audio/Sounds/Banks/MacProDefault.dls"] {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            do {
                try sampler.loadSoundBankInstrument(
                    at: URL(fileURLWithPath: path), program: 0, bankMSB: 0x79, bankLSB: 0
                )
                useSampler = true
                break
            } catch { continue }
        }
        // Bundled SF2
        if !useSampler {
            for res in [("GeneralUser GS", "sf2"), ("soundfont", "sf2")] {
                if let url = Bundle.main.url(forResource: res.0, withExtension: res.1) {
                    try? sampler.loadSoundBankInstrument(at: url, program: 0, bankMSB: 0x79, bankLSB: 0)
                    useSampler = true; break
                }
            }
        }
    }

    // MARK: - Play single pitch (called from UI — main thread safe)
    func playPitch(_ pitch: Pitch, instrumentName: String = "Grand Piano", duration: Double = 0.5) {
        if !isSetup { setup() }
        let midi = UInt8(max(21, min(108, pitch.midiNote)))
        let prog = AWInstrument.find(instrumentName).midiProgram

        if useSampler {
            sampler.sendProgramChange(prog, bankMSB: 0x79, bankLSB: 0, onChannel: 0)
            sampler.startNote(midi, withVelocity: 90, onChannel: 0)
            // Stop after duration — on main thread is fine for UI-triggered notes
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                self.sampler.stopNote(midi, onChannel: 0)
            }
        } else {
            playSynthTone(midiNote: Int(midi), duration: duration, program: prog)
        }
    }

    // MARK: - Synthesized tone (main thread safe — scheduleBuffer is thread-safe)
    private func playSynthTone(midiNote: Int, duration: Double, program: UInt8) {
        guard engine.isRunning else { return }
        let sr   = 44100.0
        let fc   = Int(sr * duration)
        let freq = 440.0 * pow(2.0, (Double(midiNote) - 69.0) / 12.0)
        let fmt  = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
        guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(fc)),
              let ptr = buf.floatChannelData?[0] else { return }
        buf.frameLength = AVAudioFrameCount(fc)

        audioQ.async {
            for i in 0..<fc {
                let t   = Double(i) / sr
                let env = min(1.0, t * 20) * max(0, 1.0 - t / duration)
                let s: Double
                switch program {
                case 40...43:
                    let ph = (freq * t).truncatingRemainder(dividingBy: 1.0)
                    s = (2*ph - 1) * env
                case 56...75:
                    let ph = (freq * t).truncatingRemainder(dividingBy: 1.0)
                    s = (ph < 0.5 ? 1.0 : -1.0) * env * 0.7
                default:
                    let d = exp(-t * 4.0)
                    s = (sin(2 * .pi * freq * t)
                       + sin(2 * .pi * freq * 2 * t) * 0.35
                       + sin(2 * .pi * freq * 3 * t) * 0.12) * d * 0.5
                }
                ptr[i] = Float(s * 0.4)
            }
            DispatchQueue.main.async {
                if !self.playerNode.isPlaying { self.playerNode.play() }
                self.playerNode.scheduleBuffer(buf, completionHandler: nil)
            }
        }
    }

    // MARK: - Score playback
    // MUST be called on MainActor — extracts notes from @Observable document here
    func play(document: ScoreDocument) {
        if !isSetup { setup() }
        guard !isPlaying || isPaused else { return }
        if !isPaused { currentBeat = 0 }
        isPlaying = true
        isPaused  = false
        _bpm      = document.tempo

        totalBeats = Double(max(1, document.parts.first?.measures.count ?? 4)) * 4.0

        // Extract notes here on MainActor (safe to read @Observable)
        let notes = extractNotes(from: document)
        let bpmD  = Double(document.tempo)
        let sixteenth = 60.0 / bpmD / 4.0

        // Schedule note playback via audioQ (notes are value types — safe to pass)
        audioQ.async { [weak self] in
            guard let self else { return }
            for note in notes {
                self.audioQ.asyncAfter(deadline: .now() + note.startTime) {
                    DispatchQueue.main.async {
                        guard self.isPlaying else { return }
                        let pitch = Pitch(pitchClass: note.pitchClass, octave: note.octave)
                        let name  = AWInstrument.all.first { $0.midiProgram == note.program }?.name ?? "Grand Piano"
                        self.playPitch(pitch, instrumentName: name, duration: note.duration)
                    }
                }
            }
        }

        // Advance scrubber on main thread via Timer
        playTimer?.invalidate()
        playTimer = Timer.scheduledTimer(withTimeInterval: sixteenth, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.currentBeat += 0.25
            if self.currentBeat >= self.totalBeats { self.stop() }
        }
    }

    func pause() {
        playTimer?.invalidate(); playTimer = nil
        isPaused = true; isPlaying = false
    }

    func stop() {
        playTimer?.invalidate(); playTimer = nil
        isPlaying = false; isPaused = false; currentBeat = 0
    }

    func seek(to progress: Double) {
        currentBeat = progress * totalBeats
    }

    // MARK: - Note extraction (MainActor — reads @Observable safely)
    private func extractNotes(from doc: ScoreDocument) -> [ScheduledNote] {
        var events: [ScheduledNote] = []
        let beatDur = 60.0 / Double(doc.tempo)

        for part in doc.parts {
            let prog = AWInstrument.find(part.instrument.rawValue).midiProgram
            var beat = 0.0

            for measure in part.measures {
                for content in measure.contents {
                    switch content {
                    case .chord(let chord):
                        let t = beat * beatDur
                        let d = chord.totalBeats * beatDur * 0.88
                        for note in chord.notes {
                            events.append(ScheduledNote(
                                pitchClass: note.pitch.pitchClass,
                                octave:     note.pitch.octave,
                                startTime:  t,
                                duration:   d,
                                program:    prog
                            ))
                        }
                        beat += chord.totalBeats
                    case .rest(let rest):
                        beat += rest.duration.beats
                    }
                }
            }
        }
        return events.sorted { $0.startTime < $1.startTime }
    }

    // MARK: - MIDI export
    func buildMIDI(from document: ScoreDocument) -> Data {
        let bpm = document.tempo; let ticks = 480
        var tracks: [Data] = []
        let mspb = 60_000_000 / bpm
        tracks.append(Data([0x00,0xFF,0x51,0x03,
                             UInt8((mspb>>16)&0xFF),UInt8((mspb>>8)&0xFF),UInt8(mspb&0xFF),
                             0x00,0xFF,0x2F,0x00]))

        for (pi, part) in document.parts.enumerated() {
            var t = Data()
            let ch = UInt8(min(pi, 14))
            let prog = AWInstrument.find(part.instrument.rawValue).midiProgram
            t += delta(0) + [0xC0|ch, prog]
            for measure in part.measures {
                for content in measure.contents {
                    switch content {
                    case .chord(let chord):
                        let dur = Int(chord.totalBeats * Double(ticks))
                        for note in chord.notes {
                            let m = UInt8(max(21,min(108,note.pitch.midiNote)))
                            t += delta(0) + [0x90|ch, m, 90]
                        }
                        for note in chord.notes {
                            let m = UInt8(max(21,min(108,note.pitch.midiNote)))
                            t += delta(dur) + [0x80|ch, m, 0]
                        }
                    case .rest(let rest):
                        let _ = Int(rest.duration.beats * Double(ticks))
                    }
                }
            }
            t += delta(0) + [0xFF,0x2F,0x00]
            tracks.append(t)
        }

        var midi = Data()
        midi += [0x4D,0x54,0x68,0x64,0,0,0,6,0,1]
        let n = UInt16(tracks.count)
        midi += [UInt8(n>>8),UInt8(n&0xFF),UInt8(ticks>>8),UInt8(ticks&0xFF)]
        for t in tracks {
            midi += [0x4D,0x54,0x72,0x6B]
            let l = UInt32(t.count)
            midi += [UInt8(l>>24),UInt8(l>>16&0xFF),UInt8(l>>8&0xFF),UInt8(l&0xFF)]
            midi += t
        }
        return midi
    }

    private func delta(_ ticks: Int) -> Data {
        var v=ticks; var b=[UInt8]()
        b.append(UInt8(v&0x7F)); v>>=7
        while v>0 { b.insert(UInt8((v&0x7F)|0x80),at:0); v>>=7 }
        return Data(b)
    }

    func exportWAV(document: ScoreDocument, completion: @escaping (URL?) -> Void) {
        let midiData = buildMIDI(from: document)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(document.title + ".mid")
        try? midiData.write(to: url)
        completion(url)
    }

    func exportM4A(wavURL: URL, completion: @escaping (URL?) -> Void) { completion(nil) }
}
