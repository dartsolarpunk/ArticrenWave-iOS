// AWMainLayout.swift — AshTree IDE-style slide-out drawer layout
// Articren Wave · © 2026 DART Meadow LLC & Radical Deepscale LLC
import SwiftUI

struct AWMainLayout: View {
    @Environment(AppState.self)    private var appState
    @Environment(AuthManager.self) private var authManager
    @Environment(ScoreEngine.self) private var scoreEngine

    @State private var drawerTab: AWDrawerTab = .files

    var drawerWidth: CGFloat { min(UIScreen.main.bounds.width * 0.82, 320) }

    /// Single source of truth for open/closed state -- a direct computed binding
    /// onto appState.isMainMenuOpen. Previously this was mirrored across THREE
    /// separate @State variables (this view's showDrawer, MainComposerView's
    /// showMainMenu, and direct writes from MainMenuOverlay) kept in sync via
    /// onChange callbacks in both directions. Any close path that didn't reset
    /// every mirror left the others stale, so re-opening (which only re-set one
    /// of them) produced no visible change since SwiftUI's onChange doesn't fire
    /// when a value is set to what it already equals.
    var showDrawer: Binding<Bool> {
        Binding(
            get: { appState.isMainMenuOpen },
            set: { appState.isMainMenuOpen = $0 }
        )
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Color(hex: "#080910").ignoresSafeArea()

                // ── Main content (shifts right when drawer open) ──
                MainComposerView()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .offset(x: showDrawer.wrappedValue ? drawerWidth : 0)
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showDrawer.wrappedValue)
                    .disabled(showDrawer.wrappedValue)

                // ── Dim overlay ───────────────────────────────────
                if showDrawer.wrappedValue {
                    Color.black.opacity(0.52)
                        .ignoresSafeArea()
                        .offset(x: drawerWidth)
                        .onTapGesture { withAnimation { appState.isMainMenuOpen = false } }
                        .transition(.opacity)
                        .zIndex(5)
                }

                // ── Side drawer ───────────────────────────────────
                AWDrawer(
                    isOpen: showDrawer,
                    activeTab: $drawerTab
                )
                .frame(width: drawerWidth)
                .offset(x: showDrawer.wrappedValue ? 0 : -drawerWidth)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showDrawer.wrappedValue)
                .zIndex(10)
                .ignoresSafeArea()
            }
        }
        .ignoresSafeArea(.keyboard)
    }
}

// MARK: - Drawer Tab Enum
enum AWDrawerTab: String, CaseIterable {
    case files    = "Scores"
    case profile  = "Profile"
    case settings = "Settings"
    case about    = "About"

    var icon: String {
        switch self {
        case .files:    return "music.note.list"
        case .profile:  return "person.circle"
        case .settings: return "gearshape"
        case .about:    return "info.circle"
        }
    }
}

// MARK: - Side Drawer
struct AWDrawer: View {
    @Environment(AppState.self)     private var appState
    @Environment(AuthManager.self)  private var authManager
    @Environment(ScoreEngine.self)  private var scoreEngine
    @Binding var isOpen: Bool
    @Binding var activeTab: AWDrawerTab

    var body: some View {
        VStack(spacing: 0) {
            // Profile header
            AWDrawerHeader(isOpen: $isOpen)

            // Tab pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(AWDrawerTab.allCases, id: \.self) { tab in
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                activeTab = tab
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 10))
                                Text(tab.rawValue)
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(activeTab == tab ? Color(hex: "#0A0B14") : .white.opacity(0.5))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(activeTab == tab ? appState.theme.accent : Color.white.opacity(0.08))
                            .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .background(Color(hex: "#0d1220"))
            .overlay(Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1), alignment: .bottom)

            // Tab content
            switch activeTab {
            case .files:    AWDrawerFilesTab(isOpen: $isOpen)
            case .profile:  AWDrawerProfileTab(isOpen: $isOpen)
            case .settings: AWDrawerSettingsTab()
            case .about:    AWDrawerAboutTab()
            }

            Spacer(minLength: 0)
        }
        .background(Color(hex: "#0A0B14"))
        .ignoresSafeArea()
    }
}

// MARK: - Drawer Header
struct AWDrawerHeader: View {
    @Environment(AppState.self)    private var appState
    @Environment(AuthManager.self) private var authManager
    @Binding var isOpen: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Avatar circle
            ZStack {
                Circle()
                    .fill(appState.theme.accent.opacity(0.2))
                    .frame(width: 46, height: 46)
                Text(authManager.userFullName.prefix(1).uppercased())
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(appState.theme.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(authManager.userFullName.isEmpty ? "Composer" : authManager.userFullName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                if authManager.isGuest {
                    Text("GUEST MODE")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(appState.theme.secondary.opacity(0.8))
                        .kerning(1)
                } else if !authManager.userEmail.isEmpty {
                    Text(authManager.userEmail)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                }
            }

            Spacer()

            Button { withAnimation { isOpen = false } } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(width: 30, height: 30)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 58)
        .padding(.bottom, 14)
        .background(Color(hex: "#0d1220"))
    }
}

