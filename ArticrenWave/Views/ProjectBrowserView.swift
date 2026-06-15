// ProjectBrowserView.swift — Local score file browser (AshTree IDE style)
// Long press = multi-select, swipe left = delete, swipe right = rename
import SwiftUI
import UniformTypeIdentifiers

@Observable
class ProjectBrowserState {
    var projects: [ScoreFileMeta] = []
    var selectedIDs: Set<UUID> = []
    var isMultiSelecting: Bool = false
    var renameTarget: ScoreFileMeta? = nil
    var renameText: String = ""
    var showNewScoreSheet: Bool = false
    var newScoreTitle: String = "Untitled Score"
    var errorMessage: String? = nil

    static let shared = ProjectBrowserState()

    struct ScoreFileMeta: Identifiable {
        let id: UUID
        var title: String
        var modifiedAt: Date
        var fileURL: URL
        var iCloudSynced: Bool = false

        var formattedDate: String {
            let f = RelativeDateTimeFormatter()
            f.unitsStyle = .abbreviated
            return f.localizedString(for: modifiedAt, relativeTo: Date())
        }
    }

    private var projectsDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir  = docs.appendingPathComponent("ArticrenWave/Projects", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func refresh() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: projectsDir, includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        projects = files
            .filter { $0.pathExtension == "awscore" }
            .compactMap { url -> ScoreFileMeta? in
                let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                let title = url.deletingPathExtension().lastPathComponent
                    .replacingOccurrences(of: "_", with: " ")
                return ScoreFileMeta(
                    id: UUID(),
                    title: title,
                    modifiedAt: attrs?.contentModificationDate ?? Date(),
                    fileURL: url
                )
            }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    func delete(id: UUID) {
        guard let meta = projects.first(where: { $0.id == id }) else { return }
        try? FileManager.default.removeItem(at: meta.fileURL)
        projects.removeAll { $0.id == id }
        selectedIDs.remove(id)
    }

    func deleteSelected() {
        for id in selectedIDs { delete(id: id) }
        selectedIDs.removeAll()
        isMultiSelecting = false
    }

    func rename(id: UUID, to newTitle: String) {
        guard let meta = projects.first(where: { $0.id == id }),
              !newTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let sanitized = newTitle.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "_")
        let newURL = meta.fileURL.deletingLastPathComponent()
            .appendingPathComponent(sanitized).appendingPathExtension("awscore")
        try? FileManager.default.moveItem(at: meta.fileURL, to: newURL)
        refresh()
    }

    func save(document: ScoreDocument) {
        let title = document.title.replacingOccurrences(of: " ", with: "_")
        let url   = projectsDir.appendingPathComponent(
            "\(title)_\(document.id.uuidString.prefix(6)).awscore"
        )
        if let data = try? JSONEncoder().encode(document) {
            try? data.write(to: url, options: .atomicWrite)
        }
        refresh()
    }

    func load(id: UUID) -> ScoreDocument? {
        guard let meta = projects.first(where: { $0.id == id }),
              let data = try? Data(contentsOf: meta.fileURL),
              let doc  = try? JSONDecoder().decode(ScoreDocument.self, from: data)
        else { return nil }
        return doc
    }
}

// MARK: - Project Browser Panel (slide-out from left or shown as sheet)
struct ProjectBrowserView: View {
    @Environment(AppState.self)    private var appState
    @Environment(ScoreEngine.self) private var scoreEngine
    @State private var browser = ProjectBrowserState.shared
    @State private var showingFilePicker = false
    @State private var dragOffset: CGFloat = 0
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0A0B14").ignoresSafeArea()

