// AWAudioEngine.swift — AVAudioEngine with synthesized instruments
// All AVAudio calls on MainActor / main thread only
// Sound design based on additive synthesis per instrument type
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
    let isTied:    Bool
}

@Observable
class AWAudioPlayer {
    static let shared = AWAudioPlayer()

    var isPlaying:   Bool   = false
    var isPaused:    Bool   = false
    var currentBeat: Double = 0.0
    var totalBeats:  Double = 16.0

    var progress: Double { totalBeats > 0 ? currentBeat / totalBeats : 0 }
    var currentTimeString: String {
        let s = totalBeats > 0 ? (currentBeat / Double(max(1,_bpm))) * 60.0 : 0
        return String(format: "%d:%04.1f", Int(s)/60, s.truncatingRemainder(dividingBy: 60))
    }

    // Audio nodes — only touched on main thread
    private var engine     = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()   // legacy alias (voice 0)
    private var voices: [AVAudioPlayerNode] = []   // polyphonic pool — no queue-behind latency
    private var vIdx = 0

    private func nextVoice() -> AVAudioPlayerNode {
        guard !voices.isEmpty else { return playerNode }
        vIdx = (vIdx + 1) % voices.count
        return voices[vIdx]
    }
    private var reverbNode = AVAudioUnitReverb()
    private var isSetup    = false
    private var _bpm       = 80
    private var playTimer: Timer?
    private let sr: Double = 44100

    // Buffer cache: key = (midi << 8 | program)
    private var bufCache: [Int: AVAudioPCMBuffer] = [:]
    private let synthQ = DispatchQueue(label: "aw.synth", qos: .userInitiated)

    private init() {}

    private let cacheLock = NSLock()

    // MARK: - Setup (main thread only) — resilient, retries until engine runs
    func setup() {
        if isSetup { ensureRunning(); return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { print("Session: \(error)") }
        reverbNode.loadFactoryPreset(.mediumHall)
        reverbNode.wetDryMix = 12
        engine.attach(reverbNode)
        engine.connect(reverbNode, to: engine.mainMixerNode, format: nil)
        // 8-voice polyphonic pool: each key press gets its own node → instant, overlapping notes
        voices = (0..<8).map { _ in AVAudioPlayerNode() }
        playerNode = voices[0]
        for v in voices {
            engine.attach(v)
            engine.connect(v, to: reverbNode, format: nil)
        }
        do { try engine.start() } catch { print("Engine: \(error)"); return }
        for v in voices where !v.isPlaying { v.play() }
        isSetup = true   // only after successful start
        // Pre-warm full piano range for instant key response
        synthQ.async { [weak self] in
            guard let self else { return }
            for m in 21...108 { _ = self.buildBuf(midi: m, dur: 0.8, prog: 0) }
        }
    }

    // MARK: - Synthesize PCM buffer (background)
    /// Restart engine/session if iOS suspended them (app init, interruptions, route changes)
    private func ensureRunning() {
        if !engine.isRunning {
            try? AVAudioSession.sharedInstance().setActive(true)
            try? engine.start()
        }
        if engine.isRunning {
            for v in voices where !v.isPlaying { v.play() }
        }
    }

    func buildBuf(midi: Int, dur: Double, prog: UInt8) -> AVAudioPCMBuffer? {
        let key = (midi << 8) | Int(prog)
        cacheLock.lock()
        if let cached = bufCache[key] { cacheLock.unlock(); return cached }
        cacheLock.unlock()
        let fc   = Int(sr * min(dur + 0.1, 3.5))
        let freq = 440.0 * pow(2.0, (Double(midi) - 69.0) / 12.0)
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2),
              let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(fc)),
              let L = buf.floatChannelData?[0], let R = buf.floatChannelData?[1]
        else { return nil }
        buf.frameLength = AVAudioFrameCount(fc)

