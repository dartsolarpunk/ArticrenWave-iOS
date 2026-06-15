// MusicModels.swift — Core music theory data models for ArticrenWave
import Foundation
import SwiftUI

// MARK: - Note Duration
enum NoteDuration: String, CaseIterable, Codable {
    case whole = "whole"         // 4 beats
    case half = "half"           // 2 beats
    case quarter = "quarter"     // 1 beat
    case eighth = "eighth"       // 0.5 beats
    case sixteenth = "sixteenth" // 0.25 beats

    var beats: Double {
        switch self {
        case .whole: return 4.0
        case .half: return 2.0
        case .quarter: return 1.0
        case .eighth: return 0.5
        case .sixteenth: return 0.25
        }
    }

    var label: String {
        switch self {
        case .whole: return "𝅝"
        case .half: return "𝅗𝅥"
        case .quarter: return "𝅘𝅥"
        case .eighth: return "𝅘𝅥𝅮"
        case .sixteenth: return "𝅘𝅥𝅯"
        }
    }

    var isFilled: Bool {
        switch self {
        case .whole, .half: return false
        case .quarter, .eighth, .sixteenth: return true
        }
    }

    var hasStem: Bool { self != .whole }
    var tailCount: Int {
        switch self {
        case .eighth: return 1
        case .sixteenth: return 2
        default: return 0
        }
    }
}

// MARK: - Rest Duration (mirrors NoteDuration)
enum RestDuration: String, CaseIterable, Codable {
    case whole, half, quarter, eighth, sixteenth

    var beats: Double {
        switch self {
        case .whole: return 4.0
        case .half: return 2.0
        case .quarter: return 1.0
        case .eighth: return 0.5
        case .sixteenth: return 0.25
        }
    }
}

// MARK: - Pitch
enum PitchClass: Int, CaseIterable, Codable {
    case C=0, Db, D, Eb, E, F, Gb, G, Ab, A, Bb, B

    var name: String {
        ["C","C#/Db","D","D#/Eb","E","F","F#/Gb","G","G#/Ab","A","A#/Bb","B"][rawValue]
    }
    var isNatural: Bool { [0,2,4,5,7,9,11].contains(rawValue) }
}

struct Pitch: Codable, Equatable, Hashable {
    var pitchClass: PitchClass
    var octave: Int   // 1–7 for piano; middle C = C4

    var midiNote: Int { (octave + 1) * 12 + pitchClass.rawValue }
    var displayName: String { "\(pitchClass.name)\(octave)" }

    // Staff line position relative to middle C (C4 = 0)
    // Positive = higher, negative = lower
    var staffPosition: Int {
        let c4midi = 60
        let diff = midiNote - c4midi
        // Each diatonic step ≈ diff/2 approx; use chromatic offset mapping
        let diatonicMap: [Int: Int] = [0:0,2:1,4:2,5:3,7:4,9:5,11:6]
        let octaveDiff = (midiNote / 12) - (c4midi / 12)
        let noteInOctave = midiNote % 12
        // Find nearest diatonic
        var bestDia = 0
        var bestDist = 99
        for (chrom, dia) in diatonicMap {
            let d = abs(chrom - noteInOctave)
            if d < bestDist { bestDist = d; bestDia = dia }
        }
        return octaveDiff * 7 + bestDia
    }

    static let middleC = Pitch(pitchClass: .C, octave: 4)
}

// MARK: - Accidental
enum Accidental: String, Codable {
    case sharp = "sharp"
    case flat = "flat"
    case natural = "natural"
    case none = "none"
}

// MARK: - Note (single pitch on staff)
struct ScoreNote: Identifiable, Codable {
    var id: UUID = UUID()
    var pitch: Pitch
    var duration: NoteDuration
    var accidental: Accidental = .none
    var hasAccent: Bool = false   // accent/marcato symbol
}

// MARK: - Chord (up to 4 notes, stacked within 4-note range)
struct Chord: Identifiable, Codable {
    var id: UUID = UUID()
    var notes: [ScoreNote] = []      // max 4 notes
    var duration: NoteDuration       // all notes in chord share duration
    var beatPosition: Double         // position in measure (0.0 ... <4.0)

    var totalBeats: Double { duration.beats }

    mutating func addNote(_ note: ScoreNote) -> Bool {
        guard notes.count < 4 else { return false }
        // Validate: all notes within 4-staff-position range of first note
        if let first = notes.first {
            let range = abs(note.pitch.staffPosition - first.pitch.staffPosition)
            guard range <= 4 else { return false }
        }
        // Replace if same staff position
        if let idx = notes.firstIndex(where: { $0.pitch.staffPosition == note.pitch.staffPosition }) {
            notes[idx] = note
        } else {
            notes.append(note)
        }
        return true
    }
}

