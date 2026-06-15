// AudioEngine.swift — Sound playback and audio export for ArticrenWave
import AVFoundation
import Combine

enum AudioInstrument: String, CaseIterable {
    case grandPiano = "Grand Piano"
    case violin = "Violin"
    case viola = "Viola"
    case cello = "Cello"
    case flute = "Flute"
    case oboe = "Oboe"
    case clarinet = "Clarinet"
    case trumpet = "Trumpet"
    case frenchHorn = "French Horn"
    case harp = "Harp"

    var soundFontFileName: String {
        // These reference bundled .sf2 / .aupreset or sample files
        switch self {
        case .grandPiano: return "GrandPiano"
        case .violin: return "Violin"
        case .viola: return "Viola"
        case .cello: return "Cello"
        case .flute: return "Flute"
        case .oboe: return "Oboe"
        case .clarinet: return "Clarinet"
        case .trumpet: return "Trumpet"
        case .frenchHorn: return "FrenchHorn"
        case .harp: return "Harp"
        }
    }

    // MIDI program number (General MIDI)
    var midiProgram: UInt8 {
        switch self {
        case .grandPiano: return 0
        case .violin: return 40
        case .viola: return 41
        case .cello: return 42
        case .flute: return 73
        case .oboe: return 68
        case .clarinet: return 71
        case .trumpet: return 56
        case .frenchHorn: return 60
        case .harp: return 46
        }
    }
}

class AudioEngine: ObservableObject {
    @Published var currentInstrument: AudioInstrument = .grandPiano
    @Published var isExporting: Bool = false
    @Published var exportProgress: Double = 0

    private var engine = AVAudioEngine()
    private var sampler = AVAudioUnitSampler()
    private var reverb = AVAudioUnitReverb()
    private var mixer = AVAudioMixerNode()
    private var isSetup = false

