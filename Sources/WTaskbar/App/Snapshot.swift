import AppKit

/// `WTaskbar -snapshot <папка>`: рисует панель, «Пуск» и календарь в PNG и выходит.
/// Для README и проверки вида без разрешения на запись экрана. Настройки можно подменить
/// аргументами, не трогая сохранённые: `-snapshot out -combine never -smallButtons YES`.
enum Snapshot {
    static var directory: String? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "-snapshot"), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    static func run(into directory: String) {
        TaskbarModel.shared.start()
        AppCatalog.shared.refresh()
        // Список программ собирается в фоне — ждём его.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let backdrop = NSColor(calibratedRed: 0.10, green: 0.25, blue: 0.45, alpha: 1)
            let bar = TaskbarView(screen: NSScreen.screens[0])
            bar.frame = NSRect(x: 0, y: 0, width: 1440, height: Theme.barScreenHeight)
            save(bar, backdrop: backdrop, to: "\(directory)/taskbar.png")
            let start = StartMenu.makeContent(Settings.theme)
            start.frame = NSRect(origin: .zero, size: StartMenu.size(Settings.theme))
            start.reset()
            save(start, backdrop: backdrop, to: "\(directory)/start.png")
            save(CalendarView(frame: NSRect(x: 0, y: 0, width: 360, height: 430)), backdrop: backdrop, to: "\(directory)/calendar.png")
            let options = OptionsWindow.shared.snapshotView()
            save(options, backdrop: .windowBackgroundColor, to: "\(directory)/options.png")
            exit(0)
        }
    }

    private static func save(_ view: NSView, backdrop: NSColor, to path: String) {
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = Theme.darkAppearance
        let host = BackdropView(frame: view.frame, color: backdrop)
        host.addSubview(view)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        view.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    private final class BackdropView: NSView {
        let color: NSColor
        init(frame: NSRect, color: NSColor) {
            self.color = color
            super.init(frame: frame)
        }
        required init?(coder: NSCoder) { fatalError() }
        override func draw(_ dirtyRect: NSRect) {
            color.setFill()
            bounds.fill()
        }
    }
}