// MARK: - Files Tab (AshTree IDE pattern exactly)
struct AWDrawerFilesTab: View {
    @Environment(AppState.self)    private var appState
    @Environment(ScoreEngine.self) private var scoreEngine
    @Binding var isOpen: Bool

    @State private var browser     = ProjectBrowserState.shared
    @State private var selectMode  = false
    @State private var selectedIDs = Set<UUID>()
    @State private var renamingID: UUID? = nil
    @State private var renameText  = ""
    @State private var showNewScore = false
    @State private var newTitle    = "Untitled Score"

    var body: some View {
        VStack(spacing: 0) {
            // Action bar
            HStack(spacing: 8) {
                if selectMode {
                    Button("Done") {
                        selectMode = false; selectedIDs.removeAll()
                    }
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))

                    Spacer()

                    if !selectedIDs.isEmpty {
                        Text("\(selectedIDs.count) selected")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(appState.theme.accent)

                        Button {
                            for id in selectedIDs { browser.delete(id: id) }
                            selectedIDs.removeAll(); selectMode = false
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 13))
                                .foregroundColor(.red)
                        }
                    }
                } else {
                    // New score
                    Button {
                        newTitle = "Untitled Score"; showNewScore = true
                    } label: {
                        Label("New Score", systemImage: "plus.square")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(appState.theme.accent)
                    }

                    Spacer()

                    Text("\(browser.projects.count) score\(browser.projects.count == 1 ? "" : "s")")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.03))
            .overlay(Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1), alignment: .bottom)

            // File list
            if browser.projects.isEmpty {
                VStack(spacing: 14) {
                    Spacer().frame(height: 40)
                    Image(systemName: "music.note.list")
                        .font(.system(size: 40))
                        .foregroundColor(.white.opacity(0.12))
                    Text("No Scores Yet")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white.opacity(0.3))
                    Text("Tap New Score to begin")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.18))
                    Spacer()
                }
            } else {
                List {
                    Section {
                        // Select all row (select mode)
                        if selectMode {
                            Button {
                                if selectedIDs.count == browser.projects.count {
                                    selectedIDs.removeAll()
                                } else {
                                    selectedIDs = Set(browser.projects.map { $0.id })
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: selectedIDs.count == browser.projects.count
                                          ? "checkmark.square.fill" : "square")
                                        .foregroundColor(appState.theme.accent)
                                    Text(selectedIDs.count == browser.projects.count ? "Deselect All" : "Select All")
                                        .font(.system(size: 12))
                                        .foregroundColor(.white)
                                }
                            }
                            .listRowBackground(Color.white.opacity(0.04))
                        }

                        ForEach(browser.projects) { meta in
                            Group {
                                if renamingID == meta.id {
                                    // Inline rename
                                    HStack {
                                        Image(systemName: "pencil")
                                            .foregroundColor(appState.theme.accent)
                                            .font(.system(size: 12))
                                        TextField("Score title", text: $renameText)
                                            .font(.system(size: 13, design: .monospaced))
                                            .foregroundColor(appState.theme.accent)
                                            .autocorrectionDisabled()
                                            .onSubmit { commitRename(id: meta.id) }
                                        Button("Save") { commitRename(id: meta.id) }
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(appState.theme.accent)
                                        Button("✕") { renamingID = nil }
                                            .font(.system(size: 11))
                                            .foregroundColor(.red)
                                    }
                                } else {
                                    // Normal row
                                    Button {
                                        if selectMode {
                                            if selectedIDs.contains(meta.id) { selectedIDs.remove(meta.id) }
                                            else { selectedIDs.insert(meta.id) }
                                        } else {
                                            if let doc = browser.load(id: meta.id) {
                                                scoreEngine.document = doc
                                                withAnimation { isOpen = false }
                                            }
                                        }
                                    } label: {
                                        HStack(spacing: 10) {
                                            if selectMode {
                                                Image(systemName: selectedIDs.contains(meta.id)
                                                      ? "checkmark.circle.fill" : "circle")
                                                    .foregroundColor(selectedIDs.contains(meta.id)
                                                                     ? appState.theme.accent : .white.opacity(0.3))
                                                    .font(.system(size: 16))
                                            } else {
                                                Image(systemName: "music.note")
                                                    .font(.system(size: 14))
                                                    .foregroundColor(appState.theme.accent.opacity(0.7))
                                                    .frame(width: 24)
                                            }
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(meta.title)
                                                    .font(.system(size: 13, weight: .medium))
                                                    .foregroundColor(.white.opacity(0.9))
                                                    .lineLimit(1)
                                                Text(meta.formattedDate)
                                                    .font(.system(size: 10, design: .monospaced))
                                                    .foregroundColor(.white.opacity(0.3))
                                            }
                                            Spacer()
                                            if !selectMode {
                                                Image(systemName: "chevron.right")
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.white.opacity(0.18))
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .contentShape(Rectangle())
                                    .onLongPressGesture {
                                        withAnimation { selectMode = true; selectedIDs.insert(meta.id) }
                                    }
                                    // Swipe left → delete
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            browser.delete(id: meta.id)
                                        } label: { Label("Delete", systemImage: "trash") }
                                    }
                                    // Swipe right → rename
                                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                        Button {
                                            renameText = meta.title
                                            renamingID = meta.id
                                        } label: { Label("Rename", systemImage: "pencil") }
                                            .tint(appState.theme.accent)
                                    }
                                }
                            }
                            .listRowBackground(
                                selectedIDs.contains(meta.id)
                                    ? appState.theme.accent.opacity(0.08)
                                    : Color.white.opacity(0.03)
                            )
                            .listRowSeparatorTint(Color.white.opacity(0.06))
                        }
                    } header: {
                        Text("LOCAL SCORES")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.3))
                            .kerning(1.5)
                    }

                    // Save current
                    Section {
                        Button {
                            browser.save(document: scoreEngine.document)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.down")
                                    .foregroundColor(appState.theme.accent)
                                Text("Save Current Score")
                                    .foregroundColor(appState.theme.accent)
                                    .font(.system(size: 12))
                            }
                        }
                        .listRowBackground(Color.white.opacity(0.03))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color(hex: "#0A0B14"))
            }
        }
        .onAppear { browser.refresh() }
        .sheet(isPresented: $showNewScore) {
            NavigationStack {
                ZStack {
                    Color(hex: "#0A0B14").ignoresSafeArea()
                    VStack(spacing: 20) {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 48))
                            .foregroundColor(appState.theme.accent)
                            .padding(.top, 24)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("SCORE TITLE")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.4))
                                .kerning(1.5)
                            TextField("Untitled Score", text: $newTitle)
                                .textFieldStyle(.plain)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white)
                                .padding(14)
                                .background(Color.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal, 24)
                        Button {
                            var doc = ScoreDocument.defaultDocument()
                            doc.title = newTitle.isEmpty ? "Untitled Score" : newTitle
                            scoreEngine.document = doc
                            browser.save(document: doc)
                            showNewScore = false
                            withAnimation { isOpen = false }
                        } label: {
                            Text("Create Score")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity).frame(height: 52)
                                .background(LinearGradient(colors: [appState.theme.accent, appState.theme.accent.opacity(0.7)],
                                                           startPoint: .leading, endPoint: .trailing))
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
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showNewScore = false }
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }
        }
    }

    func commitRename(id: UUID) {
        browser.rename(id: id, to: renameText)
        renamingID = nil
    }
}

