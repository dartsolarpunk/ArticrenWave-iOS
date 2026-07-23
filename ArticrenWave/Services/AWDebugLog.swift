// AWDebugLog.swift — shared, tagged debug console used by every subsystem
// (audio, Sign in with Apple, etc.) so failures are visible in one place
// without needing Xcode attached. Off-screen by default; toggled on via
// Settings > Developer > Debug Console.
import Foundation
import Observation

@Observable
final class AWDebugLog {
    static let shared = AWDebugLog()
    private init() {}

    private(set) var entries: [String] = []
    private let lock = NSLock()

    /// category examples: "AUDIO", "AUTH", "SCORE" — shown as a bracketed tag
    /// so mixed-subsystem logs stay readable in one shared console.
    func log(_ message: String, category: String = "APP") {
        let stamp = String(format: "%.2f", CFAbsoluteTimeGetCurrent().truncatingRemainder(dividingBy: 1000))
        let line = "[\(stamp)] [\(category)] \(message)"
        lock.lock()
        entries.append(line)
        // Generous retention -- a single debugging session can legitimately
        // produce thousands of lines (e.g. a runaway retry loop); keeping only
        // 400 was cutting off exactly the evidence needed to diagnose one.
        if entries.count > 20_000 { entries.removeFirst(entries.count - 20_000) }
        lock.unlock()
    }

    func clear() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }

    /// Write the ENTIRE log (no truncation) to a timestamped .txt file in the
    /// temporary directory and return its URL for sharing/exporting -- e.g. via
    /// the share sheet, AirDrop, or copying into another project for reference.
    func exportToFile() -> URL? {
        lock.lock()
        let snapshot = entries
        lock.unlock()

        guard !snapshot.isEmpty else { return nil }

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "ArticrenWave_DebugLog_\(df.string(from: Date())).txt"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        let header = """
        Articren Wave Debug Log Export
        Generated: \(Date())
        App Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))
        Total entries: \(snapshot.count)
        ================================================================

        """
        let body = snapshot.joined(separator: "\n")

        do {
            try (header + body).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
