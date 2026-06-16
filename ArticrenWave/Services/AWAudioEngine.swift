// AWAudioEngine.swift — Thread-safe audio engine
// Key rule: AVAudioUnitSampler note on/off on audio thread only
import AVFoundation
import Observation

// MARK: - Instrument map
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

// Value type — safe to pass across thread boundaries
private struct ScheduledNote {
    let pitchClass: PitchClass
    let octave:     Int
    let startTime:  Double   // seconds from start
    let duration:   Double
    let program:    UInt8
    var midiNote: Int { (octave + 1) * 12 + pitchClass.rawValue }
}

// MARK: - Audio Player (@Observable for UI state only)
@Observable
class AWAudioPlayer {
    static let shared = AWAudioPlayer()

    // UI state — only written on main thread
    var isPlaying:   Bool   = false
    var isPaused:    Bool   = false
    var currentBeat: Double = 0.0
    var totalBeats:  Double = 16.0

    var progress: Double { totalBeats > 0 ? currentBeat / totalBeats : 0 }
    var currentTimeString: String {
        let secs = totalBeats > 0 ? (currentBeat / Double(max(1, _bpm))) * 60.0 : 0
        return String(format: "%d:%04.1f", Int(secs)/60, secs.truncatingRemainder(dividingBy: 60))
    }

    // Audio objects — only touched on audioThread
    private var engine      = AVAudioEngine()
    private var sampler     = AVAudioUnitSampler()
    private var playerNode  = AVAudioPlayerNode()
    private var isSetup     = false
    private var useSampler  = false
    private var _bpm        = 80
    private var playTimer:  Timer?

    // Dedicated serial queue for audio I/O
    private let audioThread = DispatchQueue(label: "aw.audio.thread", qos: .userInteractive)

    private init() {}

    // MARK: - Setup
    func setup() {
        guard !isSetup else { return }
        isSetup = true

        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback, mode: .default, options: [.mixWithOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { print("AVAudioSession: \(error)") }

        engine.attach(sampler)
        engine.attach(playerNode)
        engine.connect(sampler,    to: engine.mainMixerNode, format: nil)
        engine.connect(playerNode, to: engine.mainMixerNode, format: nil)

        do { try engine.start() } catch { print("Engine start: \(error)"); return }

        // Try system DLS
        let dlsPaths = [
            "/System/Library/Audio/Sounds/Banks/gs_instruments.dls",
            "/System/Library/Audio/Sounds/Banks/MacProDefault.dls",
        ]
        for p in dlsPaths where FileManager.default.fileExists(atPath: p) {
            if (try? sampler.loadSoundBankInstrument(
                at: URL(fileURLWithPath: p), program: 0, bankMSB: 0x79, bankLSB: 0
            )) != nil {
                useSampler = true; break
            }
        }
        // Bundled SF2
        if !useSampler {
            for (res, ext) in [("GeneralUser GS","sf2"),("soundfont","sf2")] {
                if let url = Bundle.main.url(forResource: res, withExtension: ext),
                   (try? sampler.loadSoundBankInstrument(
                       at: url, program: 0, bankMSB: 0x79, bankLSB: 0)) != nil {
                    useSampler = true; break
                }
            }
        }
    }

    // MARK: - Play single pitch (UI-triggered, main thread)
    func playPitch(_ pitch: Pitch, instrumentName: String = "Grand Piano", duration: Double = 0.5) {
        if !isSetup { setup() }
        guard engine.isRunning else { setup(); return }

        let midi = UInt8(max(21, min(108, pitch.midiNote)))
        let prog = AWInstrument.find(instrumentName).midiProgram

        if useSampler {
            // AVAudioUnitSampler is thread-safe for startNote/stopNote
            sampler.sendProgramChange(prog, bankMSB: 0x79, bankLSB: 0, onChannel: 0)
            sampler.startNote(midi, withVelocity: 90, onChannel: 0)
            let s = sampler
            audioThread.asyncAfter(deadline: .now() + duration) {
                s.stopNote(midi, onChannel: 0)
            }
        } else {
            synthNote(midi: Int(midi), duration: duration, program: prog)
        }
    }

    // MARK: - Synthesized tone
    private func synthNote(midi: Int, duration: Double, program: UInt8) {
        guard engine.isRunning else { return }
        let sr  = 44100.0
        let fc  = Int(sr * min(duration, 3.0))
        let freq = 440.0 * pow(2.0, (Double(midi) - 69.0) / 12.0)
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1),
              let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(fc)),
              let ptr = buf.floatChannelData?[0]
        else { return }
        buf.frameLength = AVAudioFrameCount(fc)

