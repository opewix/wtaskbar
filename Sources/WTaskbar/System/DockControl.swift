import Foundation

/// Прячет системный Dock так же, как uBar: включает автоскрытие с задержкой в 1000 секунд,
/// после чего Dock не выезжает. Исходное значение автоскрытия запоминаем и возвращаем.
enum DockControl {
    private static let defaults = UserDefaults.standard
    private static let hiddenKey = "dockHiddenByUs"
    private static let originalAutohideKey = "dockOriginalAutohide"

    static func hide() {
        guard !defaults.bool(forKey: hiddenKey) else { return }
        let original = UserDefaults(suiteName: "com.apple.dock")?.bool(forKey: "autohide") ?? false
        defaults.set(original, forKey: originalAutohideKey)
        defaults.set(true, forKey: hiddenKey)
        run("/usr/bin/defaults", ["write", "com.apple.dock", "autohide", "-bool", "true"])
        run("/usr/bin/defaults", ["write", "com.apple.dock", "autohide-delay", "-float", "1000"])
        run("/usr/bin/killall", ["Dock"])
    }

    static func restore() {
        guard defaults.bool(forKey: hiddenKey) else { return }
        let original = defaults.bool(forKey: originalAutohideKey)
        defaults.set(false, forKey: hiddenKey)
        run("/usr/bin/defaults", ["write", "com.apple.dock", "autohide", "-bool", original ? "true" : "false"])
        run("/usr/bin/defaults", ["delete", "com.apple.dock", "autohide-delay"])
        run("/usr/bin/killall", ["Dock"])
    }

    @discardableResult
    static func run(_ tool: String, _ args: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}
