// AppState.swift — iOS 17+ @Observable pattern
import SwiftUI
import Observation

@Observable
class AppState {
    var isPianoDrawerOpen: Bool = false
    var isMainMenuOpen: Bool = false
    var themeAccent: Color = Color(hex: "#E040FB")
    var themeSecondary: Color = Color(hex: "#00E5FF")
    var themeBackground: Color = Color(hex: "#0A0A0F")

    static let shared = AppState()
}

@Observable
class AuthManager {
    var isSignedIn: Bool = false
    var userFullName: String = ""
    var userID: String = ""
    var authError: String? = nil
    var storagePreference: String = "Device"
    var isGuest: Bool { userID == "guest" }

    static let shared = AuthManager()

    func restoreSession() {
        guard let id = UserDefaults.standard.string(forKey: "appleUserID"),
              !id.isEmpty else { return }
        userID = id
        userFullName = UserDefaults.standard.string(forKey: "appleUserName") ?? "Composer"
        isSignedIn = true
    }

    func signOut() {
        isSignedIn = false
        userID = ""
        userFullName = ""
        UserDefaults.standard.removeObject(forKey: "appleUserID")
        UserDefaults.standard.removeObject(forKey: "appleUserName")
    }

    func checkiCloudAvailability(completion: @escaping (Bool) -> Void) {
        // Simplified — avoid CloudKit import crash on iOS 27 beta
        completion(false)
    }
}

@Observable
class ScoreEngine {
    var document: ScoreDocument = ScoreDocument.defaultDocument()
    var editMode: ScoreEditMode = .select
    var selectedChordID: UUID? = nil
    var validationError: String? = nil
    var isRecording: Bool = false

    static let shared = ScoreEngine()

    func newDocument() {
        document = ScoreDocument.defaultDocument()
        editMode = .select
        selectedChordID = nil
        validationError = nil
    }

    func inputNote(pitch: Pitch, in partIndex: Int, measureIndex: Int) {
        guard case .addNote(let dur) = editMode else { return }
        guard partIndex < document.parts.count else { return }
        guard measureIndex < document.parts[partIndex].measures.count else { return }
        var measure = document.parts[partIndex].measures[measureIndex]
        guard measure.remainingBeats >= dur.beats else {
            validationError = "Not enough beats remaining"
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

    func addPart(instrument: InstrumentFamily) {
        let measureCount = document.parts.first?.measures.count ?? 1
        var part = Part(instrument: instrument, clef: instrument.clef, measures: [])
        part.measures = (0..<measureCount).map { _ in Measure() }
        document.parts.append(part)
    }

    func startRecording() { isRecording = true }
    func stopRecording() { isRecording = false }
}

@Observable
class AudioEngine {
    var currentInstrument: AudioInstrument = .grandPiano

    static let shared = AudioEngine()

    func playPitch(_ pitch: Pitch, duration: Double = 0.4) {
        // Safe stub — AVAudioEngine setup deferred to avoid iOS 27 crash
        DispatchQueue.global(qos: .userInteractive).async {
            // Will be wired up after stable launch confirmed
        }
    }

    func loadInstrument(_ instr: AudioInstrument) {
        currentInstrument = instr
    }
}

@Observable
class ProjectManager {
    var recentProjects: [String] = []
    static let shared = ProjectManager()

    func save(document: ScoreDocument, completion: @escaping (Bool) -> Void) {
        // Safe stub
        completion(true)
    }
}
