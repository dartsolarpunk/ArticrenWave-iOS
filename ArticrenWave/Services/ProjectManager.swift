// ProjectManager.swift — Save/Load/iCloud for ArticrenWave
import SwiftUI
import CloudKit
import Combine
import UniformTypeIdentifiers

class ProjectManager: ObservableObject {
    @Published var recentProjects: [ProjectMeta] = []
    @Published var isSaving: Bool = false
    @Published var saveError: String? = nil

    struct ProjectMeta: Identifiable, Codable {
        var id: UUID
        var title: String
        var modifiedAt: Date
        var filePath: String
        var iCloudSynced: Bool
    }

    private let fileManager = FileManager.default

    var localProjectsDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("ArticrenWave/Projects", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    var iCloudProjectsDirectory: URL? {
        guard let container = fileManager.url(
            forUbiquityContainerIdentifier: "iCloud.ArticrenWaveAppStore"
        ) else { return nil }
        let dir = container.appendingPathComponent("Documents/Projects", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    init() {
        loadRecentProjects()
    }

    // MARK: - Save
    func save(document: ScoreDocument, toiCloud: Bool = false,
              completion: @escaping (Bool, URL?) -> Void) {
        isSaving = true
        let filename = "\(document.title.replacingOccurrences(of: " ", with: "_"))_\(document.id.uuidString.prefix(8)).awscore"

        let directory = toiCloud ? (iCloudProjectsDirectory ?? localProjectsDirectory) : localProjectsDirectory
        let fileURL = directory.appendingPathComponent(filename)

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                let data = try encoder.encode(document)
                try data.write(to: fileURL, options: .atomicWrite)

                let meta = ProjectMeta(
                    id: document.id,
                    title: document.title,
                    modifiedAt: document.modifiedAt,
                    filePath: fileURL.path,
                    iCloudSynced: toiCloud
                )

                DispatchQueue.main.async {
                    self.isSaving = false
                    self.upsertMeta(meta)
                    completion(true, fileURL)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isSaving = false
                    self.saveError = error.localizedDescription
                    completion(false, nil)
                }
            }
        }
    }

    // MARK: - Load
    func load(from url: URL, completion: @escaping (ScoreDocument?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let data = try Data(contentsOf: url)
                let document = try JSONDecoder().decode(ScoreDocument.self, from: data)
                DispatchQueue.main.async { completion(document) }
            } catch {
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    // MARK: - Export MIDI
    func exportMIDI(from document: ScoreDocument, completion: @escaping (URL?) -> Void) {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(document.title).mid")

        // Build MIDI using AudioEngine helper
        let audioEng = AudioEngine()
        let seq = audioEng.buildMIDISequencePublic(from: document)
        let data = seq.data()

        do {
            try data.write(to: tmpURL)
            completion(tmpURL)
        } catch {
            completion(nil)
        }
    }

    // MARK: - Export PDF
    func exportPDF(scoreView: some View, document: ScoreDocument,
                   completion: @escaping (URL?) -> Void) {
        let renderer = ImageRenderer(content: scoreView)
        renderer.scale = 2.0

        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(document.title).pdf")

        renderer.render { size, context in
            var pdfBox = CGRect(x: 0, y: 0, width: 1240, height: 1754) // A4 portrait
            guard let pdf = CGContext(tmpURL as CFURL, mediaBox: &pdfBox, nil) else { return }
            pdf.beginPDFPage(nil)
            pdf.translateBy(x: 0, y: pdfBox.height - size.height)
            context(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
        }
        completion(tmpURL)
    }

    // MARK: - Recent projects
    private func loadRecentProjects() {
        let metaURL = localProjectsDirectory.appendingPathComponent("_meta.json")
        guard let data = try? Data(contentsOf: metaURL),
              let list = try? JSONDecoder().decode([ProjectMeta].self, from: data) else { return }
        recentProjects = list.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    private func upsertMeta(_ meta: ProjectMeta) {
        if let idx = recentProjects.firstIndex(where: { $0.id == meta.id }) {
            recentProjects[idx] = meta
        } else {
            recentProjects.insert(meta, at: 0)
        }
        saveMeta()
    }

    private func saveMeta() {
        let metaURL = localProjectsDirectory.appendingPathComponent("_meta.json")
        if let data = try? JSONEncoder().encode(recentProjects) {
            try? data.write(to: metaURL)
        }
    }
}

// Expose for ProjectManager
extension AudioEngine {
    func buildMIDISequencePublic(from document: ScoreDocument) -> SimpleMIDISequence {
        return buildMIDISequence(from: document)
    }
}