        let maxDur = dur
        for i in 0..<fc {
            let t   = Double(i) / sr
            let env = min(1.0, t * 18.0) * max(0.0, 1.0 - (t / maxDur) * 1.05)
            var s: Double

            switch prog {
            case 40...43:   // Strings — warm sawtooth + chorus
                let ph  = (freq * t).truncatingRemainder(dividingBy: 1.0)
                let ph2 = (freq * 1.004 * t).truncatingRemainder(dividingBy: 1.0)
                s = ((2*ph-1)*0.5 + (2*ph2-1)*0.5) * env * 0.28

            case 56...60:   // Brass — bright sawtooth + harmonic
                let ph = (freq * t).truncatingRemainder(dividingBy: 1.0)
                let brassy = (2*ph-1) + sin(2*Double.pi*freq*2*t)*0.3
                s = brassy * env * 0.22

            case 68...73:   // Woodwinds — flute-like sine + breathiness
                let flute  = sin(2*Double.pi*freq*t)
                let breath = sin(2*Double.pi*freq*2*t)*0.12 + sin(2*Double.pi*freq*3*t)*0.04
                s = (flute + breath) * env * 0.32

            case 46:        // Harp — pluck with fast decay
                let decay = exp(-t * 8.0)
                let lowH  = freq < 131.0 ? 0.45 : 0.25
                let f1g   = freq < 131.0 ? 0.55 : 1.0
                s = (sin(2*Double.pi*freq*t)*f1g + sin(2*Double.pi*freq*2*t)*lowH
                   + sin(2*Double.pi*freq*3*t)*(lowH*0.5)) * decay * 0.45

            case 47:        // Timpani — pitched noise + thump
                let tump  = sin(2*Double.pi*freq*t) * exp(-t*5.0)
                let noise = sin(2*Double.pi*freq*0.71*t) * exp(-t*12.0) * 0.3
                s = (tump + noise) * 0.5

            default:        // Piano — detuned unison strings + hammer transient
                let d1 = exp(-t * 2.6)
                let d2 = exp(-t * 4.2)
                let d3 = exp(-t * 6.8)
                let d4 = exp(-t * 11.0)
                // Phone speakers can't reproduce fundamentals below ~130Hz.
                // For low notes, shift energy into harmonics (missing-fundamental effect
                // lets the ear still hear the correct low pitch).
                let lowBoost = freq < 131.0 ? min(1.0, (131.0 - freq) / 100.0) : 0.0
                let f1Gain = 1.0 - lowBoost * 0.65
                let h2Gain = 0.34 + lowBoost * 0.55
                let h3Gain = 0.13 + lowBoost * 0.40
                let h4Gain = 0.05 + lowBoost * 0.25
                // Real pianos have 2-3 slightly detuned strings per note
                let u1 = sin(2*Double.pi*freq*t)
                let u2 = sin(2*Double.pi*freq*1.0015*t)
                let u3 = sin(2*Double.pi*freq*0.9985*t)
                let p1 = (u1 + u2*0.7 + u3*0.7) / 2.4 * d1 * f1Gain
                let p2 = sin(2*Double.pi*freq*2.001*t) * d2 * h2Gain
                let p3 = sin(2*Double.pi*freq*3.003*t) * d3 * h3Gain
                let p4 = sin(2*Double.pi*freq*4.006*t) * d4 * h4Gain
                // Hammer strike transient (first ~30ms)
                let hammer = t < 0.03 ? sin(2*Double.pi*freq*6.2*t) * exp(-t*90) * 0.25 : 0
                s = (p1 + p2 + p3 + p4 + hammer) * env * 0.42
            }

            // Stereo spread based on octave
            let spread = Float(0.1 + Double(midi - 21) / 87.0 * 0.8)
            L[i] = Float(s) * (1.0 - spread * 0.15)
            R[i] = Float(s) * (1.0 + spread * 0.15)
        }
        cacheLock.lock(); bufCache[key] = buf; cacheLock.unlock()
        return buf
    }

    // MARK: - Play single pitch (call from main thread)
    func playPitch(_ pitch: Pitch, instrumentName: String = "Grand Piano", duration: Double = 0.5) {
        setup()
        let midi = max(21, min(108, pitch.midiNote))
        let prog = AWInstrument.find(instrumentName).midiProgram
        let key  = (midi << 8) | Int(prog)
        ensureRunning()
        guard engine.isRunning else { return }

        // INSTANT path: cached buffer schedules with zero latency
        cacheLock.lock()
        let cachedBuf = bufCache[key]
        cacheLock.unlock()
        if let cached = cachedBuf {
            let v = nextVoice()
            if !v.isPlaying { v.play() }
            v.scheduleBuffer(cached)          // fresh voice → plays NOW, mixes with others
            return
        }
        // Cold path: synth in background then play
        synthQ.async { [weak self] in
            guard let self else { return }
            let buf = self.buildBuf(midi: midi, dur: duration, prog: prog)
            DispatchQueue.main.async {
                guard let buf, self.engine.isRunning else { return }
                let v = self.nextVoice()
                if !v.isPlaying { v.play() }
                v.scheduleBuffer(buf)
            }
        }
    }

    /// Pre-warm the FULL 88-key range for an instrument so every key is instant
    func prewarm(instrumentName: String) {
        if !isSetup { setup() }
        let prog = AWInstrument.find(instrumentName).midiProgram
        synthQ.async { [weak self] in
            guard let self else { return }
            for m in 21...108 { _ = self.buildBuf(midi: m, dur: 0.8, prog: prog) }
        }
    }

    // MARK: - Score playback (main thread)
    func play(document: ScoreDocument) {
        setup()
        ensureRunning()
        if isPlaying && !isPaused { return }
        if !isPaused { currentBeat = 0 }
        isPlaying = true; isPaused = false
        _bpm = document.tempo
        totalBeats = Double(max(1, document.parts.first?.measures.count ?? 4)) * 4.0
        let beatSec = 60.0 / Double(document.tempo)
        let sixth   = beatSec / 4.0

        // Extract notes on main thread
        let notes = extractNotes(from: document)

        // Pre-synth all buffers in background, then schedule on main
        synthQ.async { [weak self] in
            guard let self else { return }
            var items: [(delay: Double, buf: AVAudioPCMBuffer)] = []
            for note in notes {
                if let buf = self.buildBuf(midi: note.midi, dur: note.duration, prog: note.program) {
                    items.append((note.startTime, buf))
                }
            }
            let totalDur = items.map { $0.delay + 0.1 }.max() ?? 1.0

            DispatchQueue.main.async { [weak self] in
                guard let self, self.isPlaying else { return }
                guard self.engine.isRunning else { self.stop(); return }
                for v in self.voices where !v.isPlaying { v.play() }

                // Host-time anchor is shared by ALL voices → overlapping notes mix correctly
                let anchor = mach_absolute_time()
                for item in items {
                    let noteTime = AVAudioTime(
                        hostTime: anchor + AVAudioTime.hostTime(forSeconds: item.delay + 0.12)
                    )
                    self.nextVoice().scheduleBuffer(item.buf, at: noteTime)
                }
            }
        }

        // Scrubber timer
        playTimer?.invalidate()
        playTimer = Timer.scheduledTimer(withTimeInterval: sixth, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            self.currentBeat += 0.25
            if self.currentBeat >= self.totalBeats { self.stop() }
        }
    }

    func pause() {
        playTimer?.invalidate(); playTimer = nil
        isPaused = true; isPlaying = false
        for v in voices { v.stop() }
        if engine.isRunning { for v in voices { v.play() } }
    }
    func stop()  {
        playTimer?.invalidate(); playTimer = nil
        isPlaying = false; isPaused = false; currentBeat = 0
        // Flush every voice's scheduled queue, then re-arm for instant key presses
        for v in voices { v.stop() }
        if engine.isRunning { for v in voices { v.play() } }
    }
    func seek(to p: Double) { currentBeat = p * totalBeats }

    // MARK: - Extract notes (main thread safe)
    private func extractNotes(from doc: ScoreDocument) -> [ScheduledNote] {
        var out: [ScheduledNote] = []
        let bs = 60.0 / Double(doc.tempo)
        for part in doc.parts {
            let prog = AWInstrument.find(part.instrument.rawValue).midiProgram
            var beat = 0.0
            for measure in part.measures {
                for content in measure.contents {
                    switch content {
                    case .chord(let ch):
                        for note in ch.notes {
                            out.append(ScheduledNote(
                                midi: max(21,min(108,note.pitch.midiNote)),
                                startTime: beat*bs,
                                duration: max(0.1, note.duration.beats*bs*0.88),
                                program: prog,
                                isTied: false
                            ))
                        }
                        beat += ch.totalBeats
                    case .rest(let r): beat += r.duration.beats
                    }
                }
            }
        }
        return out.sorted { $0.startTime < $1.startTime }
    }

    // MARK: - MIDI export
    func buildMIDI(from doc: ScoreDocument) -> Data {
        let ticks = 480; let bpm = doc.tempo
        let mspb  = 60_000_000 / bpm
        var tracks: [Data] = [Data([0x00,0xFF,0x51,0x03,
            UInt8((mspb>>16)&0xFF),UInt8((mspb>>8)&0xFF),UInt8(mspb&0xFF),
            0x00,0xFF,0x2F,0x00])]
        for (pi,part) in doc.parts.enumerated() {
            var t = Data(); let ch = UInt8(min(pi,14))
            let pg = AWInstrument.find(part.instrument.rawValue).midiProgram
            t += d(0)+[0xC0|ch,pg]
            for m in part.measures { for c in m.contents {
                switch c {
                case .chord(let ch2):
                    let dur = Int(ch2.totalBeats*Double(ticks))
                    for n in ch2.notes { let m2=UInt8(max(21,min(108,n.pitch.midiNote))); t+=d(0)+[0x90|ch,m2,90] }
                    for n in ch2.notes { let m2=UInt8(max(21,min(108,n.pitch.midiNote))); t+=d(dur)+[0x80|ch,m2,0] }
                case .rest: break
                }
            }}
            t+=d(0)+[0xFF,0x2F,0x00]; tracks.append(t)
        }
        var midi = Data([0x4D,0x54,0x68,0x64,0,0,0,6,0,1])
        let n=UInt16(tracks.count); midi+=[UInt8(n>>8),UInt8(n&0xFF),UInt8(ticks>>8),UInt8(ticks&0xFF)]
        for t in tracks { let l=UInt32(t.count)
            midi+=[0x4D,0x54,0x72,0x6B,UInt8(l>>24),UInt8(l>>16&0xFF),UInt8(l>>8&0xFF),UInt8(l&0xFF)]+t }
        return midi
    }
    private func d(_ v: Int) -> Data {
        var v=v,b=[UInt8](); b.append(UInt8(v&0x7F)); v>>=7
        while v>0{b.insert(UInt8((v&0x7F)|0x80),at:0);v>>=7}; return Data(b)
    }
    func exportWAV(document: ScoreDocument, completion: @escaping (URL?)->Void) {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(document.title+".mid")
        try? buildMIDI(from:document).write(to:url); completion(url)
    }
    func exportM4A(wavURL: URL, completion: @escaping (URL?)->Void) { completion(nil) }
}
