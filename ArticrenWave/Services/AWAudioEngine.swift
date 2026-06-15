// AWAudioEngine.swift — Real audio playback using AVAudioEngine + AVAudioUnitSampler
// Falls back to built-in General MIDI (iOS SF2 bank) without external soundfont
import AVFoundation
import Observation

// MARK: - Instrument definitions with GM program numbers
struct AWInstrument {
    let name: String
    let midiProgram: UInt8
    let bankMSB: UInt8
    let bankLSB: UInt8

    static let all: [AWInstrument] = [
        AWInstrument(name: "Grand Piano",   midiProgram: 0,  bankMSB: 0x79, bankLSB: 0),
        AWInstrument(name: "Violin",        midiProgram: 40, bankMSB: 0x79, bankLSB: 0),
        AWInstrument(name: "Viola",         midiProgram: 41, bankMSB: 0x79, bankLSB: 0),
        AWInstrument(name: "Cello",         midiProgram: 42, bankMSB: 0x79, bankLSB: 0),
        AWInstrument(name: "Flute",         midiProgram: 73, bankMSB: 0x79, bankLSB: 0),
        AWInstrument(name: "Oboe",          midiProgram: 68, bankMSB: 0x79, bankLSB: 0),
        AWInstrument(name: "Clarinet",      midiProgram: 71, bankMSB: 0x79, bankLSB: 0),
        AWInstrument(name: "Trumpet",       midiProgram: 56, bankMSB: 0x79, bankLSB: 0),
        AWInstrument(name: "French Horn",   midiProgram: 60, bankMSB: 0x79, bankLSB: 0),
        AWInstrument(name: "Harp",          midiProgram: 46, bankMSB: 0x79, bankLSB: 0),
    ]

    static func find(_ name: String) -> AWInstrument {
        all.first(where: { $0.name == name }) ?? all[0]
    }
}

// MARK: - Audio Engine Singleton
@Observable
class AWAudioPlayer {
    static let shared = AWAudioPlayer()

    // Playback state
    var isPlaying: Bool   = false
    var isPaused: Bool    = false
    var currentBeat: Double = 0.0
    var totalBeats: Double  = 16.0

    // Engine components
    private var engine    = AVAudioEngine()
    private var sampler   = AVAudioUnitSampler()
    private var reverb    = AVAudioUnitReverb()
    private var isSetup   = false
    private var playTimer: Timer?

    // Per-instrument samplers (lazily created)
    private var samplers: [String: AVAudioUnitSampler] = [:]

    var progress: Double { totalBeats > 0 ? currentBeat / totalBeats : 0 }

    var currentTimeString: String {
        let seconds = (currentBeat / 80.0) * 60.0 // approximate
        return String(format: "%d:%04.1f", Int(seconds)/60, seconds.truncatingRemainder(dividingBy: 60))
    }

    private init() { }

    // MARK: - Setup
    func setup() {
        guard !isSetup else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)

            engine.attach(sampler)
            engine.attach(reverb)

            reverb.loadFactoryPreset(.smallRoom)
            reverb.wetDryMix = 18

            engine.connect(sampler, to: reverb, format: nil)
            engine.connect(reverb, to: engine.mainMixerNode, format: nil)

            try engine.start()

