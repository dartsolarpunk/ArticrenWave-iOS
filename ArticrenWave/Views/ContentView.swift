// ContentView.swift — Root shell (delegates to AWRootView)
// Articren Wave · © 2026 DART Meadow LLC & Radical Deepscale LLC
import SwiftUI

// ContentView is kept for compatibility but AWRootView is the actual root.
// The @main app uses AWRootView directly.
struct ContentView: View {
    var body: some View {
        AWRootView()
    }
}