                VStack(spacing: 0) {
                    // Toolbar
                    browserToolbar

                    // Multi-select action bar
                    if browser.isMultiSelecting && !browser.selectedIDs.isEmpty {
                        multiSelectBar
                    }

                    // File list
                    if browser.projects.isEmpty {
                        emptyState
                    } else {
                        fileList
                    }
                }
            }
            .navigationTitle("Scores")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(hex: "#0A0B14"), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { isPresented = false }
                        .foregroundColor(appState.theme.accent)
                        .fontWeight(.medium)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 14) {
                        Button {
                            browser.isMultiSelecting.toggle()
                            if !browser.isMultiSelecting { browser.selectedIDs.removeAll() }
                        } label: {
                            Image(systemName: browser.isMultiSelecting ? "xmark.circle" : "checkmark.circle")
                                .foregroundColor(browser.isMultiSelecting ? .red : appState.theme.accent)
                        }
                        Button {
                            browser.newScoreTitle = "Untitled Score"
                            browser.showNewScoreSheet = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(appState.theme.accent)
                                .font(.system(size: 20))
                        }
                    }
                }
            }
        }
        .onAppear { browser.refresh() }
        .sheet(isPresented: $browser.showNewScoreSheet) { newScoreSheet }
        .alert("Rename", isPresented: Binding(
            get: { browser.renameTarget != nil },
            set: { if !$0 { browser.renameTarget = nil } }
        )) {
            TextField("Score title", text: $browser.renameText)
                .autocorrectionDisabled()
            Button("Rename") {
                if let target = browser.renameTarget {
                    browser.rename(id: target.id, to: browser.renameText)
                }
                browser.renameTarget = nil
            }
            Button("Cancel", role: .cancel) { browser.renameTarget = nil }
        }
    }

    // MARK: Browser Toolbar (sort / search placeholder)
    var browserToolbar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.white.opacity(0.3))
                .font(.system(size: 13))
            Text("Search scores…")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.25))
            Spacer()
            Text("\(browser.projects.count) score\(browser.projects.count == 1 ? "" : "s")")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.04))
    }

    // MARK: Multi-select action bar
    var multiSelectBar: some View {
        HStack(spacing: 16) {
            Button {
                for proj in browser.projects { browser.selectedIDs.insert(proj.id) }
            } label: {
                Label("All", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(appState.theme.accent)
            }
            Spacer()
            Text("\(browser.selectedIDs.count) selected")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
            Spacer()
            Button(role: .destructive) {
                browser.deleteSelected()
            } label: {
                Label("Delete", systemImage: "trash.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.red.opacity(0.08))
    }

    // MARK: File list
    var fileList: some View {
        List {
            ForEach(browser.projects) { meta in
                ScoreFileRow(
                    meta: meta,
                    isSelected: browser.selectedIDs.contains(meta.id),
                    isMultiSelecting: browser.isMultiSelecting,
                    accent: appState.theme.accent
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    if browser.isMultiSelecting {
                        if browser.selectedIDs.contains(meta.id) {
                            browser.selectedIDs.remove(meta.id)
                        } else {
                            browser.selectedIDs.insert(meta.id)
                        }
                    } else {
                        if let doc = browser.load(id: meta.id) {
                            scoreEngine.document = doc
                            isPresented = false
                        }
                    }
                }
                .onLongPressGesture {
                    browser.isMultiSelecting = true
                    browser.selectedIDs.insert(meta.id)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        browser.delete(id: meta.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button {
                        browser.renameText = meta.title
                        browser.renameTarget = meta
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    .tint(appState.theme.accent)
                }
                .listRowBackground(Color.white.opacity(0.04))
                .listRowSeparatorTint(Color.white.opacity(0.08))
            }
        }
        .listStyle(.plain)
        .background(Color(hex: "#0A0B14"))
        .scrollContentBackground(.hidden)
    }

    // MARK: Empty state
    var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "music.note.list")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.15))
            Text("No Scores Yet")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white.opacity(0.4))
            Text("Tap + to create your first score")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.25))
            Spacer()
        }
    }

    // MARK: New score sheet
    var newScoreSheet: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0A0B14").ignoresSafeArea()
                VStack(spacing: 24) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 52))
                        .foregroundColor(appState.theme.accent)
                        .padding(.top, 32)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Score Title")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                            .kerning(1.5)
                        TextField("Untitled Score", text: $browser.newScoreTitle)
                            .textFieldStyle(.plain)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white)
                            .padding(14)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal, 24)

                    Button {
                        var newDoc = ScoreDocument.defaultDocument()
                        newDoc.title = browser.newScoreTitle.isEmpty ? "Untitled Score" : browser.newScoreTitle
                        scoreEngine.document = newDoc
                        browser.save(document: newDoc)
                        browser.showNewScoreSheet = false
                        isPresented = false
                    } label: {
                        Text("Create Score")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .background(
                                LinearGradient(colors: [appState.theme.accent, appState.theme.accent.opacity(0.7)],
                                               startPoint: .leading, endPoint: .trailing)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal, 24)

                    Spacer()
                }
            }
            .navigationTitle("New Score")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(hex: "#0A0B14"), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { browser.showNewScoreSheet = false }
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
    }
}

// MARK: - Score File Row
struct ScoreFileRow: View {
    let meta: ProjectBrowserState.ScoreFileMeta
    let isSelected: Bool
    let isMultiSelecting: Bool
    let accent: Color

    var body: some View {
        HStack(spacing: 14) {
            // Multi-select indicator
            if isMultiSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? accent : .white.opacity(0.3))
                    .font(.system(size: 20))
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 16))
                    .foregroundColor(accent.opacity(0.7))
                    .frame(width: 28)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(meta.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(meta.formattedDate)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                    if meta.iCloudSynced {
                        Image(systemName: "icloud.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.3))
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.2))
        }
        .padding(.vertical, 4)
        .background(isSelected ? accent.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