            // Load General MIDI bank (iOS built-in)
            // Try to load DLS/SF2 from bundle first, fall back to system
            if let sf2URL = Bundle.main.url(forResource: "GeneralUser GS", withExtension: "sf2") ??
                            Bundle.main.url(forResource: "gs_soundfont", withExtension: "sf2") {
                try sampler.loadSoundBankInstrument(
                    at: sf2URL, program: 0, bankMSB: 0x79, bankLSB: 0
                )
            } else {
                // Use iOS built-in DLS
                let dlsURL = URL(fileURLWithPath: "/System/Library/Audio/Sounds/Banks/gs_instruments.dls")
                if FileManager.default.fileExists(atPath: dlsURL.path) {
                    try sampler.loadSoundBankInstrument(
                        at: dlsURL, program: 0, bankMSB: 0x79, bankLSB: 0
                    )
                }
            }
            isSetup = true
        } catch {
            print("AWAudioPlayer setup: \(error.localizedDescription)")
        }
    }

    // MARK: - Play single note
    func playNote(midiNote: UInt8, velocity: UInt8 = 90, duration: Double = 0.5, program: UInt8 = 0) {
        if !isSetup { setup() }
        sampler.sendProgramChange(program, bankMSB: 0x79, bankLSB: 0, onChannel: 0)
        sampler.startNote(midiNote, withVelocity: velocity, onChannel: 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            self.sampler.stopNote(midiNote, onChannel: 0)
        }
    }

    func playPitch(_ pitch: Pitch, instrumentName: String = "Grand Piano", duration: Double = 0.5) {
        let instr = AWInstrument.find(instrumentName)
        let midi = UInt8(max(21, min(108, pitch.midiNote)))
        playNote(midiNote: midi, duration: duration, program: instr.midiProgram)
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
        let sixteenth = 60.0 / bpm / 4.0  // seconds per sixteenth note

        playTimer?.invalidate()

        // Schedule notes from score
        let notes = extractNotes(from: document)
        scheduleNotes(notes, bpm: bpm)

        // Advance position counter
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
        engine.mainMixerNode.outputVolume = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.engine.mainMixerNode.outputVolume = 1.0
        }
    }

    func stop() {
        playTimer?.invalidate(); playTimer = nil
        isPlaying = false; isPaused = false; currentBeat = 0
    }

    func seek(to progress: Double) {
        currentBeat = progress * totalBeats
    }

    // MARK: - Note extraction
    struct ScheduledNote {
        let midiNote: UInt8
        let startTime: Double  // seconds from now
        let duration: Double
        let program: UInt8
        let channel: UInt8
    }

    private func extractNotes(from doc: ScoreDocument) -> [ScheduledNote] {
        var notes: [ScheduledNote] = []
        let bpm = Double(doc.tempo)
        let beatDur = 60.0 / bpm

        for (pi, part) in doc.parts.enumerated() {
            let prog = AWInstrument.find(part.instrument.rawValue).midiProgram
            let ch   = UInt8(min(pi, 14))
            var absoluteBeat: Double = 0

            for measure in part.measures {
                for content in measure.contents {
                    switch content {
                    case .chord(let chord):
                        let t = absoluteBeat * beatDur
                        let d = chord.totalBeats * beatDur * 0.92  // slight detach
                        for note in chord.notes {
                            let midi = UInt8(max(21, min(108, note.pitch.midiNote)))
                            notes.append(ScheduledNote(
                                midiNote: midi, startTime: t, duration: d,
                                program: prog, channel: ch
                            ))
                        }
                        absoluteBeat += chord.totalBeats
                    case .rest(let rest):
                        absoluteBeat += rest.duration.beats
                    }
                }
            }
        }
        return notes.sorted { $0.startTime < $1.startTime }
    }

    private func scheduleNotes(_ notes: [ScheduledNote], bpm: Double) {
        for note in notes {
            DispatchQueue.global(qos: .userInteractive).asyncAfter(
                deadline: .now() + note.startTime
            ) { [weak self] in
                guard let self, self.isPlaying else { return }
                self.sampler.sendProgramChange(note.program, bankMSB: 0x79, bankLSB: 0,
                                                onChannel: note.channel)
                self.sampler.startNote(note.midiNote, withVelocity: 88, onChannel: note.channel)
                DispatchQueue.global().asyncAfter(deadline: .now() + note.duration) {
                    guard self.isPlaying else { return }
                    self.sampler.stopNote(note.midiNote, onChannel: note.channel)
                }
            }
        }
    }

    // MARK: - Audio Export (WAV via offline render)
    func exportWAV(document: ScoreDocument, completion: @escaping (URL?) -> Void) {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(document.title).wav")

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Build MIDI data and use it to render offline
                let midiData = self.buildMIDI(from: document)
                let midiURL  = FileManager.default.temporaryDirectory
                    .appendingPathComponent("_render_temp.mid")
                try midiData.write(to: midiURL)

                // Use AVMIDIPlayer for offline export
                let player = try AVMIDIPlayer(contentsOf: midiURL, soundBankURL: nil)
                player.prepareToPlay()

                let duration = player.duration
                let sampleRate: Double = 44100
                let frameCount = AVAudioFrameCount(duration * sampleRate)

                let offlineEngine   = AVAudioEngine()
                let offlineSampler  = AVAudioUnitSampler()
                let offlineReverb   = AVAudioUnitReverb()
                offlineEngine.attach(offlineSampler)
                offlineEngine.attach(offlineReverb)
                offlineReverb.loadFactoryPreset(.mediumRoom)
                offlineReverb.wetDryMix = 20
                offlineEngine.connect(offlineSampler, to: offlineReverb, format: nil)
                offlineEngine.connect(offlineReverb, to: offlineEngine.mainMixerNode, format: nil)

                let format = offlineEngine.mainMixerNode.outputFormat(forBus: 0)
                try offlineEngine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
                try offlineEngine.start()

                let outputFile = try AVAudioFile(
                    forWriting: outputURL,
                    settings: [
                        AVFormatIDKey: kAudioFormatLinearPCM,
                        AVSampleRateKey: 44100,
                        AVNumberOfChannelsKey: 2,
                        AVLinearPCMBitDepthKey: 16,
                        AVLinearPCMIsFloatKey: false,
                    ]
                )

                let buffer = AVAudioPCMBuffer(
                    pcmFormat: format,
                    frameCapacity: 4096
                )!

                var rendered: AVAudioFramePosition = 0
                while rendered < AVAudioFramePosition(frameCount) {
                    let remaining = AVAudioFrameCount(AVAudioFramePosition(frameCount) - rendered)
                    let toRender = min(4096, remaining)
                    buffer.frameLength = toRender
                    let status = try offlineEngine.renderOffline(toRender, to: buffer)
                    if status == .success { try outputFile.write(from: buffer) }
                    else { break }
                    rendered += AVAudioFramePosition(toRender)
                }
                offlineEngine.stop()
                DispatchQueue.main.async { completion(outputURL) }
            } catch {
                print("WAV export: \(error)")
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    func exportM4A(wavURL: URL, completion: @escaping (URL?) -> Void) {
        let m4aURL = wavURL.deletingPathExtension().appendingPathExtension("m4a")
        let asset  = AVAsset(url: wavURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            completion(nil); return
        }
        session.outputURL  = m4aURL
        session.outputFileType = .m4a
        session.exportAsynchronously {
            DispatchQueue.main.async {
                completion(session.status == .completed ? m4aURL : nil)
            }
        }
    }

    // MARK: - MIDI builder
    func buildMIDI(from document: ScoreDocument) -> Data {
        let bpm   = document.tempo
        let ticks = 480  // ticks per quarter note

        var tracks: [Data] = []

        // Tempo track
        var tempoTrack = Data()
        let mspb = 60_000_000 / bpm
        tempoTrack += [0x00, 0xFF, 0x51, 0x03]
        tempoTrack += [UInt8((mspb >> 16) & 0xFF), UInt8((mspb >> 8) & 0xFF), UInt8(mspb & 0xFF)]
        tempoTrack += [0x00, 0xFF, 0x2F, 0x00]
        tracks.append(tempoTrack)

        for (pi, part) in document.parts.enumerated() {
            var track = Data()
            let ch = UInt8(min(pi, 14))
            let prog = AWInstrument.find(part.instrument.rawValue).midiProgram

            // Program change
            track += delta(0)
            track += [0xC0 | ch, prog]

            var tick = 0
            for measure in part.measures {
                for content in measure.contents {
                    switch content {
                    case .chord(let chord):
                        let dur = Int(chord.totalBeats * Double(ticks))
                        for note in chord.notes {
                            let midi = UInt8(max(21, min(108, note.pitch.midiNote)))
                            track += delta(0)
                            track += [0x90 | ch, midi, 88]
                        }
                        tick += dur
                        for note in chord.notes {
                            let midi = UInt8(max(21, min(108, note.pitch.midiNote)))
                            track += delta(dur)
                            track += [0x80 | ch, midi, 0]
                        }
                    case .rest(let rest):
                        tick += Int(rest.duration.beats * Double(ticks))
                    }
                }
            }
            track += delta(0)
            track += [0xFF, 0x2F, 0x00]
            tracks.append(track)
        }

        // Assemble MIDI file
        var midi = Data()
        // MThd
        midi += [0x4D, 0x54, 0x68, 0x64, 0x00, 0x00, 0x00, 0x06]
        midi += [0x00, 0x01]  // format 1
        let numTracks = UInt16(tracks.count)
        midi += [UInt8(numTracks >> 8), UInt8(numTracks & 0xFF)]
        midi += [UInt8(ticks >> 8), UInt8(ticks & 0xFF)]

        for t in tracks {
            midi += [0x4D, 0x54, 0x72, 0x6B]
            let len = UInt32(t.count)
            midi += [UInt8(len >> 24), UInt8(len >> 16 & 0xFF), UInt8(len >> 8 & 0xFF), UInt8(len & 0xFF)]
            midi += t
        }
        return midi
    }

    private func delta(_ ticks: Int) -> Data {
        var v = ticks
        var bytes: [UInt8] = []
        bytes.append(UInt8(v & 0x7F))
        v >>= 7
        while v > 0 {
            bytes.insert(UInt8((v & 0x7F) | 0x80), at: 0)
            v >>= 7
        }
        return Data(bytes)
    }
}
