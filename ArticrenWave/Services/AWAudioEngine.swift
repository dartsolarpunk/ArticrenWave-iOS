// AWAudioEngine.swift — Audio playback using AVAudioEngine + AVAudioUnitSampler
// Falls back to synthesized tones if soundfont not available
import AVFoundation
import Observation

// MARK: - Instrument → GM Program mapping
struct AWInstrument {
    let name: String
    let midiProgram: UInt8
    static let all: [AWInstrument] = [
        AWInstrument(name: "Grand Piano",  midiProgram: 0),
        AWInstrument(name: "Violin",       midiProgram: 40),
        AWInstrument(name: "Viola",        midiProgram: 41),
        AWInstrument(name: "Cello",        midiProgram: 42),
        AWInstrument(name: "Flute",        midiProgram: 73),
        AWInstrument(name: "Oboe",         midiProgram: 68),
        AWInstrument(name: "Clarinet",     midiProgram: 71),
        AWInstrument(name: "Trumpet",      midiProgram: 56),
        AWInstrument(name: "French Horn",  midiProgram: 60),
        AWInstrument(name: "Harp",         midiProgram: 46),
    ]
    static func find(_ name: String) -> AWInstrument {
        all.first { $0.name == name } ?? all[0]
    }
}

// MARK: - Audio Player
@Observable
class AWAudioPlayer {
    static let shared = AWAudioPlayer()

    // Playback state
    var isPlaying:    Bool   = false
    var isPaused:     Bool   = false
    var currentBeat:  Double = 0.0
    var totalBeats:   Double = 16.0

    var progress: Double { totalBeats > 0 ? currentBeat / totalBeats : 0 }
    var currentTimeString: String {
        let s = totalBeats > 0 ? (currentBeat / Double(80)) * 60 : 0
        return String(format: "%d:%04.1f", Int(s)/60, s.truncatingRemainder(dividingBy: 60))
    }

    // Engine
    private var engine      = AVAudioEngine()
    private var sampler     = AVAudioUnitSampler()
    private var playerNode  = AVAudioPlayerNode()
    private var isSetup     = false
    private var useSampler  = false   // true if soundfont loaded OK
    private var playTimer:  Timer?
    private var currentProgram: UInt8 = 0

    private init() {}

    // MARK: - Setup
    func setup() {
        guard !isSetup else { return }
        isSetup = true

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { print("AVAudioSession: \(error)") }

        // Try sampler with iOS built-in DLS bank
        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)