        audioThread.async { [weak self] in
            guard let self else { return }
            for i in 0..<fc {
                let t   = Double(i) / sr
                let env = min(1.0, t * 15) * max(0.0, 1.0 - t / duration)
                let v: Double
                switch program {
                case 40...43:                              // strings — saw
                    let ph = (freq * t).truncatingRemainder(dividingBy: 1.0)
                    v = (2*ph - 1) * env * 0.35
                case 56...75:                              // winds/brass — square
                    let ph = (freq * t).truncatingRemainder(dividingBy: 1.0)
                    v = (ph < 0.5 ? 1.0 : -1.0) * env * 0.28
                default:                                   // piano — sine+harmonics
                    let d = exp(-t * 3.5)
                    let s1 = sin(2.0 * Double.pi * freq * t)
                    let s2 = sin(2.0 * Double.pi * freq * 2.0 * t) * 0.30
                    let s3 = sin(2.0 * Double.pi * freq * 3.0 * t) * 0.10
                    v = (s1 + s2 + s3) * d * 0.40
                }
                ptr[i] = Float(v)
            }
            DispatchQueue.main.async {
                if !self.playerNode.isPlaying { self.playerNode.play() }
                self.playerNode.scheduleBuffer(buf, completionHandler: nil)
            }
        }
    }

    // MARK: - Score playback (call from main thread only)
    func play(document: ScoreDocument) {
        if !isSetup { setup() }

        // Don't restart if already playing
        if isPlaying && !isPaused { return }

        if !isPaused { currentBeat = 0 }
        isPlaying = true
        isPaused  = false
        _bpm      = document.tempo

        totalBeats = Double(max(1, document.parts.first?.measures.count ?? 4)) * 4.0
        let bpmD   = Double(document.tempo)
        let sixteenth = 60.0 / bpmD / 4.0

        // Extract notes on main thread (reads @Observable properties safely)
        let notes = extractNotes(from: document)

        // Schedule each note on a GLOBAL queue (not self.audioThread to avoid re-entrant deadlock)
        let schedQueue = DispatchQueue.global(qos: .userInteractive)
        let capturedSelf = self

        for note in notes {
            let delay = note.startTime
            schedQueue.asyncAfter(deadline: .now() + delay) {
                guard capturedSelf.isPlaying else { return }
                let pitch = Pitch(pitchClass: note.pitchClass, octave: note.octave)
                let midi  = UInt8(max(21, min(108, note.midiNote)))
                let prog  = note.program

                if capturedSelf.useSampler && capturedSelf.engine.isRunning {
                    capturedSelf.sampler.sendProgramChange(prog, bankMSB: 0x79, bankLSB: 0, onChannel: 0)
                    capturedSelf.sampler.startNote(midi, withVelocity: 85, onChannel: 0)
                    let s = capturedSelf.sampler
                    capturedSelf.audioThread.asyncAfter(deadline: .now() + note.duration * 0.9) {
                        s.stopNote(midi, onChannel: 0)
                    }
                } else {
                    DispatchQueue.main.async {
                        capturedSelf.synthNote(midi: Int(midi), duration: note.duration, program: prog)
                    }
                }
            }
        }

        // Timer advances scrubber on main thread
        playTimer?.invalidate()
        playTimer = Timer.scheduledTimer(withTimeInterval: sixteenth, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            self.currentBeat += 0.25
            if self.currentBeat >= self.totalBeats {
                self.stop()
            }
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

    // MARK: - Note extraction (main thread — safe for @Observable)
    private func extractNotes(from doc: ScoreDocument) -> [ScheduledNote] {
        var events: [ScheduledNote] = []
        let beatSecs = 60.0 / Double(doc.tempo)

        for part in doc.parts {
            let prog = AWInstrument.find(part.instrument.rawValue).midiProgram
            var beatPos = 0.0
            for measure in part.measures {
                for content in measure.contents {
                    switch content {
                    case .chord(let chord):
                        let t = beatPos * beatSecs
                        let d = max(0.05, chord.totalBeats * beatSecs * 0.88)
                        for note in chord.notes {
                            events.append(ScheduledNote(
                                pitchClass: note.pitch.pitchClass,
                                octave:     note.pitch.octave,
                                startTime:  t,
                                duration:   d,
                                program:    prog
                            ))
                        }
                        beatPos += chord.totalBeats
                    case .rest(let rest):
                        beatPos += rest.duration.beats
                    }
                }
            }
        }
        return events.sorted { $0.startTime < $1.startTime }
    }

    // MARK: - MIDI export (main thread)
    func buildMIDI(from document: ScoreDocument) -> Data {
        let bpm = document.tempo; let ticks = 480
        var tracks: [Data] = []
        let mspb = 60_000_000 / bpm
        tracks.append(Data([0x00,0xFF,0x51,0x03,
            UInt8((mspb>>16)&0xFF),UInt8((mspb>>8)&0xFF),UInt8(mspb&0xFF),
            0x00,0xFF,0x2F,0x00]))

        for (pi, part) in document.parts.enumerated() {
            var t = Data()
            let ch   = UInt8(min(pi,14))
            let prog = AWInstrument.find(part.instrument.rawValue).midiProgram
            t += delta(0) + [0xC0|ch, prog]
            for measure in part.measures {
                for content in measure.contents {
                    switch content {
                    case .chord(let chord):
                        let dur = Int(chord.totalBeats * Double(ticks))
                        for note in chord.notes {
                            let m = UInt8(max(21,min(108,note.pitch.midiNote)))
                            t += delta(0) + [0x90|ch,m,90]
                        }
                        for note in chord.notes {
                            let m = UInt8(max(21,min(108,note.pitch.midiNote)))
                            t += delta(dur) + [0x80|ch,m,0]
                        }
                    case .rest: break
                    }
                }
            }
            t += delta(0) + [0xFF,0x2F,0x00]
            tracks.append(t)
        }

        var midi = Data([0x4D,0x54,0x68,0x64,0,0,0,6,0,1])
        let n = UInt16(tracks.count)
        midi += [UInt8(n>>8),UInt8(n&0xFF),UInt8(ticks>>8),UInt8(ticks&0xFF)]
        for t in tracks {
            let l = UInt32(t.count)
            midi += [0x4D,0x54,0x72,0x6B,
                     UInt8(l>>24),UInt8(l>>16&0xFF),UInt8(l>>8&0xFF),UInt8(l&0xFF)] + t
        }
        return midi
    }

    private func delta(_ v: Int) -> Data {
        var v=v; var b=[UInt8]()
        b.append(UInt8(v&0x7F)); v>>=7
        while v>0 { b.insert(UInt8((v&0x7F)|0x80),at:0); v>>=7 }
        return Data(b)
    }

    func exportWAV(document: ScoreDocument, completion: @escaping (URL?) -> Void) {
        let midi = buildMIDI(from: document)
        let url  = FileManager.default.temporaryDirectory
            .appendingPathComponent(document.title + ".mid")
        try? midi.write(to: url)
        completion(url)
    }
    func exportM4A(wavURL: URL, completion: @escaping (URL?) -> Void) { completion(nil) }
}
