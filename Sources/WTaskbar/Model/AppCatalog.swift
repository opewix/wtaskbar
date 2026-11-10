import AppKit

struct AppEntry {
    let url: URL
    let name: String

    init(url: URL, name: String? = nil) {
        self.url = url
        self.name = name ?? Self.name(of: url)
    }

    /// Название программы так, как его показывает Finder, без «.app».
    static func name(of url: URL) -> String {
        FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

/// Все установленные программы — для списка в «Пуске».
final class AppCatalog {
    static let shared = AppCatalog()
    static let changed = Notification.Name("WTaskbarCatalogChanged")

    private(set) var entries: [AppEntry] = []
    private var scanning = false

    /// Пересобирает список в фоне; по готовности рассылает `AppCatalog.changed`.
    func refresh() {
        guard !scanning else { return }
        scanning = true
        DispatchQueue.global(qos: .userInitiated).async {
            let found = Self.scan()
            DispatchQueue.main.async {
                self.entries = found
                self.scanning = false
                NotificationCenter.default.post(name: Self.changed, object: nil)
            }
        }
    }

    private static func scan() -> [AppEntry] {
        let fm = FileManager.default
        let roots = ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"]
        var seen = Set<String>()
        var result: [AppEntry] = []

        func visit(_ dir: URL, depth: Int) {
            guard let children = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }
            for url in children {
                if url.pathExtension == "app" {
                    let path = url.resolvingSymlinksInPath().path
                    guard seen.insert(path).inserted else { continue }
                    let name = fm.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
                    result.append(AppEntry(url: url, name: name))
                } else if depth < 2, (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    // Папки вроде «Утилиты» или «Adobe Photoshop 2025».
                    visit(url, depth: depth + 1)
                }
            }
        }

        for root in roots { visit(URL(fileURLWithPath: root), depth: 0) }
        // Finder лежит среди служебных программ, остальное оттуда в список не нужно.
        let finder = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        if fm.fileExists(atPath: finder.path) {
            result.append(AppEntry(url: finder, name: fm.displayName(atPath: finder.path).replacingOccurrences(of: ".app", with: "")))
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// Значки программ берутся из системы и кешируются.
enum Icons {
    private static var cache: [String: NSImage] = [:]

    static func app(_ url: URL) -> NSImage {
        if let image = cache[url.path] { return image }
        // Safari в /Applications — ссылка, без разрешения пути на значке была бы стрелка ярлыка.
        let image = NSWorkspace.shared.icon(forFile: url.resolvingSymlinksInPath().path)
        cache[url.path] = image
        return image
    }
}