// MARK: - Profile Tab
struct AWDrawerProfileTab: View {
    @Environment(AppState.self)    private var appState
    @Environment(AuthManager.self) private var authManager
    @Binding var isOpen: Bool

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(appState.theme.accent.opacity(0.2)).frame(width: 52, height: 52)
                        Text(authManager.userFullName.prefix(1).uppercased())
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(appState.theme.accent)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(authManager.userFullName.isEmpty ? "Composer" : authManager.userFullName)
                            .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                        if !authManager.userEmail.isEmpty {
                            Text(authManager.userEmail)
                                .font(.system(size: 11)).foregroundColor(.white.opacity(0.4))
                        }
                        if authManager.isGuest {
                            Text("GUEST MODE")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(appState.theme.secondary)
                        }
                    }
                }
                .listRowBackground(Color.white.opacity(0.04))
            } header: {
                Text("ACCOUNT").font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.3)).kerning(1.5)
            }

            Section {
                Button(role: .destructive) {
                    withAnimation {
                        isOpen = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            authManager.signOut()
                        }
                    }
                } label: {
                    Label(authManager.isGuest ? "Exit Guest Mode" : "Sign Out",
                          systemImage: "rectangle.portrait.and.arrow.right")
                        .foregroundColor(.red)
                }
                .listRowBackground(Color.white.opacity(0.04))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(hex: "#0A0B14"))
    }
}

// MARK: - Settings Tab
struct AWDrawerSettingsTab: View {
    @Environment(AppState.self) private var appState
    @AppStorage("aw_debug_console_enabled") private var debugConsoleEnabled = false
    @AppStorage("aw_accent_hex") private var savedAccentHex: String = "#E040FB"
    @State private var showDebugConsole = false