    func preloadSounds() {
        // Deferred — called lazily on first key press to avoid crash-on-launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.setupEngine()
        }
    }

    private func setupEngine() {
        guard !isSetup else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default,
                options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)

            engine.attach(sampler)
            engine.attach(reverb)
            engine.attach(mixer)

            reverb.loadFactoryPreset(.mediumRoom)
            reverb.wetDryMix = 20

            engine.connect(sampler, to: reverb, format: nil)
            engine.connect(reverb, to: engine.mainMixerNode, format: nil)

            try engine.start()
            isSetup = true
        } catch {
            // Non-fatal — audio simply won't play until retry
            print("AudioEngine setup: \(error.localizedDescription)")
        }
    }

    func loadInstrument(_ instrument: AudioInstrument) {
        currentInstrument = instrument
        // Load bundled SoundFont or use MIDI bank
        if let sfURL = Bundle.main.url(forResource: instrument.soundFontFileName, withExtension: "sf2") {
            do {
                try sampler.loadSoundBankInstrument(
                    at: sfURL,
                    program: instrument.midiProgram,
                    bankMSB: 0x79,
                    bankLSB: 0x00
                )
            } catch {
                print("SoundFont load error: \(error)")
            }
        } else {
            // Fallback: use default MIDI bank via AVAudioUnitSampler
            sampler.sendProgramChange(instrument.midiProgram, onChannel: 0)
        }
    }

    // MARK: - Play a single MIDI note
    func playNote(midiNote: UInt8, velocity: UInt8 = 100, duration: Double = 0.5) {
        guard isSetup else { setupEngine(); return }
        sampler.startNote(midiNote, withVelocity: velocity, onChannel: 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            self.sampler.stopNote(midiNote, onChannel: 0)
        }
    }

    func playPitch(_ pitch: Pitch, duration: Double = 0.5) {
        let midi = midiNote(pitch.midiNote)
        playNote(midiNote: midi, duration: duration)
    }

    // MARK: - Render score to audio file
    func renderScoreToAudio(document: ScoreDocument, format: AudioExportFormat,
                             completion: @escaping (URL?) -> Void) {
        isExporting = true
        exportProgress = 0

        DispatchQueue.global(qos: .userInitiated).async {
            let outputURL = FileManager.default
                .temporaryDirectory
                .appendingPathComponent("\(document.title).\(format.fileExtension)")

            // Build a sequence of MIDI events from the score
            let midiSequence = self.buildMIDISequence(from: document)

            // Write to file using AVAudioSequencer → offline render
            do {
                let offlineEngine = AVAudioEngine()
                let offlineSampler = AVAudioUnitSampler()
                let offlineReverb = AVAudioUnitReverb()

                offlineEngine.attach(offlineSampler)
                offlineEngine.attach(offlineReverb)
                offlineEngine.connect(offlineSampler, to: offlineReverb, format: nil)
                offlineEngine.connect(offlineReverb, to: offlineEngine.mainMixerNode, format: nil)

                offlineReverb.loadFactoryPreset(.largeRoom)
                offlineReverb.wetDryMix = 25

                if let sfURL = Bundle.main.url(forResource: "GrandPiano", withExtension: "sf2") {
                    try offlineSampler.loadSoundBankInstrument(at: sfURL, program: 0, bankMSB: 0x79, bankLSB: 0x00)
                }

                let audioFormat = offlineEngine.mainMixerNode.outputFormat(forBus: 0)
                try offlineEngine.enableManualRenderingMode(
                    .offline,
                    format: audioFormat,
                    maximumFrameCount: 4096
                )
                try offlineEngine.start()

                let sequencer = AVAudioSequencer(audioEngine: offlineEngine)
                let midiData = midiSequence.data()
                try sequencer.load(from: midiData, options: .smf_ChannelsToTracks)
                sequencer.prepareToPlay()
                sequencer.rate = 1.0

                // Determine total duration in seconds
                let durationSeconds = midiSequence.durationSeconds(bpm: document.tempo)

                // Write output audio file
                let outputFile = try AVAudioFile(
                    forWriting: outputURL,
                    settings: audioFormat.settings
                )

                let buffer = AVAudioPCMBuffer(
                    pcmFormat: audioFormat,
                    frameCapacity: 4096
                )!

                try sequencer.start()

                var renderTime: Double = 0
                while renderTime < durationSeconds + 2.0 {
                    let frameCount = min(4096, AVAudioFrameCount((durationSeconds + 2.0 - renderTime) * audioFormat.sampleRate))
                    guard frameCount > 0 else { break }
                    let status = try offlineEngine.renderOffline(frameCount, to: buffer)
                    switch status {
                    case .success:
                        try outputFile.write(from: buffer)
                        renderTime += Double(frameCount) / audioFormat.sampleRate
                        DispatchQueue.main.async {
                            self.exportProgress = min(renderTime / durationSeconds, 1.0)
                        }
                    case .insufficientDataFromInputNode, .cannotDoInCurrentContext, .error:
                        break
                    @unknown default: break
                    }
                }

                offlineEngine.stop()

                // Convert to MP3 if needed (requires LAME or system encoder)
                if format == .mp3 {
                    // iOS doesn't have native LAME; export as M4A with AAC then rename
                    // In production: integrate LAME framework or use AudioConverter
                    let m4aURL = outputURL.deletingPathExtension().appendingPathExtension("m4a")
                    try self.convertToM4A(inputURL: outputURL, outputURL: m4aURL)
                    DispatchQueue.main.async {
                        self.isExporting = false
                        completion(m4aURL)
                    }
                } else {
                    DispatchQueue.main.async {
                        self.isExporting = false
                        completion(outputURL)
                    }
                }

            } catch {
                print("Audio render error: \(error)")
                DispatchQueue.main.async {
                    self.isExporting = false
                    completion(nil)
                }
            }
        }
    }

    private func convertToM4A(inputURL: URL, outputURL: URL) throws {
        let asset = AVAsset(url: inputURL)
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else { throw NSError(domain: "Export", code: -1) }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a

        let sema = DispatchSemaphore(value: 0)
        exportSession.exportAsynchronously { sema.signal() }
        sema.wait()
    }

    // MARK: - MIDI Sequence Builder
    func buildMIDISequence(from document: ScoreDocument) -> SimpleMIDISequence {
        let seq = SimpleMIDISequence(bpm: document.tempo)
        let beatsPerSecond = Double(document.tempo) / 60.0

        for (partIdx, part) in document.parts.enumerated() {
            let channel: UInt8 = UInt8(partIdx % 15) + (partIdx >= 9 ? 1 : 0)
            let program = AudioInstrument.allCases.first(where: {
                $0.rawValue == part.instrument.rawValue
            })?.midiProgram ?? 0
            seq.addProgramChange(channel: channel, program: program)

            var absoluteBeat: Double = 0
            for measure in part.measures {
                for content in measure.contents {
                    switch content {
                    case .chord(let chord):
                        let startTime = absoluteBeat / beatsPerSecond
                        let durTime = chord.totalBeats / beatsPerSecond
                        for note in chord.notes {
                            let midi = UInt8(clamping: note.pitch.midiNote)
                            seq.addNote(channel: channel, pitch: midi,
                                        start: startTime, duration: durTime)
                        }
                        absoluteBeat += chord.totalBeats
                    case .rest(let rest):
                        absoluteBeat += rest.duration.beats
                    }
                }
            }
        }
        return seq
    }
}

