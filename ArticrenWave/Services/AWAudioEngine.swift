// AWAudioEngine.swift — AVAudioEngine driving AVAudioUnitSampler(s) loaded with
// iOS's built-in orchestral sound bank (real sampled instruments, not synthesized
// oscillators). All AVAudio calls on main thread.
import AVFoundation
import UIKit
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
    let channel:   UInt8
}

@Observable
class AWAudioPlayer {
    static let shared = AWAudioPlayer()

    var isPlaying:   Bool   = false
    var isPaused:    Bool   = false
    var currentBeat: Double = 0.0
    var totalBeats:  Double = 16.0

    // Rolling debug log — off-screen by default, viewable via Settings > Debug Console
    var debugLog: [String] = []
    func log(_ msg: String) {
        let stamp = String(format: "%.2f", CFAbsoluteTimeGetCurrent().truncatingRemainder(dividingBy: 1000))
        debugLog.append("[\(stamp)] \(msg)")
        if debugLog.count > 200 { debugLog.removeFirst(debugLog.count - 200) }
    }

    var progress: Double { totalBeats > 0 ? currentBeat / totalBeats : 0 }
    var currentTimeString: String {
        let s = totalBeats > 0 ? (currentBeat / Double(max(1,_bpm))) * 60.0 : 0
        return String(format: "%d:%04.1f", Int(s)/60, s.truncatingRemainder(dividingBy: 60))
    }

    // MARK: - Audio graph
    // A pool of samplers, one per MIDI channel (0-15), each independently able to
    // hold a different instrument's program. This gives us real orchestral samples
    // (piano, strings, brass, winds, etc. from iOS's built-in sound bank) with
    // simultaneous multi-instrument, polyphonic playback.
    private var engine    = AVAudioEngine()
    private var reverb    = AVAudioUnitReverb()
    private var samplers: [AVAudioUnitSampler] = []
    private let channelCount = 16
    private var loadedProgram: [UInt8: UInt8] = [:]   // channel -> currently loaded program
    private var isSetup    = false
    private var _bpm       = 80
    private var playTimer: Timer?
    private var soundBankURL: URL?

    private var observersInstalled = false
    private var lastSetupFinishedAt: CFAbsoluteTime = 0

    private init() {}

    /// Restart engine/session if iOS suspended them (app init, interruptions, route changes)
    private func ensureRunning() {
        if !engine.isRunning { isSetup = false }
    }

