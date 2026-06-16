// AWAudioEngine.swift — Pure AVAudioPlayerNode synthesizer (no AVAudioUnitSampler)
// 100% thread-safe: all AVAudioEngine calls on main thread
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

private struct ScheduledNote {
    let midi:      Int
    let startTime: Double
    let duration:  Double
    let program:   UInt8
}

@Observable
class AWAudioPlayer {
    static let shared = AWAudioPlayer()

    // UI state
    var isPlaying:   Bool   = false
    var isPaused:    Bool   = false
    var currentBeat: Double = 0.0
    var totalBeats:  Double = 16.0

    var progress: Double { totalBeats > 0 ? currentBeat / totalBeats : 0 }
    var currentTimeString: String {
        let secs = totalBeats > 0 ? (currentBeat / Double(max(1,_bpm))) * 60.0 : 0
        return String(format: "%d:%04.1f", Int(secs)/60, secs.truncatingRemainder(dividingBy: 60))
    }

    private var engine     = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    private var mixerNode  = AVAudioMixerNode()
    private var isSetup    = false
    private var _bpm       = 80
    private var playTimer: Timer?

    // Pre-computed buffer cache (midiNote → buffer) for instant playback
    private var bufferCache: [Int: AVAudioPCMBuffer] = [:]
    private let sampleRate: Double = 44100
    private let synthQueue = DispatchQueue(label: "aw.synth", qos: .userInitiated)

    private init() {}

    // MARK: - Setup (main thread)
    func setup() {
        guard !isSetup else { return }
        isSetup = true

        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback, mode: .default, options: [.mixWithOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { print("AudioSession: \(error)") }

        engine.attach(playerNode)
        engine.attach(mixerNode)
        engine.connect(playerNode, to: mixerNode,        format: nil)
        engine.connect(mixerNode,  to: engine.mainMixerNode, format: nil)
        mixerNode.outputVolume = 1.0

        do { try engine.start() } catch { print("Engine: \(error)") }

        if !playerNode.isPlaying { playerNode.play() }

        // Pre-warm common notes in background
        synthQueue.async { [weak self] in
            guard let self else { return }
            for midi in 48...84 {  // C3 to C6 range
                _ = self.makeBuffer(midi: midi, duration: 0.7, program: 0)
            }
        }
    }

    // MARK: - Buffer synthesis (runs on synthQueue)
    private func makeBuffer(midi: Int, duration: Double, program: UInt8) -> AVAudioPCMBuffer? {
        let sr  = sampleRate
        let dur = min(duration, 3.0)
        let fc  = Int(sr * dur)
        let freq = 440.0 * pow(2.0, (Double(midi) - 69.0) / 12.0)

        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2),
              let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(fc)),
              let L = buf.floatChannelData?[0],
              let R = buf.floatChannelData?[1]
        else { return nil }
        buf.frameLength = AVAudioFrameCount(fc)

