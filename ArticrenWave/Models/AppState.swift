// AppState.swift — All @Observable models for iOS 17+ / iOS 27 compatibility
import SwiftUI
import Observation

// MARK: - Types needed by @Observable classes (must be in same file for macro expansion)
enum ScoreEditMode {
    case select
    case addNote(NoteDuration)
    case addRest(RestDuration)
    case addAccidental(Accidental)
    case addAccent
    case addTie
    case addSlur
    case delete
}

// AudioInstrument — mirrors the one in MusicModels for @Observable macro scope
// The actual full definition remains in MusicModels.swift

// MARK: - Audio Export Format
enum AudioExportFormat: String, CaseIterable {
    case wav = "WAV"
    case mp3 = "MP3"
    case m4a = "M4A"
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

// MARK: - App Theme
struct AWTheme {
    var accent: Color       = Color(hex: "#E040FB")
    var secondary: Color    = Color(hex: "#00E5FF")
    var background: Color   = Color(hex: "#0A0A0F")
    var cardBG: Color       = Color.white.opacity(0.05)
}

// MARK: - Storage Preference
enum StoragePreference: String {
    case device = "Device"
    case iCloud = "iCloud"
}

// MARK: - AppState
@Observable
class AppState {
    var theme = AWTheme()
    var isPianoDrawerOpen: Bool = false
    var isMainMenuOpen: Bool    = false

    static let shared = AppState()
}

// MARK: - AuthManager
@Observable
class AuthManager {
    var isSignedIn: Bool           = false
    var userFullName: String       = ""
    var userEmail: String          = ""
    var userID: String             = ""
    var authError: String?         = nil
    var storagePreference: StoragePreference = .device
    var isGuest: Bool { userID == "guest" }

    static let shared = AuthManager()

    func restoreSession() {
        guard let id = UserDefaults.standard.string(forKey: "appleUserID"),
              !id.isEmpty else { return }
        userID       = id
        userFullName = UserDefaults.standard.string(forKey: "appleUserName") ?? "Composer"
        userEmail    = UserDefaults.standard.string(forKey: "appleUserEmail") ?? ""
        isSignedIn   = true
    }

    func signOut() {
        isSignedIn   = false
        userID       = ""
        userFullName = ""
        userEmail    = ""
        UserDefaults.standard.removeObject(forKey: "appleUserID")
        UserDefaults.standard.removeObject(forKey: "appleUserName")
        UserDefaults.standard.removeObject(forKey: "appleUserEmail")
    }

    func checkiCloudAvailability(completion: @escaping (Bool) -> Void) {
        completion(false) // Safe stub for iOS 27 beta
    }
}

// MARK: - AudioEngine
@Observable
class AudioEngine {
    var currentInstrumentName: String = "Grand Piano"


    static let shared = AudioEngine()

    func loadInstrumentNamed(_ name: String) { currentInstrumentName = name }

    func playPitch(_ pitch: Pitch, duration: Double = 0.4) {
        Task { @MainActor in
            AWAudioPlayer.shared.playPitch(pitch, instrumentName: currentInstrumentName, duration: duration)
        }
    }
    func preload() {
        Task { @MainActor in AWAudioPlayer.shared.setup() }
    }
}

// MARK: - ProjectManager
@Observable
class ProjectManager {
    struct ProjectMeta: Identifiable {
        var id: UUID = UUID()
        var title: String
        var modifiedAt: Date
        var filePath: String
        var iCloudSynced: Bool = false
    }
    var recentProjects: [ProjectMeta] = []
    static let shared = ProjectManager()