// MARK: - Export Format
enum AudioExportFormat: String, CaseIterable {
    case wav = "WAV"
    case mp3 = "MP3"
    case m4a = "M4A (AAC)"
    case midi = "MIDI"

    var fileExtension: String {
        switch self {
        case .wav: return "wav"
        case .mp3: return "mp3"
        case .m4a: return "m4a"
        case .midi: return "mid"
        }
    }
}

// MARK: - Simple MIDI Sequence helper
class SimpleMIDISequence {
    struct MIDIEvent {
        var time: Double
        var data: [UInt8]
    }

    var events: [MIDIEvent] = []
    var bpm: Int

    init(bpm: Int) { self.bpm = bpm }

    func addProgramChange(channel: UInt8, program: UInt8) {
        events.append(MIDIEvent(time: 0, data: [0xC0 | (channel & 0xF), program]))
    }

    func addNote(channel: UInt8, pitch: UInt8, start: Double, duration: Double) {
        events.append(MIDIEvent(time: start, data: [0x90 | (channel & 0xF), pitch, 100]))
        events.append(MIDIEvent(time: start + duration - 0.05, data: [0x80 | (channel & 0xF), pitch, 0]))
    }

    func durationSeconds(bpm: Int) -> Double {
        events.map { $0.time }.max() ?? 4.0
    }

    func data() -> Data {
        // Build minimal Type 1 MIDI file
        var midi = Data()
        // Header chunk
        midi.append(contentsOf: [0x4D,0x54,0x68,0x64]) // MThd
        midi.append(contentsOf: [0,0,0,6]) // length
        midi.append(contentsOf: [0,1]) // format 1
        midi.append(contentsOf: [0,1]) // 1 track
        midi.append(contentsOf: [0,0x60]) // 96 ticks/quarter

        // Track chunk
        var track = Data()
        let sortedEvents = events.sorted { $0.time < $1.time }
        var lastTick: Int = 0
        let ticksPerSecond = 96 * bpm / 60

        // Tempo event
        track.append(0x00) // delta
        track.append(contentsOf: [0xFF,0x51,0x03])
        let microsecondsPerBeat = 60_000_000 / bpm
        track.append(UInt8((microsecondsPerBeat >> 16) & 0xFF))
        track.append(UInt8((microsecondsPerBeat >> 8) & 0xFF))
        track.append(UInt8(microsecondsPerBeat & 0xFF))

        for event in sortedEvents {
            let tick = Int(event.time * Double(ticksPerSecond))
            let delta = max(0, tick - lastTick)
            lastTick = tick
            track.append(contentsOf: encodeDeltaTime(delta))
            track.append(contentsOf: event.data)
        }
        // End of track
        track.append(contentsOf: [0x00, 0xFF, 0x2F, 0x00])

        midi.append(contentsOf: [0x4D,0x54,0x72,0x6B]) // MTrk
        let trackLen = UInt32(track.count)
        midi.append(UInt8((trackLen >> 24) & 0xFF))
        midi.append(UInt8((trackLen >> 16) & 0xFF))
        midi.append(UInt8((trackLen >> 8) & 0xFF))
        midi.append(UInt8(trackLen & 0xFF))
        midi.append(contentsOf: track)

        return midi
    }

    private func encodeDeltaTime(_ value: Int) -> [UInt8] {
        var v = value
        var bytes: [UInt8] = []
        bytes.append(UInt8(v & 0x7F))
        v >>= 7
        while v > 0 {
            bytes.insert(UInt8((v & 0x7F) | 0x80), at: 0)
            v >>= 7
        }
        return bytes
    }
}

// MARK: - Static builder for use outside AudioEngine
extension SimpleMIDISequence {
    static func build(from document: ScoreDocument) -> SimpleMIDISequence {
        let eng = AudioEngine()
        return eng.buildMIDISequence(from: document)
    }
}
