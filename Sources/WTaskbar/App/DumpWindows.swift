import AppKit

/// `open -n WTaskbar.app --args -dumpWindows <файл>`: пишет, какие окна и на каких столах видит панель,
/// и выходит. Через `open`, иначе разрешение «Универсальный доступ» берётся у терминала.
enum DumpWindows {
    static var path: String? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "-dumpWindows"), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    static func run(into path: String) -> Never {
        var out = ""
        out += "trusted=\(WindowList.isTrusted) spacesAPI=\(SpacePin.isAvailable) currentDesktopOnly=\(Settings.currentDesktopOnly)\n"
        Desktops.update()
        out += "desktops=\(Desktops.current.sorted()) fullScreen=\(Desktops.fullScreen.sorted())\n"
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            for window in WindowList.windows(of: app) ?? [] {
                out += "\(app.localizedName ?? "?") | \(window.title.prefix(50)) | number=\(window.number.map(String.init) ?? "nil") spaces=\(window.desktops) minimized=\(window.minimized) here=\(window.onCurrentDesktop)\n"
            }
        }
        out += "server=\(WindowList.serverWindows().apps.sorted { $0.key < $1.key })\n"
        try? out.write(toFile: path, atomically: true, encoding: .utf8)
        exit(0)
    }
}