    private func installObservers() {
        guard !observersInstalled else { return }
        observersInstalled = true
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if CFAbsoluteTimeGetCurrent() - self.lastSetupFinishedAt > 0.4 {
                self.isSetup = false
            }
        }
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.isSetup = false }
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.isSetup = false }
    }

    /// Locate iOS's built-in orchestral sound bank. This ships on-device -- no
    /// bundled soundfont needed -- and provides real sampled instruments across
    /// the full General MIDI program set (piano, strings, brass, woodwinds,
    /// percussion, etc.), which is what actually sounds like an orchestra
    /// instead of raw oscillator waveforms.
    private func locateSoundBank() -> URL? {
        let candidates = [
            "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls",
            "/System/Library/Audio/Sounds/Banks/gs_instruments.dls",
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    // MARK: - Setup (main thread only) -- rebuilds the whole graph when dirty
    func setup() {
        if isSetup && engine.isRunning { log("already running"); return }
        installObservers()

        engine.stop()
        engine = AVAudioEngine()
        reverb = AVAudioUnitReverb()
        samplers = (0..<channelCount).map { _ in AVAudioUnitSampler() }
        loadedProgram = [:]

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { log("session error: \(error.localizedDescription)") }

        reverb.loadFactoryPreset(.mediumHall)
        reverb.wetDryMix = 14
        engine.attach(reverb)
        for s in samplers { engine.attach(s) }
        // Samplers -> reverb -> mixer, in that order, with an explicit format at
        // every stage so nothing in the chain is ever left format-less.
        let stereoFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)
        for s in samplers {
            engine.connect(s, to: reverb, format: stereoFormat)
        }
        engine.connect(reverb, to: engine.mainMixerNode, format: stereoFormat)

        guard UIApplication.shared.applicationState == .active else {
            log("waiting for app active")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.setup() }
            return
        }
        do { try engine.start() } catch {
            log("engine.start() threw: \(error.localizedDescription)")
            return
        }
        guard engine.isRunning else { log("engine.start() returned but isRunning=false"); return }

        soundBankURL = locateSoundBank()
        if soundBankURL == nil {
            log("WARNING: no system sound bank found -- instruments will be silent")
        }

        // Load default program 0 (Grand Piano) on every channel up front so the
        // very first key press on any channel is instant.
        if let bank = soundBankURL {
            for (idx, s) in samplers.enumerated() {
                let ch = UInt8(idx)
                if let reason = AWTryCatch({
                    try? s.loadSoundBankInstrument(at: bank, program: 0, bankMSB: 0x79, bankLSB: 0)
                }) {
                    log("loadSoundBankInstrument ch\(ch) EXCEPTION: \(reason)")
                } else {
                    loadedProgram[ch] = 0
                }
            }
        }

        isSetup = true
        lastSetupFinishedAt = CFAbsoluteTimeGetCurrent()
        log("engine running, \(samplers.count) sampler channels, bank=\(soundBankURL?.lastPathComponent ?? "none")")
    }

    /// Ensure the given channel's sampler has the requested program loaded
    /// (loadSoundBankInstrument is relatively cheap once the bank file is
    /// already mmap'd by iOS, but we still cache to avoid redundant calls).
    private func ensureProgram(_ program: UInt8, onChannel ch: UInt8) {
        guard let bank = soundBankURL else { return }
        if loadedProgram[ch] == program { return }
        let sampler = samplers[Int(ch)]
        if let reason = AWTryCatch({
            try? sampler.loadSoundBankInstrument(at: bank, program: program, bankMSB: 0x79, bankLSB: 0)
        }) {
            log("ensureProgram ch\(ch) prog\(program) EXCEPTION: \(reason)")
        } else {
            loadedProgram[ch] = program
        }
    }

    // MARK: - Play single pitch (call from main thread)
    func playPitch(_ pitch: Pitch, instrumentName: String = "Grand Piano", duration: Double = 0.5) {
        setup()
        ensureRunning()
        guard engine.isRunning else { log("playPitch: engine not running"); return }

        let midi = UInt8(max(21, min(108, pitch.midiNote)))
        let prog = AWInstrument.find(instrumentName).midiProgram
        let ch: UInt8 = 0   // solo key-press preview always uses channel 0
        ensureProgram(prog, onChannel: ch)

        let sampler = samplers[Int(ch)]
        if let reason = AWTryCatch({ sampler.startNote(midi, withVelocity: 100, onChannel: ch) }) {
            log("playPitch startNote EXCEPTION: \(reason)")
            isSetup = false
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard self != nil else { return }
            _ = AWTryCatch({ sampler.stopNote(midi, onChannel: ch) })
        }
        log("playPitch: midi=\(midi) prog=\(prog) ch=\(ch)")
    }

    /// Pre-load a program across the channel pool so switching instruments and
    /// pressing a key feels instant rather than waiting on sound-bank loading.
    func prewarm(instrumentName: String) {
        setup()
        let prog = AWInstrument.find(instrumentName).midiProgram
        ensureProgram(prog, onChannel: 0)
    }

    // MARK: - Score playback (main thread)
    func play(document: ScoreDocument) {
        setup()
        ensureRunning()
        guard engine.isRunning else { log("play: engine not running"); return }
        if isPlaying && !isPaused { return }
        if !isPaused { currentBeat = 0 }
        isPlaying = true; isPaused = false
        _bpm = document.tempo
        totalBeats = Double(max(1, document.parts.first?.measures.count ?? 4)) * 4.0
        let beatSec = 60.0 / Double(document.tempo)
        let sixth   = beatSec / 4.0

        let notes = extractNotes(from: document)

        // Assign one MIDI channel per part (up to 16 simultaneous instrument
        // parts) so each staff plays through its own sampler with its own
        // loaded program.
        var channelForProgram: [UInt8: UInt8] = [:]
        var nextFreeChannel: UInt8 = 0
        for note in notes where channelForProgram[note.program] == nil {
            guard nextFreeChannel < UInt8(channelCount) else { break }
            channelForProgram[note.program] = nextFreeChannel
            ensureProgram(note.program, onChannel: nextFreeChannel)
            nextFreeChannel += 1
        }

        for note in notes {
            let ch = channelForProgram[note.program] ?? 0
            let sampler = samplers[Int(ch)]
            let midi = UInt8(max(21, min(108, note.midi)))
            DispatchQueue.main.asyncAfter(deadline: .now() + note.startTime) { [weak self] in
                guard let self, self.isPlaying else { return }
                _ = AWTryCatch({ sampler.startNote(midi, withVelocity: 95, onChannel: ch) })
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + note.startTime + note.duration) { [weak self] in
                guard self != nil else { return }
                _ = AWTryCatch({ sampler.stopNote(midi, onChannel: ch) })
            }
        }

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
        for s in samplers { for ch: UInt8 in 0..<UInt8(channelCount) { _ = AWTryCatch({ s.stopNote(0, onChannel: ch) }) } }
    }
    func stop() {
        playTimer?.invalidate(); playTimer = nil
        isPlaying = false; isPaused = false; currentBeat = 0
        for s in samplers { for m: UInt8 in 21...108 { _ = AWTryCatch({ s.stopNote(m, onChannel: 0) }) } }
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
                                channel: 0
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
