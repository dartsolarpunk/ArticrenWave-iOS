// AppState.swift — Global UI state for ArticrenWave
import SwiftUI
import Combine

enum AppTheme: String, CaseIterable {
    case darkDefault = "Dark Default"
    case midnight = "Midnight Blue"
    case forest = "Forest Green"
    case crimson = "Crimson"
    case slate = "Slate"

    var background: Color {
        switch self {
        case .darkDefault: return Color(hex: "#0A0A0F")
        case .midnight: return Color(hex: "#050A18")
        case .forest: return Color(hex: "#061209")
        case .crimson: return Color(hex: "#140407")
        case .slate: return Color(hex: "#0D0F14")
        }
    }
    var accent: Color {
        switch self {
        case .darkDefault: return Color(hex: "#E040FB")
        case .midnight: return Color(hex: "#00B4FF")
        case .forest: return Color(hex: "#00E676")
        case .crimson: return Color(hex: "#FF1744")
        case .slate: return Color(hex: "#90CAF9")
        }
    }
    var secondaryAccent: Color {
        switch self {
        case .darkDefault: return Color(hex: "#00E5FF")
        case .midnight: return Color(hex: "#FF9100")
        case .forest: return Color(hex: "#FFEA00")
        case .crimson: return Color(hex: "#FF6D00")
        case .slate: return Color(hex: "#B39DDB")
        }
    }
    var staffColor: Color { Color.white.opacity(0.85) }
    var noteColor: Color { Color.white }
    var surface: Color { background.opacity(0.95) }
    var cardBackground: Color { Color.white.opacity(0.05) }
}

class AppState: ObservableObject {
    @Published var theme: AppTheme = .darkDefault
    @Published var isPianoDrawerOpen: Bool = false
    @Published var isMainMenuOpen: Bool = false
    @Published var orientation: UIDeviceOrientation = UIDevice.current.orientation
    @Published var showingOnboarding: Bool = false

    init() {
        if let saved = UserDefaults.standard.string(forKey: "appTheme"),
           let t = AppTheme(rawValue: saved) {
            theme = t
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(orientationChanged),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }

    @objc private func orientationChanged() {
        DispatchQueue.main.async {
            self.orientation = UIDevice.current.orientation
        }
    }

    func setTheme(_ t: AppTheme) {
        theme = t
        UserDefaults.standard.set(t.rawValue, forKey: "appTheme")
    }
}
