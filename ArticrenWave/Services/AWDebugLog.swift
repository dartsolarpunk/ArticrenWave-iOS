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
        if entries.count > 400 { entries.removeFirst(entries.count - 400) }
        lock.unlock()
    }

    func clear() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }
}
