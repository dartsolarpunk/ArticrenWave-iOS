// AWAudioEngine.swift — AVAudioEngine with synthesized instruments
// All AVAudio calls on MainActor / main thread only
// Sound design based on additive synthesis per instrument type
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
    let isTied:    Bool
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
        if debugLog.count > 20_000 { debugLog.removeFirst(debugLog.count - 20_000) }
        AWDebugLog.shared.log(msg, category: "AUDIO")
    }

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

    /// play() throws an ObjC NSException if a fresh AVAudioPlayerNode races the
    /// engine's render-graph setup on some devices, even though engine.isRunning
    /// reads true and the node is genuinely attached. Retrying the SAME node
    /// after a brief delay (rather than tearing down and rebuilding the whole
    /// engine, which was happening on every single note and produced an
    /// unbreakable fail-rebuild-fail loop) resolves this without ever losing a
    /// graph that was otherwise healthy.
    @discardableResult
    private func startVoice(_ v: AVAudioPlayerNode, retriesLeft: Int = 6) -> Bool {
        guard engine.isRunning, v.engine === engine else {
            log("startVoice: engine.isRunning=\(engine.isRunning) v.engine===engine=\(v.engine === engine)")
            return false
        }
        if v.isPlaying { return true }

        // The render thread needs a brief moment to actually come up after
        // engine.start() returns -- that call can report success and
        // engine.isRunning can read true while the render graph is still
        // spinning up internally. Calling .play() on a freshly attached node
        // in the same synchronous call stack as engine.start() (which is
        // exactly what playPitch -> setup() -> startVoice does) is what
        // produced "player started when in a disconnected state" on every
        // single voice, regardless of sample rate or format (both directly
        // ruled out: the hardware rate is now correctly detected as 48kHz and
        // the exception persists identically). Waiting out the settle window
        // before the first attempt, rather than only retrying after failing,
        // avoids the failure in the first place instead of reacting to it.
        let sinceSetup = CFAbsoluteTimeGetCurrent() - lastSetupFinishedAt
        let settleWindow = 0.15
        if sinceSetup < settleWindow {
            Thread.sleep(forTimeInterval: settleWindow - sinceSetup)
        }

        if let reason = AWTryCatch({ v.play() }) {
            log("startVoice EXCEPTION: \(reason) (retriesLeft=\(retriesLeft))")
            if retriesLeft > 0 {
                // Do NOT invalidate isSetup here -- the engine itself is fine;
                // this is a transient race on the node, not a dead graph.
                Thread.sleep(forTimeInterval: 0.03)
                return startVoice(v, retriesLeft: retriesLeft - 1)
            }
            // Only after repeated failures on an otherwise-healthy engine do we
            // consider the graph itself suspect and allow the next setup() to rebuild.
            isSetup = false
            return false
        }
        return true
    }

    /// scheduleBuffer can also throw on a dead graph — same protection
    private func safeSchedule(_ v: AVAudioPlayerNode, _ buf: AVAudioPCMBuffer, at when: AVAudioTime? = nil) {
        if let reason = AWTryCatch({ v.scheduleBuffer(buf, at: when, options: [], completionHandler: nil) }) {
            log("scheduleBuffer EXCEPTION: \(reason)")
            isSetup = false
        }
    }
    private var reverbNode = AVAudioUnitReverb()
    private var isSetup    = false
    private var _bpm       = 80
    private var playTimer: Timer?
    private var sr: Double = 44100   // updated to the real hardware rate once the engine starts

    // Buffer cache: key = (midi << 8 | program)
    private var bufCache: [Int: AVAudioPCMBuffer] = [:]
    private let synthQ = DispatchQueue(label: "aw.synth", qos: .userInitiated)

    private init() {}

    private let cacheLock = NSLock()

    private var observersInstalled = false

    private var lastSetupFinishedAt: CFAbsoluteTime = 0

    /// The engine's isRunning can report true while internally paused after a
    /// route/session reconfiguration (iOS 26+). These observers mark it dirty
    /// so the next sound request rebuilds the graph from scratch.
    ///
    /// AVAudioEngineConfigurationChange also fires as a normal side effect of our
    /// OWN attach/connect/start calls inside setup() — not just external events.
    /// Ignore it for a brief settle window right after we finish building the graph,
    /// or every setup() call immediately invalidates itself before a note can play.
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

    // MARK: - Setup (main thread only) — rebuilds the whole graph when dirty
    func setup() {
        if isSetup && engine.isRunning { log("already running"); return }
        installObservers()

        // Tear down any previous graph completely — reattaching to a half-dead
        // engine is what makes play() throw even when isRunning reads true.
        engine.stop()
        engine = AVAudioEngine()
        reverbNode = AVAudioUnitReverb()
        voices = []
        vIdx = 0
        cacheLock.lock(); bufCache.removeAll(); cacheLock.unlock()

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { log("session error: \(error.localizedDescription)") }
        reverbNode.loadFactoryPreset(.mediumHall)
        reverbNode.wetDryMix = 12
        engine.attach(reverbNode)
        // 8-voice polyphonic pool: each key press gets its own node → instant, overlapping notes
        voices = (0..<8).map { _ in AVAudioPlayerNode() }
        playerNode = voices[0]
        // CRITICAL FIX: connect with format: nil, NOT an explicitly queried format.
        // The previous attempt read engine.mainMixerNode.outputFormat(forBus: 0)
        // BEFORE engine.start() -- at that point AVAudioEngine has not yet
        // negotiated anything with the real hardware and outputFormat(forBus:)
        // returns an internal placeholder (44.1kHz stereo), which is why the log
        // kept showing exactly "44100.0Hz, 2ch" even on a device whose real
        // session runs at 48kHz. That placeholder was then forced onto every
        // connection, producing the same silent format mismatch as before under
        // a different disguise. Passing format: nil is the Apple-documented
        // pattern here: it lets the engine infer the connection format from
        // what's already wired, which is what actually avoids the mismatch.
        for v in voices {
            engine.attach(v)
            engine.connect(v, to: reverbNode, format: nil)
        }
        engine.connect(reverbNode, to: engine.mainMixerNode, format: nil)
        // Only start audio when the app is truly active — starting during launch/transition
        // makes the engine report running then die, and the next play() aborts the process.
        // If we're not active yet, retry shortly rather than silently giving up forever.
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
        // NOW it's safe to read the real negotiated hardware rate -- only after
        // a successful engine.start() does AVAudioSession.sampleRate reflect
        // what the hardware actually negotiated, rather than a placeholder.
        let realRate = AVAudioSession.sharedInstance().sampleRate
        if realRate > 0 { sr = realRate }
        log("engine started -- real hardware rate: \(realRate)Hz")
        // NOTE: voices are NOT pre-played here. Each voice starts individually,
        // guarded, at the moment it's needed (startVoice) — never in bulk.
        isSetup = true   // only after verified start
        lastSetupFinishedAt = CFAbsoluteTimeGetCurrent()
        log("engine running, \(voices.count) voices")

        // Warm up every voice node once, right now, while nothing depends on
        // the timing -- if a node's very first .play() carries its own
        // settle/activation cost (distinct from the engine-wide startup cost),
        // this absorbs it here instead of on the first real note the user
        // actually wants to hear.
        for v in voices {
            _ = AWTryCatch({ v.play() })
            _ = AWTryCatch({ v.stop() })
        }
        log("voice warm-up pass complete")
        // Pre-warm full piano range for instant key response
        synthQ.async { [weak self] in
            guard let self else { return }
            for m in 21...108 { _ = self.buildBuf(midi: m, dur: 0.8, prog: 0) }
        }
    }

    // MARK: - Synthesize PCM buffer (background)
    /// Restart engine/session if iOS suspended them (app init, interruptions, route changes)
    private func ensureRunning() {
        if !engine.isRunning { isSetup = false }   // dirty → setup() rebuilds the graph
        // Voices start lazily per-schedule via startVoice — no bulk play
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
        guard engine.isRunning else { log("playPitch: engine not running"); return }

        // INSTANT path: cached buffer schedules with zero latency
        cacheLock.lock()
        let cachedBuf = bufCache[key]
        cacheLock.unlock()
        if let cached = cachedBuf {
            let v = nextVoice()
            guard startVoice(v) else { log("playPitch: startVoice failed (cached)"); return }
            safeSchedule(v, cached)           // fresh voice → plays NOW, mixes with others
            log("playPitch: scheduled midi=\(midi) (cached), vol=\(engine.mainMixerNode.outputVolume)")
            return
        }
        // Cold path: synth in background then play
        log("playPitch: synthesizing midi=\(midi)…")
        synthQ.async { [weak self] in
            guard let self else { return }
            let buf = self.buildBuf(midi: midi, dur: duration, prog: prog)
            DispatchQueue.main.async {
                guard let buf, self.engine.isRunning else {
                    self.log("playPitch: buf or engine nil after synth")
                    return
                }
                let v = self.nextVoice()
                guard self.startVoice(v) else { self.log("playPitch: startVoice failed (cold)"); return }
                self.safeSchedule(v, buf)
                self.log("playPitch: scheduled midi=\(midi) (cold), vol=\(self.engine.mainMixerNode.outputVolume)")
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
                // Host-time anchor is shared by ALL voices → overlapping notes mix correctly
                let anchor = mach_absolute_time()
                for item in items {
                    let v = self.nextVoice()
                    guard self.startVoice(v) else { continue }
                    let noteTime = AVAudioTime(
                        hostTime: anchor + AVAudioTime.hostTime(forSeconds: item.delay + 0.12)
                    )
                    self.safeSchedule(v, item.buf, at: noteTime)
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
        for v in voices { _ = AWTryCatch({ v.stop() }) }
    }
    func stop()  {
        playTimer?.invalidate(); playTimer = nil
        isPlaying = false; isPaused = false; currentBeat = 0
        // Flush every voice's scheduled queue, then re-arm for instant key presses
        for v in voices { _ = AWTryCatch({ v.stop() }) }
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

    /// Render the whole score to a real WAV file by mixing every note's
    /// synthesized buffer into one master PCM buffer at its correct sample
    /// offset, then writing it with AVAudioFile. This does NOT depend on the
    /// live AVAudioEngine graph at all, so it works even if playback is busy
    /// or the engine hasn't started -- and it's sample-accurate, not a
    /// real-time capture.
    func exportWAV(document: ScoreDocument, completion: @escaping (URL?) -> Void) {
        let notes = extractNotes(from: document)
        guard !notes.isEmpty else { completion(nil); return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { completion(nil); return }

            let totalDur = notes.map { $0.startTime + $0.duration }.max() ?? 1.0
            let totalFrames = Int(self.sr * (totalDur + 0.5))
            guard let fmt = AVAudioFormat(standardFormatWithSampleRate: self.sr, channels: 2),
                  let master = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(totalFrames)),
                  let mL = master.floatChannelData?[0], let mR = master.floatChannelData?[1]
            else { DispatchQueue.main.async { completion(nil) }; return }
            master.frameLength = AVAudioFrameCount(totalFrames)

            for note in notes {
                guard let buf = self.buildBuf(midi: note.midi, dur: note.duration, prog: note.program),
                      let bL = buf.floatChannelData?[0], let bR = buf.floatChannelData?[1]
                else { continue }
                let startFrame = Int(note.startTime * self.sr)
                let frames = Int(buf.frameLength)
                for i in 0..<frames {
                    let dst = startFrame + i
                    guard dst < totalFrames else { break }
                    mL[dst] += bL[i]
                    mR[dst] += bR[i]
                }
            }

            // Soft-limit to avoid clipping when many notes/chords overlap
            for i in 0..<totalFrames {
                mL[i] = max(-1.0, min(1.0, mL[i]))
                mR[i] = max(-1.0, min(1.0, mR[i]))
            }

            let safeTitle = document.title.isEmpty ? "Untitled Score" : document.title
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(safeTitle + ".wav")
            try? FileManager.default.removeItem(at: url)

            do {
                let file = try AVAudioFile(
                    forWriting: url,
                    settings: [
                        AVFormatIDKey: kAudioFormatLinearPCM,
                        AVSampleRateKey: self.sr,
                        AVNumberOfChannelsKey: 2,
                        AVLinearPCMBitDepthKey: 16,
                        AVLinearPCMIsFloatKey: false,
                        AVLinearPCMIsBigEndianKey: false
                    ]
                )
                try file.write(from: master)
                DispatchQueue.main.async { completion(url) }
            } catch {
                DispatchQueue.main.async {
                    self.log("exportWAV write failed: \(error.localizedDescription)")
                    completion(nil)
                }
            }
        }
    }

    /// Convert a rendered WAV to AAC-in-M4A -- a compressed, widely-accepted
    /// format for uploading to SoundCloud and similar platforms. (iOS has no
    /// public MP3 encoder; M4A/AAC is the standard, broadly-compatible
    /// substitute at comparable quality and much smaller file size than WAV.)
    func exportM4A(wavURL: URL, completion: @escaping (URL?) -> Void) {
        let asset = AVAsset(url: wavURL)
        let outURL = wavURL.deletingPathExtension().appendingPathExtension("m4a")
        try? FileManager.default.removeItem(at: outURL)

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            completion(nil); return
        }
        session.outputURL = outURL
        session.outputFileType = .m4a
        session.exportAsynchronously { [weak self] in
            DispatchQueue.main.async {
                switch session.status {
                case .completed:
                    completion(outURL)
                case .failed, .cancelled:
                    self?.log("exportM4A failed: \(session.error?.localizedDescription ?? "unknown")")
                    completion(nil)
                default:
                    completion(nil)
                }
            }
        }
    }
}