        // Also attach a player node for synthesized fallback
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: nil)

        do {
            try engine.start()
        } catch {
            print("Engine start failed: \(error)")
            return
        }

        // Try to load soundfont — first bundled, then system DLS
        let dlsPaths = [
            "/System/Library/Audio/Sounds/Banks/gs_instruments.dls",
            "/System/Library/Audio/Sounds/Banks/MacProDefault.dls",
        ]
        for path in dlsPaths {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                do {
                    try sampler.loadSoundBankInstrument(at: url, program: 0, bankMSB: 0x79, bankLSB: 0)
                    useSampler = true
                    print("Loaded soundfont: \(path)")
                    break
                } catch { print("Soundfont load failed: \(error)") }
            }
        }
        // Also try bundled SF2
        if !useSampler, let sf2 = Bundle.main.url(forResource: "GeneralUser GS", withExtension: "sf2")
                                   ?? Bundle.main.url(forResource: "soundfont", withExtension: "sf2") {
            do {
                try sampler.loadSoundBankInstrument(at: sf2, program: 0, bankMSB: 0x79, bankLSB: 0)
                useSampler = true
                print("Loaded bundled SF2")
            } catch { print("Bundled SF2 load failed: \(error)") }
        }

        if !useSampler { print("Using synthesized tones (no soundfont available)") }
    }

    // MARK: - Play a single pitch
    func playPitch(_ pitch: Pitch, instrumentName: String = "Grand Piano", duration: Double = 0.5) {
        if !isSetup { setup() }

        let midi = UInt8(max(21, min(108, pitch.midiNote)))
        let prog = AWInstrument.find(instrumentName).midiProgram

        if useSampler {
            // Change program if needed
            if prog != currentProgram {
                sampler.sendProgramChange(prog, bankMSB: 0x79, bankLSB: 0, onChannel: 0)
                currentProgram = prog
            }
            sampler.startNote(midi, withVelocity: 90, onChannel: 0)
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                self.sampler.stopNote(midi, onChannel: 0)
            }
        } else {
            // Synthesize a pitched tone
            playSynthTone(midiNote: midi, duration: duration, program: prog)
        }
    }

    // MARK: - Synthesized tone fallback
    private func playSynthTone(midiNote: UInt8, duration: Double, program: UInt8) {
        guard engine.isRunning else { return }

        let sampleRate: Double = 44100
        let frameCount = Int(sampleRate * duration)
        let freq = 440.0 * pow(2.0, (Double(midiNote) - 69.0) / 12.0)

        // Choose waveform by instrument type (program number)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else { return }
        buf.frameLength = AVAudioFrameCount(frameCount)

        guard let ptr = buf.floatChannelData?[0] else { return }

        for i in 0..<frameCount {
            let t = Double(i) / sampleRate
            let envelope = min(1.0, t * 20) * max(0, 1.0 - t / duration)
            var sample: Double

            switch program {
            case 40...43:  // Strings — sawtooth
                let phase = (freq * t).truncatingRemainder(dividingBy: 1.0)
                sample = (2.0 * phase - 1.0) * envelope
            case 68...73:  // Woodwinds — square
                let phase = (freq * t).truncatingRemainder(dividingBy: 1.0)
                sample = (phase < 0.5 ? 1.0 : -1.0) * envelope * 0.7
            case 56...67:  // Brass — sawtooth + harmonic
                let phase = (freq * t).truncatingRemainder(dividingBy: 1.0)
                sample = (2.0 * phase - 1.0 + sin(2 * .pi * freq * 2 * t) * 0.3) * envelope * 0.6
            default:       // Piano — sine with harmonics + quick decay
                let decay = exp(-t * 3.0)
                sample = (sin(2 * .pi * freq * t)
                        + sin(2 * .pi * freq * 2 * t) * 0.4
                        + sin(2 * .pi * freq * 3 * t) * 0.15
                        + sin(2 * .pi * freq * 4 * t) * 0.05) * decay * 0.5
            }
            ptr[i] = Float(sample * 0.4)
        }

        if !playerNode.isPlaying { playerNode.play() }
        playerNode.scheduleBuffer(buf, completionHandler: nil)
    }

    // MARK: - Score playback
    func play(document: ScoreDocument) {
        if !isSetup { setup() }
        guard !isPlaying else { return }
        if !isPaused { currentBeat = 0 }
        isPlaying = true
        isPaused  = false

        totalBeats = Double(max(1, document.parts.first?.measures.count ?? 4)) * 4.0
        let bpm    = Double(document.tempo)

        // Schedule all notes
        let notes = extractNotes(from: document)
        for note in notes {
            DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + note.startTime) {
                guard self.isPlaying else { return }
                let pitch = Pitch(pitchClass: note.pitchClass, octave: note.octave)
                let instrName = AWInstrument.all.first(where: { $0.midiProgram == note.program })?.name ?? "Grand Piano"
                self.playPitch(pitch, instrumentName: instrName, duration: note.duration)
            }
        }

        // Advance scrubber
        let sixteenth = 60.0 / bpm / 4.0
        playTimer?.invalidate()
        playTimer = Timer.scheduledTimer(withTimeInterval: sixteenth, repeats: true) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                self.currentBeat += 0.25
                if self.currentBeat >= self.totalBeats { self.stop() }
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

    // MARK: - Note extraction
    struct NoteEvent {
        let pitchClass: PitchClass
        let octave:     Int
        let startTime:  Double
        let duration:   Double
        let program:    UInt8
    }

    private func extractNotes(from doc: ScoreDocument) -> [NoteEvent] {
        var events: [NoteEvent] = []
        let beatDur = 60.0 / Double(doc.tempo)

        for (pi, part) in doc.parts.enumerated() {
            let prog = AWInstrument.find(part.instrument.rawValue).midiProgram
            var beat: Double = 0

            for measure in part.measures {
                for content in measure.contents {
                    switch content {
                    case .chord(let chord):
                        let t = beat * beatDur
                        let d = chord.totalBeats * beatDur * 0.88
                        for note in chord.notes {
                            events.append(NoteEvent(
                                pitchClass: note.pitch.pitchClass,
                                octave:     note.pitch.octave,
                                startTime:  t, duration: d, program: prog
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

    // MARK: - MIDI file builder
    func buildMIDI(from document: ScoreDocument) -> Data {
        let bpm   = document.tempo
        let ticks = 480

        var tracks: [Data] = []

        // Tempo track
        var tempo = Data()
        let mspb = 60_000_000 / bpm
        tempo += [0x00, 0xFF, 0x51, 0x03,
                  UInt8((mspb >> 16) & 0xFF), UInt8((mspb >> 8) & 0xFF), UInt8(mspb & 0xFF),
                  0x00, 0xFF, 0x2F, 0x00]
        tracks.append(tempo)

        for (pi, part) in document.parts.enumerated() {
            var track = Data()
            let ch  = UInt8(min(pi, 14))
            let prog = AWInstrument.find(part.instrument.rawValue).midiProgram
            track += delta(0) + [0xC0 | ch, prog]

            var tick = 0
            for measure in part.measures {
                for content in measure.contents {
                    switch content {
                    case .chord(let chord):
                        let dur = Int(chord.totalBeats * Double(ticks))
                        for note in chord.notes {
                            let midi = UInt8(max(21, min(108, note.pitch.midiNote)))
                            track += delta(0) + [0x90 | ch, midi, 90]
                        }
                        for note in chord.notes {
                            let midi = UInt8(max(21, min(108, note.pitch.midiNote)))
                            track += delta(dur) + [0x80 | ch, midi, 0]
                        }
                        tick += dur
                    case .rest(let rest):
                        tick += Int(rest.duration.beats * Double(ticks))
                    }
                }
            }
            track += delta(0) + [0xFF, 0x2F, 0x00]
            tracks.append(track)
        }

        var midi = Data()
        midi += [0x4D,0x54,0x68,0x64, 0x00,0x00,0x00,0x06, 0x00,0x01]
        let n = UInt16(tracks.count)
        midi += [UInt8(n>>8), UInt8(n&0xFF), UInt8(ticks>>8), UInt8(ticks&0xFF)]
        for t in tracks {
            midi += [0x4D,0x54,0x72,0x6B]
            let len = UInt32(t.count)
            midi += [UInt8(len>>24), UInt8(len>>16&0xFF), UInt8(len>>8&0xFF), UInt8(len&0xFF)]
            midi += t
        }
        return midi
    }

    private func delta(_ ticks: Int) -> Data {
        var v = ticks; var bytes: [UInt8] = []
        bytes.append(UInt8(v & 0x7F)); v >>= 7
        while v > 0 { bytes.insert(UInt8((v & 0x7F) | 0x80), at: 0); v >>= 7 }
        return Data(bytes)
    }

    // MARK: - WAV export
    func exportWAV(document: ScoreDocument, completion: @escaping (URL?) -> Void) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(document.title + ".wav")
        // Build MIDI then render with AVMIDIPlayer
        let midiData = buildMIDI(from: document)
        let midiURL  = FileManager.default.temporaryDirectory.appendingPathComponent("_render.mid")
        do {
            try midiData.write(to: midiURL)
            let player = try AVMIDIPlayer(contentsOf: midiURL, soundBankURL: nil)
            player.prepareToPlay()
            // AVMIDIPlayer doesn't have offline render — record in real time
            // For now deliver the MIDI file as the best we can do without a soundfont
            DispatchQueue.main.async { completion(midiURL) }
        } catch {
            print("WAV export error: \(error)")
            DispatchQueue.main.async { completion(nil) }
        }
    }

    func exportM4A(wavURL: URL, completion: @escaping (URL?) -> Void) {
        completion(nil) // requires offline render; return nil, user gets MIDI
    }
}