// MARK: - Rest
struct ScoreRest: Identifiable, Codable {
    var id: UUID = UUID()
    var duration: RestDuration
    var beatPosition: Double
}

// MARK: - Beat slot (chord OR rest)
enum BeatContent: Identifiable, Codable {
    case chord(Chord)
    case rest(ScoreRest)

    var id: UUID {
        switch self {
        case .chord(let c): return c.id
        case .rest(let r): return r.id
        }
    }
    var beats: Double {
        switch self {
        case .chord(let c): return c.totalBeats
        case .rest(let r): return r.duration.beats
        }
    }
    var beatPosition: Double {
        switch self {
        case .chord(let c): return c.beatPosition
        case .rest(let r): return r.beatPosition
        }
    }
}

// MARK: - Articulation
struct Tie: Identifiable, Codable {
    var id: UUID = UUID()
    var fromChordID: UUID
    var toChordID: UUID
    var isSlur: Bool  // false = tie (above), true = slur (below)
}

// MARK: - Measure
struct Measure: Identifiable, Codable {
    var id: UUID = UUID()
    var contents: [BeatContent] = []
    var ties: [Tie] = []

    var totalBeats: Double { contents.reduce(0) { $0 + $1.beats } }
    var remainingBeats: Double { 4.0 - totalBeats }
    var isFull: Bool { totalBeats >= 4.0 }

    mutating func addContent(_ c: BeatContent) -> Bool {
        guard totalBeats + c.beats <= 4.0 else { return false }
        contents.append(c)
        return true
    }
}

// MARK: - Staff / Part
enum InstrumentFamily: String, CaseIterable, Codable {
    case piano = "Grand Piano"
    case violin = "Violin"
    case viola = "Viola"
    case cello = "Cello"
    case doubleBass = "Double Bass"
    case flute = "Flute"
    case oboe = "Oboe"
    case clarinet = "Clarinet"
    case bassoon = "Bassoon"
    case frenchHorn = "French Horn"
    case trumpet = "Trumpet"
    case trombone = "Trombone"
    case tuba = "Tuba"
    case harp = "Harp"
    case timpani = "Timpani"

    // Piano range octaves on 88-key: A0–C8 (we use 1-7 simplification)
    var playableOctaveRange: ClosedRange<Int> {
        switch self {
        case .piano: return 1...7
        case .violin: return 3...7
        case .viola: return 3...6
        case .cello: return 2...6
        case .doubleBass: return 1...4
        case .flute: return 4...7
        case .oboe: return 4...7
        case .clarinet: return 3...6
        case .bassoon: return 1...4
        case .frenchHorn: return 2...5
        case .trumpet: return 3...6
        case .trombone: return 2...5
        case .tuba: return 1...3
        case .harp: return 1...7
        case .timpani: return 2...4
        }
    }

    var clef: Clef {
        switch self {
        case .cello, .doubleBass, .bassoon, .tuba: return .bass
        case .trombone: return .bass
        default: return .treble
        }
    }
}

enum Clef: String, Codable {
    case treble = "treble"
    case bass = "bass"

    // Middle C (C4) staff line offset from bottom line
    // Treble: C4 is 1 ledger below bottom staff line
    // Bass: C4 is 1 ledger above top staff line
    var middleCOffset: Int {
        switch self {
        case .treble: return -2   // below staff
        case .bass: return 8      // above staff
        }
    }
}

struct Part: Identifiable, Codable {
    var id: UUID = UUID()
    var instrument: InstrumentFamily
    var clef: Clef
    var measures: [Measure] = []
    var label: String { instrument.rawValue }
}

// MARK: - ScoreLayout Presets
enum ScoreLayoutPreset: String, CaseIterable {
    case grandStaff = "Grand Staff (Piano)"
    case chamber = "Chamber Orchestra"
    case symphonyFull = "Full Symphony"

    var instruments: [InstrumentFamily] {
        switch self {
        case .grandStaff:
            return [.piano, .piano]  // treble + bass
        case .chamber:
            return [.violin, .viola, .cello, .doubleBass]
        case .symphonyFull:
            return InstrumentFamily.allCases
        }
    }
}

// MARK: - Score Document
struct ScoreDocument: Identifiable, Codable {
    var id: UUID = UUID()
    var title: String = "Untitled Score"
    var tempo: Int = 80  // BPM
    var parts: [Part] = []
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var version: String = "1.0"

    // Default grand staff
    static func defaultDocument() -> ScoreDocument {
        var doc = ScoreDocument()
        doc.parts = [
            Part(instrument: .piano, clef: .treble, measures: [Measure()]),
            Part(instrument: .piano, clef: .bass, measures: [Measure()])
        ]
        return doc
    }
}
