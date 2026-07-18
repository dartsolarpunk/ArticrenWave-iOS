// AppState.swift — All @Observable models for iOS 17+ / iOS 27 compatibility
import SwiftUI
import Observation

// MARK: - Types needed by @Observable classes (must be in same file for macro expansion)
enum ScoreEditMode: Equatable {
    case select
    case move            // select note then drag to reposition
    case addNote(NoteDuration)
    case addRest(RestDuration)
    case addAccidental(Accidental)
    case addAccent(AccentType)
    case addTie
    case addSlur
    case delete

    static func == (lhs: ScoreEditMode, rhs: ScoreEditMode) -> Bool {
        switch (lhs, rhs) {
        case (.select, .select), (.move, .move),
             (.addTie, .addTie),
             (.addSlur, .addSlur), (.delete, .delete): return true
        case (.addNote(let a), .addNote(let b)): return a == b
        case (.addRest(let a), .addRest(let b)): return a == b
        case (.addAccidental(let a), .addAccidental(let b)): return a == b
        case (.addAccent(let a), .addAccent(let b)): return a == b
        default: return false
        }
    }
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

    func loadInstrumentNamed(_ name: String) {
        currentInstrumentName = name
        AWAudioPlayer.shared.prewarm(instrumentName: name)
    }

    func playPitch(_ pitch: Pitch, duration: Double = 0.4) {
        AWAudioPlayer.shared.playPitch(pitch, instrumentName: currentInstrumentName, duration: duration)
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
    var selectedNoteID: UUID? = nil

    // MARK: - Undo / Redo
    private var undoStack: [ScoreDocument] = []
    private var redoStack: [ScoreDocument] = []
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func snapshot() {
        undoStack.append(document)
        if undoStack.count > 50 { undoStack.removeFirst() }
        redoStack.removeAll()
    }
    func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(document)
        document = prev
        selectedChordID = nil; selectedNoteID = nil
    }
    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(document)
        document = next
        selectedChordID = nil; selectedNoteID = nil
    }
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

    // Append a NEW chord at the next beat slot (tap on empty area)
    func inputNote(pitch: Pitch, in partIndex: Int, measureIndex: Int) {
        guard case .addNote(let dur) = editMode else { return }
        guard partIndex < document.parts.count,
              measureIndex < document.parts[partIndex].measures.count else { return }
        var measure = document.parts[partIndex].measures[measureIndex]
        guard measure.remainingBeats >= dur.beats else {
            validationError = "Not enough beats remaining in this measure"
            return
        }
        snapshot()
        let note  = ScoreNote(pitch: pitch, duration: dur)
        var chord = Chord(duration: dur, beatPosition: measure.totalBeats)
        _ = chord.addNote(note)
        measure.contents.append(.chord(chord))
        document.parts[partIndex].measures[measureIndex] = measure
        validationError = nil
        selectedChordID = chord.id
        selectedNoteID  = note.id
        if measure.isFull {
            let isLast = measureIndex == document.parts[partIndex].measures.count - 1
            if isLast {
                for i in 0..<document.parts.count {
                    document.parts[i].measures.append(Measure())
                }
            }
        }
    }

    // Add note to an EXISTING chord (tap directly on that chord's slot).
    // Same staff position → replace; different → stack (max 4, span ≤7).
    func addNoteToChord(chordID: UUID, pitch: Pitch, partIndex: Int, measureIndex: Int) {
        guard case .addNote(let dur) = editMode else { return }
        guard partIndex < document.parts.count,
              measureIndex < document.parts[partIndex].measures.count else { return }
        var measure = document.parts[partIndex].measures[measureIndex]
        guard let ci = measure.contents.firstIndex(where: { $0.id == chordID }),
              case .chord(var ch) = measure.contents[ci] else { return }

        let oldBeats = ch.totalBeats
        var cand = ch
        if let idx = cand.notes.firstIndex(where: { $0.pitch.staffPosition == pitch.staffPosition }) {
            cand.notes[idx] = ScoreNote(pitch: pitch, duration: dur)
        } else {
            guard cand.notes.count < 4 else { validationError = "Chords hold up to 4 notes"; return }
            if let first = cand.notes.first,
               abs(pitch.staffPosition - first.pitch.staffPosition) > 7 {
                validationError = "Chord notes must stay within an octave span"; return
            }
            cand.notes.append(ScoreNote(pitch: pitch, duration: dur))
            cand.notes.sort { $0.pitch.staffPosition < $1.pitch.staffPosition }
        }
        cand.duration = cand.notes.map { $0.duration }.max(by: { $0.beats < $1.beats }) ?? dur

        let newTotal = measure.totalBeats - oldBeats + cand.totalBeats
        guard newTotal <= 4.0 else {
            validationError = "Not enough beats remaining in this measure"; return
        }
        snapshot()
        ch = cand
        measure.contents[ci] = .chord(ch)
        document.parts[partIndex].measures[measureIndex] = measure
        validationError = nil
        selectedChordID = ch.id
    }

    // Delete one note from a chord (removes chord when empty)
    func deleteNote(noteID: UUID, chordID: UUID, partIndex: Int) {
        guard partIndex < document.parts.count else { return }
        for mi in 0..<document.parts[partIndex].measures.count {
            guard let ci = document.parts[partIndex].measures[mi].contents.firstIndex(where: { $0.id == chordID }),
                  case .chord(var ch) = document.parts[partIndex].measures[mi].contents[ci] else { continue }
            guard ch.notes.contains(where: { $0.id == noteID }) else { continue }
            snapshot()
            ch.notes.removeAll { $0.id == noteID }
            if ch.notes.isEmpty {
                document.parts[partIndex].measures[mi].contents.remove(at: ci)
                document.ties.removeAll { $0.fromChordID == chordID || $0.toChordID == chordID }
            } else {
                ch.duration = ch.notes.map { $0.duration }.max(by: { $0.beats < $1.beats }) ?? ch.duration
                document.parts[partIndex].measures[mi].contents[ci] = .chord(ch)
            }
            if selectedNoteID == noteID { selectedNoteID = nil }
            return
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

    // MARK: - Tie / Slur two-tap workflow
    var pendingTieStart: UUID? = nil

    func handleTieTap(chordID: UUID) {
        let isSlur: Bool
        switch editMode {
        case .addTie:  isSlur = false
        case .addSlur: isSlur = true
        default: return
        }
        if let start = pendingTieStart {
            guard start != chordID else { pendingTieStart = nil; return }
            snapshot()
            document.ties.append(Tie(fromChordID: start, toChordID: chordID, isSlur: isSlur))
            pendingTieStart = nil
            editMode = .select   // auto-toggle off after second pick
        } else {
            pendingTieStart = chordID
        }
    }

    func deleteTie(id: UUID) {
        snapshot()
        document.ties.removeAll { $0.id == id }
    }

    func applyAccent(_ type: AccentType, chordID: UUID, partIndex: Int) {
        for mi in 0..<document.parts[partIndex].measures.count {
            for ci in 0..<document.parts[partIndex].measures[mi].contents.count {
                if case .chord(var ch) = document.parts[partIndex].measures[mi].contents[ci], ch.id == chordID {
                    // Apply to top note (last in sorted order)
                    if let topIdx = ch.notes.indices.last {
                        ch.notes[topIdx].accentType = ch.notes[topIdx].accentType == type ? nil : type
                    }
                    document.parts[partIndex].measures[mi].contents[ci] = .chord(ch)
                    return
                }
            }
        }
    }

    func deleteContent(id: UUID, partIndex: Int) {
        guard partIndex < document.parts.count else { return }
        let exists = document.parts[partIndex].measures.contains { m in
            m.contents.contains { $0.id == id }
        }
        guard exists else { return }
        snapshot()
        for mi in 0..<document.parts[partIndex].measures.count {
            document.parts[partIndex].measures[mi].contents.removeAll { content in
                switch content {
                case .chord(let c): return c.id == id
                case .rest(let r):  return r.id == id
                }
            }
        }
        if selectedChordID == id { selectedChordID = nil }
        document.ties.removeAll { $0.fromChordID == id || $0.toChordID == id }
    }

    func moveNote(chordID: UUID, to newPitch: Pitch) {
        snapshot()
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
