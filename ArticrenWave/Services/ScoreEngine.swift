// ScoreEngine.swift — Score editing state machine for ArticrenWave
import SwiftUI
import Combine
import PDFKit
import MobileCoreServices

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

class ScoreEngine: ObservableObject {
    @Published var document: ScoreDocument = ScoreDocument.defaultDocument()
    @Published var editMode: ScoreEditMode = .select
    @Published var selectedPartIndex: Int = 0
    @Published var selectedMeasureIndex: Int = 0
    @Published var selectedChordID: UUID? = nil
    @Published var selectedInstrument: InstrumentFamily = .piano
    @Published var tieStartChordID: UUID? = nil
    @Published var validationError: String? = nil
    @Published var isRecording: Bool = false
    @Published var layoutPreset: ScoreLayoutPreset = .grandStaff

    // MARK: - Note Input
    func inputNote(pitch: Pitch, in partIndex: Int, measureIndex: Int) {
        guard case .addNote(let dur) = editMode else { return }
        guard partIndex < document.parts.count else { return }
        guard measureIndex < document.parts[partIndex].measures.count else { return }

        var measure = document.parts[partIndex].measures[measureIndex]

        // Check beat budget
        guard measure.remainingBeats >= dur.beats else {
            validationError = "Not enough beats remaining in this measure (need \(dur.beats), have \(measure.remainingBeats))"
            return
        }

        let note = ScoreNote(pitch: pitch, duration: dur)
        let beatPos = measure.totalBeats

        // Try to add to last chord if same beat position (building a chord)
        if var lastContent = measure.contents.last,
           case .chord(var chord) = lastContent,
           chord.beatPosition == beatPos - chord.totalBeats {
            // same rhythmic slot — add note to chord
            let added = chord.addNote(note)
            if !added {
                validationError = "Cannot add: chord already has 4 notes or note is out of range (max 4-staff-position span)"
                return
            }
            measure.contents[measure.contents.count - 1] = .chord(chord)
        } else {
            // New chord
            var chord = Chord(duration: dur, beatPosition: beatPos)
            _ = chord.addNote(note)
            measure.contents.append(.chord(chord))
        }

        document.parts[partIndex].measures[measureIndex] = measure
        document.modifiedAt = Date()
        validationError = nil
        appendMeasureIfNeeded(partIndex: partIndex, measureIndex: measureIndex)
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
        document.modifiedAt = Date()
        validationError = nil
        appendMeasureIfNeeded(partIndex: partIndex, measureIndex: measureIndex)
    }

    private func appendMeasureIfNeeded(partIndex: Int, measureIndex: Int) {
        let measure = document.parts[partIndex].measures[measureIndex]
        if measure.isFull {
            // Auto-add new measure if this was the last
            let isLast = measureIndex == document.parts[partIndex].measures.count - 1
            if isLast {
                for i in 0..<document.parts.count {
                    document.parts[i].measures.append(Measure())
                }
            }
        }
    }

    // MARK: - Tie / Slur
    func beginTieOrSlur(chordID: UUID, isSlur: Bool) {
        tieStartChordID = chordID
    }

    func endTieOrSlur(chordID: UUID, isSlur: Bool, partIndex: Int) {
        guard let startID = tieStartChordID else { return }
        let tie = Tie(fromChordID: startID, toChordID: chordID, isSlur: isSlur)
        // Add tie to the measure containing the start chord
        for mi in 0..<document.parts[partIndex].measures.count {
            for content in document.parts[partIndex].measures[mi].contents {
                if case .chord(let c) = content, c.id == startID {
                    document.parts[partIndex].measures[mi].ties.append(tie)
                    tieStartChordID = nil
                    return
                }
            }
        }
        tieStartChordID = nil
    }

    func deleteTie(tieID: UUID, partIndex: Int) {
        for mi in 0..<document.parts[partIndex].measures.count {
            document.parts[partIndex].measures[mi].ties.removeAll { $0.id == tieID }
        }
    }

    // MARK: - Accidental on selected note
    func applyAccidental(_ acc: Accidental, to chordID: UUID, noteIndex: Int, partIndex: Int) {
        for mi in 0..<document.parts[partIndex].measures.count {
            for ci in 0..<document.parts[partIndex].measures[mi].contents.count {
                if case .chord(var chord) = document.parts[partIndex].measures[mi].contents[ci],
                   chord.id == chordID,
                   noteIndex < chord.notes.count {
                    chord.notes[noteIndex].accidental = acc
                    document.parts[partIndex].measures[mi].contents[ci] = .chord(chord)
                    return
                }
            }
        }
    }

    // MARK: - Delete
    func deleteContent(id: UUID, partIndex: Int) {
        for mi in 0..<document.parts[partIndex].measures.count {
            document.parts[partIndex].measures[mi].contents.removeAll { $0.id == id }
        }
        document.modifiedAt = Date()
    }

    // MARK: - Layout Preset
    func applyLayoutPreset(_ preset: ScoreLayoutPreset) {
        layoutPreset = preset
        let instruments = preset.instruments
        let measureCount = max(document.parts.first?.measures.count ?? 1, 1)
        document.parts = instruments.map { instr in
            var part = Part(instrument: instr, clef: instr.clef, measures: [])
            part.measures = (0..<measureCount).map { _ in Measure() }
            return part
        }
        document.modifiedAt = Date()
    }

    func addPart(instrument: InstrumentFamily) {
        let measureCount = document.parts.first?.measures.count ?? 1
        var part = Part(instrument: instrument, clef: instrument.clef, measures: [])
        part.measures = (0..<measureCount).map { _ in Measure() }
        document.parts.append(part)
    }

    // MARK: - Live Recording
    func startRecording() { isRecording = true }
    func stopRecording() { isRecording = false }

    func recordLiveNote(pitch: Pitch, instrument: InstrumentFamily, duration: NoteDuration) {
        guard isRecording else { return }
        // Find or use last part matching instrument
        var partIndex = document.parts.firstIndex(where: { $0.instrument == instrument })
        if partIndex == nil {
            addPart(instrument: instrument)
            partIndex = document.parts.count - 1
        }
        guard let pi = partIndex else { return }
        let lastMeasure = document.parts[pi].measures.count - 1
        let savedMode = editMode
        editMode = .addNote(duration)
        inputNote(pitch: pitch, in: pi, measureIndex: lastMeasure)
        editMode = savedMode
    }

    // MARK: - New Document
    func newDocument() {
        document = ScoreDocument.defaultDocument()
        editMode = .select
        selectedChordID = nil
        validationError = nil
    }
}