    func save(document: ScoreDocument, completion: @escaping (Bool, URL?) -> Void) {
        completion(true, nil)
    }
    func load(from url: URL, completion: @escaping (ScoreDocument?) -> Void) {
        completion(nil)
    }
    func exportMIDI(from document: ScoreDocument, completion: @escaping (URL?) -> Void) {
        completion(nil)
    }
    func exportPDF(document: ScoreDocument, completion: @escaping (URL?) -> Void) {
        completion(nil)
    }
}

// MARK: - ScoreEngine
@Observable
class ScoreEngine {
    var document: ScoreDocument   = ScoreDocument.defaultDocument()
    var editMode: ScoreEditMode   = .select
    var selectedChordID: UUID?    = nil
    var validationError: String?  = nil
    var isRecording: Bool         = false
    var layoutPreset: ScoreLayoutPreset = .grandStaff

    static let shared = ScoreEngine()

    func newDocument() {
        document     = ScoreDocument.defaultDocument()
        editMode     = .select
        selectedChordID = nil
        validationError = nil
    }

    func inputNote(pitch: Pitch, in partIndex: Int, measureIndex: Int) {
        guard case .addNote(let dur) = editMode else { return }
        guard partIndex < document.parts.count else { return }
        guard measureIndex < document.parts[partIndex].measures.count else { return }
        var measure = document.parts[partIndex].measures[measureIndex]
        guard measure.remainingBeats >= dur.beats else {
            validationError = "Not enough beats remaining in this measure"
            return
        }
        let note = ScoreNote(pitch: pitch, duration: dur)
        var chord = Chord(duration: dur, beatPosition: measure.totalBeats)
        _ = chord.addNote(note)
        measure.contents.append(.chord(chord))
        document.parts[partIndex].measures[measureIndex] = measure
        validationError = nil
        if measure.isFull {
            let isLast = measureIndex == document.parts[partIndex].measures.count - 1
            if isLast {
                for i in 0..<document.parts.count {
                    document.parts[i].measures.append(Measure())
                }
            }
        }
    }

    func inputRest(in partIndex: Int, measureIndex: Int) {
        guard case .addRest(let dur) = editMode else { return }
        guard partIndex < document.parts.count else { return }
        guard measureIndex < document.parts[partIndex].measures.count else { return }
        var measure = document.parts[partIndex].measures[measureIndex]
        guard measure.remainingBeats >= dur.beats else {
            validationError = "Not enough beats for rest"
            return
        }
        let rest = ScoreRest(duration: dur, beatPosition: measure.totalBeats)
        measure.contents.append(.rest(rest))
        document.parts[partIndex].measures[measureIndex] = measure
        validationError = nil
    }

    func deleteContent(id: UUID, partIndex: Int) {
        guard partIndex < document.parts.count else { return }
        for mi in 0..<document.parts[partIndex].measures.count {
            document.parts[partIndex].measures[mi].contents.removeAll { content in
                switch content {
                case .chord(let c): return c.id == id
                case .rest(let r):  return r.id == id
                }
            }
        }
        if selectedChordID == id { selectedChordID = nil }
    }

    func moveNote(chordID: UUID, to newPitch: Pitch) {
        for pi in 0..<document.parts.count {
            for mi in 0..<document.parts[pi].measures.count {
                for ci in 0..<document.parts[pi].measures[mi].contents.count {
                    if case .chord(var c) = document.parts[pi].measures[mi].contents[ci], c.id == chordID {
                        c.notes = c.notes.map { var n = $0; n.pitch = newPitch; return n }
                        document.parts[pi].measures[mi].contents[ci] = .chord(c)
                        return
                    }
                }
            }
        }
    }

    func addPart(instrument: InstrumentFamily) {
        let count = document.parts.first?.measures.count ?? 1
        var part = Part(instrument: instrument, clef: instrument.clef, measures: [])
        part.measures = (0..<count).map { _ in Measure() }
        document.parts.append(part)
    }

    func applyLayoutPreset(_ preset: ScoreLayoutPreset) {
        layoutPreset = preset
        let count = max(document.parts.first?.measures.count ?? 1, 1)
        document.parts = preset.instruments.map { instr in
            var part = Part(instrument: instr, clef: instr.clef, measures: [])
            part.measures = (0..<count).map { _ in Measure() }
            return part
        }
    }

    func startRecording() { isRecording = true }
    func stopRecording()  { isRecording = false }
}