    var accentOptions: [(String, String)] = [
        ("Magenta", "#E040FB"), ("Cyan", "#00E5FF"), ("Green", "#00E676"),
        ("Red", "#FF1744"), ("Blue", "#00B4FF"), ("Gold", "#FFD600"),
        ("Purple", "#AA00FF"), ("Orange", "#FF6D00")
    ]

    var body: some View {
        List {
            Section {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(accentOptions, id: \.0) { name, hex in
                        Button {
                            appState.theme.accent = Color(hex: hex)
                            savedAccentHex = hex   // @AppStorage — real, observed SwiftUI state
                        } label: {
                            VStack(spacing: 5) {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 32, height: 32)
                                    .overlay(Circle().stroke(.white, lineWidth: 2.5)
                                        .opacity(savedAccentHex == hex ? 1 : 0))
                                Text(name)
                                    .font(.system(size: 8))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                            .contentShape(Rectangle())   // whole swatch area is tappable, not just the glyphs
                        }
                        .buttonStyle(.plain)   // List/Section rows otherwise intercept nested Button taps,
                                               // which is why only the very first swatch tapped ever "stuck"
                    }
                }
                .listRowBackground(Color.white.opacity(0.04))
            } header: {
                Text("ACCENT COLOR").font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.3)).kerning(1.5)
            }

            Section {
                Toggle(isOn: $debugConsoleEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Debug Console").foregroundColor(.white)
                        Text("Shows an overlay button with engine/audio logs")
                            .font(.system(size: 11)).foregroundColor(.white.opacity(0.4))
                    }
                }
                .tint(appState.theme.accent)

                if debugConsoleEnabled {
                    Button {
                        showDebugConsole = true
                    } label: {
                        Label("View Debug Log", systemImage: "terminal")
                            .foregroundColor(appState.theme.accent)
                    }
                }
            } header: {
                Text("DEVELOPER").font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.3)).kerning(1.5)
            }
            .listRowBackground(Color.white.opacity(0.04))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(hex: "#0A0B14"))
        .sheet(isPresented: $showDebugConsole) {
            AWDebugConsoleView()
        }
    }
}

// MARK: - Debug Console (view AWAudioPlayer.shared.debugLog)
struct AWDebugConsoleView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var refreshTick = 0
    @State private var exportURL: URL? = nil
    @State private var showShareSheet = false
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    func color(for line: String) -> Color {
        if line.contains("EXCEPTION") || line.contains("FAILURE") || line.contains("ERROR") { return .red }
        if line.contains("[AUTH]") { return .cyan.opacity(0.9) }
        if line.contains("[AUDIO]") { return .white.opacity(0.75) }
        return .white.opacity(0.6)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(AWDebugLog.shared.entries.enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(color(for: line))
                                .id(idx)
                        }
                    }
                    .padding(12)
                }
                .background(Color.black)
                .onReceive(timer) { _ in
                    refreshTick += 1
                    if let last = AWDebugLog.shared.entries.indices.last {
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }
            .navigationTitle("Debug Console")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Clear") { AWDebugLog.shared.clear() }
                        .foregroundColor(.white.opacity(0.6))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        // Exports the FULL log, no matter how large, to a .txt file
                        // for sharing/reuse in other projects or with support.
                        Button {
                            if let url = AWDebugLog.shared.exportToFile() {
                                exportURL = url
                                showShareSheet = true
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let exportURL { ShareSheet(activityItems: [exportURL]) }
        }
    }
}

// MARK: - About Tab
struct AWDrawerAboutTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            Section {
                LabeledContent("App", value: "Articren Wave").foregroundColor(.white)
                LabeledContent("Version", value: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))").foregroundColor(.white)
                LabeledContent("Author", value: "Justin Craig Venable").foregroundColor(.white)
                LabeledContent("Company", value: "DART Meadow LLC").foregroundColor(.white)
                LabeledContent("Engine", value: "LEATR Neural Architecture").foregroundColor(.white)
            } header: {
                Text("ABOUT").font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.3)).kerning(1.5)
            }
            .listRowBackground(Color.white.opacity(0.04))

            Section {
                Link("Radical Deepscale", destination: URL(string: "https://radicaldeepscale.com")!)
                    .foregroundColor(appState.theme.accent)
                Link("DART Meadow", destination: URL(string: "https://dartmeadow.com")!)
                    .foregroundColor(appState.theme.accent)
            } header: {
                Text("LINKS").font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.3)).kerning(1.5)
            }
            .listRowBackground(Color.white.opacity(0.04))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(hex: "#0A0B14"))
    }
}