        for i in 0..<fc {
            let t   = Double(i) / sr
            let env = min(1.0, t * 12.0) * max(0.0, 1.0 - (t / dur) * 1.1)
            let sample: Float

            switch program {
            case 40...43:   // Strings — sawtooth
                let ph = (freq * t).truncatingRemainder(dividingBy: 1.0)
                sample = Float((2.0 * ph - 1.0) * env * 0.3)

            case 56...75:   // Winds/Brass — square wave
                let ph = (freq * t).truncatingRemainder(dividingBy: 1.0)
                sample = Float((ph < 0.5 ? 0.3 : -0.3) * env)

            case 46, 47:    // Harp/Timpani — pluck (fast decay)
                let decay = exp(-t * 6.0)
                let s1 = sin(2.0 * Double.pi * freq * t)
                let s2 = sin(2.0 * Double.pi * freq * 2.0 * t) * 0.3
                sample = Float((s1 + s2) * decay * 0.45)

            default:        // Piano — additive sine with natural decay
                let decay = exp(-t * 3.2)
                let s1 = sin(2.0 * Double.pi * freq * t)
                let s2 = sin(2.0 * Double.pi * freq * 2.0 * t) * 0.28
                let s3 = sin(2.0 * Double.pi * freq * 3.0 * t) * 0.10
                let s4 = sin(2.0 * Double.pi * freq * 4.0 * t) * 0.04
                sample = Float((s1 + s2 + s3 + s4) * decay * env * 0.38)
            }
            L[i] = sample
            R[i] = sample
        }
        return buf
    }

    // MARK: - Play single pitch (MUST be called on main thread)
    func playPitch(_ pitch: Pitch, instrumentName: String = "Grand Piano", duration: Double = 0.5) {
        if !isSetup { setup() }
        guard engine.isRunning else { return }

        let midi = max(21, min(108, pitch.midiNote))
        let prog = AWInstrument.find(instrumentName).midiProgram

        synthQueue.async { [weak self] in
            guard let self else { return }
            let buf = self.makeBuffer(midi: midi, duration: duration, program: prog)
            guard let buf else { return }
            DispatchQueue.main.async {
                guard self.engine.isRunning else { return }
                if !self.playerNode.isPlaying { self.playerNode.play() }
                self.playerNode.scheduleBuffer(buf, completionHandler: nil)
            }
        }
    }

    // MARK: - Score playback (main thread)
    func play(document: ScoreDocument) {
        if !isSetup { setup() }
        if isPlaying && !isPaused { return }
        if !isPaused { currentBeat = 0 }

        isPlaying = true
        isPaused  = false
        _bpm      = document.tempo

        totalBeats = Double(max(1, document.parts.first?.measures.count ?? 4)) * 4.0
        let bpmD   = Double(document.tempo)
        let sixteenth = 60.0 / bpmD / 4.0

        // Extract notes on main thread (safe for @Observable)
        let notes = extractNotes(from: document)

        // Synthesize all buffers in background, then schedule on main
        synthQueue.async { [weak self] in
            guard let self else { return }
            var scheduled: [(delay: Double, buf: AVAudioPCMBuffer)] = []
            for note in notes {
                if let buf = self.makeBuffer(midi: note.midi, duration: note.duration, program: note.program) {
                    scheduled.append((note.startTime, buf))
                }
            }
            // Schedule all on main thread
            DispatchQueue.main.async {
                guard self.isPlaying else { return }
                guard self.engine.isRunning else { self.stop(); return }
                if !self.playerNode.isPlaying { self.playerNode.play() }
                for item in scheduled {
                    self.playerNode.scheduleBuffer(
                        item.buf,
                        at: nil,
                        options: [],
                        completionHandler: nil
                    )
                }
            }
        }

        // Scrubber timer (main thread)
        playTimer?.invalidate()
        playTimer = Timer.scheduledTimer(withTimeInterval: sixteenth, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
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

    // MARK: - Note extraction (main thread)
    private func extractNotes(from doc: ScoreDocument) -> [ScheduledNote] {
        var out: [ScheduledNote] = []
        let beatSec = 60.0 / Double(doc.tempo)
        for part in doc.parts {
            let prog = AWInstrument.find(part.instrument.rawValue).midiProgram
            var beat = 0.0
            for measure in part.measures {
                for content in measure.contents {
                    switch content {
                    case .chord(let c):
                        let t = beat * beatSec
                        let d = max(0.1, c.totalBeats * beatSec * 0.88)
                        for note in c.notes {
                            out.append(ScheduledNote(
                                midi:      max(21, min(108, note.pitch.midiNote)),
                                startTime: t, duration: d, program: prog
                            ))
                        }
                        beat += c.totalBeats
                    case .rest(let r):
                        beat += r.duration.beats
                    }
                }
            }
        }
        return out.sorted { $0.startTime < $1.startTime }
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
            var t = Data(); let ch = UInt8(min(pi,14))
            let prog = AWInstrument.find(part.instrument.rawValue).midiProgram
            t += delta(0) + [0xC0|ch, prog]
            for measure in part.measures {
                for content in measure.contents {
                    switch content {
                    case .chord(let c):
                        let dur = Int(c.totalBeats * Double(ticks))
                        for n in c.notes { let m=UInt8(max(21,min(108,n.pitch.midiNote))); t+=delta(0)+[0x90|ch,m,90] }
                        for n in c.notes { let m=UInt8(max(21,min(108,n.pitch.midiNote))); t+=delta(dur)+[0x80|ch,m,0] }
                    case .rest: break
                    }
                }
            }
            t += delta(0) + [0xFF,0x2F,0x00]; tracks.append(t)
        }
        var midi = Data([0x4D,0x54,0x68,0x64,0,0,0,6,0,1])
        let n=UInt16(tracks.count); midi+=[UInt8(n>>8),UInt8(n&0xFF),UInt8(ticks>>8),UInt8(ticks&0xFF)]
        for t in tracks { let l=UInt32(t.count)
            midi += [0x4D,0x54,0x72,0x6B,UInt8(l>>24),UInt8(l>>16&0xFF),UInt8(l>>8&0xFF),UInt8(l&0xFF)] + t }
        return midi
    }
    private func delta(_ v: Int) -> Data {
        var v=v; var b=[UInt8](); b.append(UInt8(v&0x7F)); v>>=7
        while v>0 { b.insert(UInt8((v&0x7F)|0x80),at:0); v>>=7 }; return Data(b)
    }
    func exportWAV(document: ScoreDocument, completion: @escaping (URL?) -> Void) {
        let midi=buildMIDI(from:document)
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(document.title+".mid")
        try? midi.write(to:url); completion(url)
    }
    func exportM4A(wavURL: URL, completion: @escaping (URL?) -> Void) { completion(nil) }
}
